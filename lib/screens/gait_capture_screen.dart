import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/theme.dart';
import '../gait/landmark.dart' as gait;
import '../models/gait_session.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';
import 'gait_result_screen.dart';

enum _Phase {
  setup,
  prepFrontal,
  recordFrontal,
  prepSagittal,
  recordSagittal,
  analysing,
  failed,
}

/// One captured frame: JPEG bytes + the path we wrote it to (used to feed
/// `flutter_pose_detection.detectPoseFromFile`). Bytes are kept in-memory so
/// we can ship up to 4 of them to Gemma's multimodal input.
class _Shot {
  _Shot(this.path, this.bytes, this.atMs);
  final String path;
  final Uint8List bytes;
  final int atMs;
}

class GaitCaptureScreen extends ConsumerStatefulWidget {
  const GaitCaptureScreen({super.key, this.lang = 'en', this.age = 'unknown', this.knee = 'right'});
  final String lang;
  final String age;
  final String knee;

  @override
  ConsumerState<GaitCaptureScreen> createState() => _GaitCaptureScreenState();
}

class _GaitCaptureScreenState extends ConsumerState<GaitCaptureScreen> {
  static const _captureSeconds = 5;
  static const _captureIntervalMs = 250;

  CameraController? _camera;
  final NpuPoseDetector _pose = NpuPoseDetector();
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;
  bool _wakeActive = false;
  Future<void>? _poseReady;
  Future<bool>? _sttInitFuture;

  _Phase _phase = _Phase.setup;
  int _countdown = 3;
  String _status = 'Setting up camera…';
  String? _error;

  final List<_Shot> _frontalShots = [];
  final List<_Shot> _sagittalShots = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _wakeActive = false;
    _stt.stop();
    _camera?.dispose();
    _pose.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Kick off pose init NOW — overlaps with camera init's I/O / native
      // setup. Doing this AFTER the preview starts rendering causes a multi-
      // second main-thread stall (GPU contention with the live preview) and
      // an ANR. Doing it now means both heavy loads happen during the
      // "loading…" placeholder phase, where there is no UI to block.
      _poseReady = _pose.initialize();

      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _camera = ctrl;
        _phase = _Phase.prepFrontal;
        _status = 'Walk TOWARD the camera (frontal). Tap start when ready.';
      });

      // STT init also hops onto the main thread; defer until after the first
      // preview frame has had a chance to render so we don't drop frames.
      WidgetsBinding.instance.addPostFrameCallback((_) => _initStt());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'Camera init failed: $e';
      });
    }
  }

  Future<void> _initStt() async {
    if (!mounted || _sttInitFuture != null) return;
    _sttInitFuture = _stt.initialize(onError: (_) {}, onStatus: (_) {});
    try {
      final ok = await _sttInitFuture!;
      if (!mounted) return;
      _sttReady = ok;
      if (ok &&
          (_phase == _Phase.prepFrontal || _phase == _Phase.prepSagittal)) {
        setState(() {
          _status = _phase == _Phase.prepFrontal
              ? 'Walk TOWARD the camera (frontal). Say "kneedle, start recording" or tap start.'
              : 'Now walk SIDEWAYS past the camera (sagittal). Say "kneedle, start recording" or tap start.';
        });
        _startWakeListening();
      }
    } catch (_) {/* STT optional; manual button still works */}
  }

  bool _matchesWake(String text) {
    final t = text.toLowerCase();
    // Tolerate STT mis-hearings of "kneedle": needle / kneadle / kneel.
    final hasName = t.contains('kneedle') ||
        t.contains('needle') ||
        t.contains('kneadle') ||
        t.contains('kneel');
    return hasName && t.contains('start') && t.contains('record');
  }

  Future<void> _startWakeListening() async {
    if (!_sttReady || _wakeActive) return;
    if (_phase != _Phase.prepFrontal && _phase != _Phase.prepSagittal) return;
    _wakeActive = true;
    try {
      while (mounted &&
          _wakeActive &&
          (_phase == _Phase.prepFrontal || _phase == _Phase.prepSagittal)) {
        var triggered = false;
        final done = Completer<void>();
        await _stt.listen(
          localeId: 'en_US',
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          onResult: (r) {
            if (triggered) return;
            if (_matchesWake(r.recognizedWords)) {
              triggered = true;
              if (!done.isCompleted) done.complete();
            } else if (r.finalResult && !done.isCompleted) {
              done.complete();
            }
          },
        );
        await done.future;
        await _stt.stop();
        if (triggered) {
          _wakeActive = false;
          if (!mounted) return;
          if (_phase == _Phase.prepFrontal) {
            _startFlow();
          } else if (_phase == _Phase.prepSagittal) {
            _startSagittal();
          }
          return;
        }
      }
    } catch (_) {
      // STT engine hiccuped; silently fall back to the manual button.
    } finally {
      _wakeActive = false;
    }
  }

  Future<void> _runCapture(List<_Shot> sink, _Phase phase) async {
    _wakeActive = false;
    await _stt.stop();
    setState(() => _phase = phase);
    for (var n = 3; n >= 1; n--) {
      setState(() => _countdown = n);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    setState(() {
      _countdown = 0;
      _status = phase == _Phase.recordFrontal
          ? 'Recording frontal walk…'
          : 'Recording sagittal walk…';
    });

    final dir = await getTemporaryDirectory();
    final t0 = DateTime.now();
    final deadline = t0.add(const Duration(seconds: _captureSeconds));
    var i = 0;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final pic = await _camera!.takePicture();
        final bytes = await File(pic.path).readAsBytes();
        final dst = File('${dir.path}/${phase.name}_$i.jpg');
        await dst.writeAsBytes(bytes, flush: true);
        sink.add(_Shot(
          dst.path,
          bytes,
          DateTime.now().difference(t0).inMilliseconds,
        ));
        i++;
      } catch (_) {
        // skip frame on transient camera error
      }
      // throttle: takePicture itself is slow; only wait the residual.
      await Future.delayed(const Duration(milliseconds: _captureIntervalMs));
    }
  }

  Future<void> _startFlow() async {
    try {
      _frontalShots.clear();
      _sagittalShots.clear();
      await _runCapture(_frontalShots, _Phase.recordFrontal);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.prepSagittal;
        _status = _sttReady
            ? 'Now walk SIDEWAYS past the camera (sagittal). Say "kneedle, start recording" or tap start.'
            : 'Now walk SIDEWAYS past the camera (sagittal). Tap start.';
      });
      _startWakeListening();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'Frontal capture failed: $e';
      });
    }
  }

  Future<void> _startSagittal() async {
    try {
      await _runCapture(_sagittalShots, _Phase.recordSagittal);
      if (!mounted) return;
      await _analyse();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'Sagittal capture failed: $e';
      });
    }
  }

  Future<List<gait.PoseFrame>> _runPoseOn(List<_Shot> shots) async {
    final frames = <gait.PoseFrame>[];
    for (var idx = 0; idx < shots.length; idx++) {
      final s = shots[idx];
      try {
        final result = await _pose.detectPoseFromFile(s.path);
        final p = result.firstPose;
        final landmarks = p == null
            ? null
            : [
                for (final lm in p.landmarks)
                  gait.Landmark(
                    x: lm.x,
                    y: lm.y,
                    z: lm.z,
                    visibility: lm.visibility,
                  ),
              ];
        double confidence = 0;
        if (landmarks != null) {
          double mean(int a, int b, int c) =>
              (landmarks[a].visibility +
                  landmarks[b].visibility +
                  landmarks[c].visibility) /
              3.0;
          final r = mean(gait.Lm.rightHip, gait.Lm.rightKnee, gait.Lm.rightAnkle);
          final l = mean(gait.Lm.leftHip, gait.Lm.leftKnee, gait.Lm.leftAnkle);
          confidence = r > l ? r : l;
        }
        frames.add(gait.PoseFrame(
          frameIdx: idx,
          sampledIdx: idx,
          timeSec: s.atMs / 1000.0,
          landmarks: landmarks,
          confidence: confidence,
        ));
      } catch (_) {
        frames.add(gait.PoseFrame(
          frameIdx: idx,
          sampledIdx: idx,
          timeSec: s.atMs / 1000.0,
          landmarks: null,
          confidence: 0,
        ));
      }
    }
    return frames;
  }

  Future<void> _analyse() async {
    setState(() {
      _phase = _Phase.analysing;
      _status = 'Detecting pose in captured frames…';
    });
    try {
      // Ensure the background pose init finished. Almost always already done
      // by the time captures end (≥10s elapsed), but await for safety.
      if (_poseReady != null) await _poseReady;
      final frontalFrames = await _runPoseOn(_frontalShots);
      final sagittalFrames = await _runPoseOn(_sagittalShots);
      final fps = 1000.0 / _captureIntervalMs;

      setState(() => _status = 'Computing gait metrics…');
      final gaitResult = await ref.read(gaitServiceProvider).analyseFrames(
            frontalFrames: frontalFrames,
            sagittalFrames: sagittalFrames,
            fps: fps,
          );

      setState(() => _status = 'Asking Gemma for guidance…');
      final sessionNumber =
          ref.read(gaitSessionsProvider).length + 1;
      // Sample up to 4 evenly-spaced frontal shots for multimodal context.
      final pickedFrames = <Uint8List>[];
      if (_frontalShots.isNotEmpty) {
        final step = (_frontalShots.length / 4).ceil().clamp(1, 999);
        for (var i = 0; i < _frontalShots.length && pickedFrames.length < 4; i += step) {
          pickedFrames.add(_frontalShots[i].bytes);
        }
      }
      final analysis = await ref.read(gemmaServiceProvider).analyseGait(
            metrics: gaitResult.metrics,
            frames: pickedFrames,
            age: widget.age,
            knee: widget.knee,
            lang: widget.lang,
            sessionNumber: sessionNumber,
          );

      final session = GaitSession.fromMetrics(gaitResult.metrics);
      await StorageService.saveGaitSession(session);
      if (!mounted) return;
      bumpData(ref);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GaitResultScreen(response: analysis),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'Analysis failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gait check')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_phase == _Phase.setup) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_phase == _Phase.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KneedleTheme.space7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: KneedleTheme.dangerTint,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.error_outline_rounded,
                    size: 32, color: KneedleTheme.danger),
              ),
              const SizedBox(height: KneedleTheme.space4),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: KneedleTheme.space2),
              Text(_error ?? '—',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: KneedleTheme.space6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_phase == _Phase.analysing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KneedleTheme.space7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: KneedleTheme.sageTint,
                  borderRadius:
                      BorderRadius.circular(KneedleTheme.radiusLg),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
              const SizedBox(height: KneedleTheme.space5),
              Text('Analysing',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: KneedleTheme.space2),
              Text(_status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    final isRecording =
        _phase == _Phase.recordFrontal || _phase == _Phase.recordSagittal;
    final isPrep =
        _phase == _Phase.prepFrontal || _phase == _Phase.prepSagittal;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_camera != null && _camera!.value.isInitialized)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(KneedleTheme.radiusXl),
                  ),
                  child: CameraPreview(_camera!),
                ),
              if (isRecording && _countdown > 0)
                Center(
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$_countdown',
                      style: const TextStyle(
                        fontSize: 80,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -3,
                      ),
                    ),
                  ),
                ),
              if (isRecording && _countdown == 0)
                Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: KneedleTheme.danger,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: [
                          BoxShadow(
                            color:
                                KneedleTheme.danger.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record,
                              size: 10, color: Colors.white),
                          SizedBox(width: 6),
                          Text('RECORDING',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          color: KneedleTheme.cream,
          padding: const EdgeInsets.fromLTRB(
            KneedleTheme.space5,
            KneedleTheme.space5,
            KneedleTheme.space5,
            KneedleTheme.space6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _phase == _Phase.prepFrontal
                    ? 'Frontal walk'
                    : _phase == _Phase.prepSagittal
                        ? 'Sagittal walk'
                        : 'Hold still',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (isPrep) ...[
                const SizedBox(height: KneedleTheme.space5),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_phase == _Phase.prepFrontal
                      ? 'Start frontal walk'
                      : 'Start sagittal walk'),
                  onPressed: _phase == _Phase.prepFrontal
                      ? _startFlow
                      : _startSagittal,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
