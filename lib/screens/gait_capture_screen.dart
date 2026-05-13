import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;
import 'package:speech_to_text/speech_to_text.dart';

import '../clinical/severity.dart';
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

class GaitCaptureScreen extends ConsumerStatefulWidget {
  const GaitCaptureScreen({super.key, this.lang = 'en', this.age = 'unknown', this.knee = 'right'});
  final String lang;
  final String age;
  final String knee;

  @override
  ConsumerState<GaitCaptureScreen> createState() => _GaitCaptureScreenState();
}

class _GaitCaptureScreenState extends ConsumerState<GaitCaptureScreen> {
  static const _captureSeconds = 8;

  CameraController? _camera;
  // Stream-mode pose detection: lower latency, no full-frame buffering.
  // Same 33-landmark BlazePose topology as the Android side previously used.
  final mlkit.PoseDetector _pose = mlkit.PoseDetector(
    options: mlkit.PoseDetectorOptions(
      mode: mlkit.PoseDetectionMode.stream,
      model: mlkit.PoseDetectionModel.accurate,
    ),
  );
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;
  bool _wakeActive = false;
  Future<void>? _poseReady;
  Future<bool>? _sttInitFuture;

  _Phase _phase = _Phase.setup;
  int _countdown = 3;
  String _status = 'Setting up camera…';
  String? _error;
  bool _canRetry = false;

  // Streaming-capture state. Pose detection runs inline inside the camera's
  // image-stream callback rather than after the fact on JPEGs, so the lists
  // below hold already-extracted pose frames instead of raw shots.
  //
  //  * _captureActive — gate on the callback so frames after stopImageStream
  //    or before startImageStream don't accumulate.
  //  * _isProcessingFrame — semaphore preventing reentry. The camera plugin
  //    delivers frames at ~30 fps; pose inference runs at ~10 fps. When the
  //    detector is busy we drop the incoming frame (camera plugin policy).
  //  * _captureStartedAt — wall-clock reference so each PoseFrame.timeSec is
  //    computed against the recording start, not the absolute clock.
  //  * _frameSeq — monotonic frame index for `PoseFrame.frameIdx`.
  final List<gait.PoseFrame> _frontalShots = [];
  final List<gait.PoseFrame> _sagittalShots = [];
  bool _captureActive = false;
  bool _isProcessingFrame = false;
  DateTime? _captureStartedAt;
  int _frameSeq = 0;

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
    _pose.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // ML Kit's PoseDetector lazy-initialises on the first processImage call;
      // no explicit init step. Leave _poseReady as already-completed so the
      // capture path's `await _poseReady` is a no-op.
      _poseReady = Future.value();

      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        // Required for startImageStream: the camera plugin only delivers raw
        // YUV planes when an explicit format group is requested. On iOS this
        // is silently translated to bgra8888 (the plugin can't honour YUV
        // there) — handled inside the per-frame callback.
        imageFormatGroup: ImageFormatGroup.yuv420,
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

  /// Capture phase using `CameraController.startImageStream`. Pose extraction
  /// runs inline inside the per-frame callback so we accumulate
  /// `gait.PoseFrame`s directly — no JPEG round-trip, no temp-file writes,
  /// no post-capture pose batch. Hard ceiling lifted from ~10 frames per 5s
  /// (takePicture-bound) to whatever the pose detector can sustain (~10-15
  /// fps on this device → 50-75 usable samples per phase).
  Future<void> _runCapture(List<gait.PoseFrame> sink, _Phase phase) async {
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

    // Pose detector must be ready before we start the stream — the first
    // few frames would otherwise be silently dropped on the platform side.
    // Almost always already done by the time we get here.
    if (_poseReady != null) await _poseReady;

    _frameSeq = 0;
    _isProcessingFrame = false;
    _captureStartedAt = DateTime.now();
    _captureActive = true;
    _resetStreamCounters();

    try {
      // The camera-plugin listener signature is void(CameraImage), so we
      // can't `await` the async handler here. The plugin will simply drop
      // further frames while `_isProcessingFrame == true`, which is the
      // backpressure mechanism we want — pose runs serially, camera supplies
      // at native FPS, mismatch resolved by dropping rather than queueing.
      await _camera!.startImageStream((image) {
        _onCameraFrame(image, sink);
      });
      await Future.delayed(const Duration(seconds: _captureSeconds));
    } finally {
      _captureActive = false;
      try {
        await _camera?.stopImageStream();
      } catch (_) {
        // Stream already stopped (e.g. controller disposed) — nothing to do.
      }
      // Drain: an in-flight processFrame may still be settling. Wait briefly
      // so the caller sees a fully-populated sink. The pose detector takes
      // <120ms per frame on this hardware, so a 400ms budget is safe.
      final flushDeadline =
          DateTime.now().add(const Duration(milliseconds: 400));
      while (_isProcessingFrame && DateTime.now().isBefore(flushDeadline)) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      _captureStartedAt = null;
      _logStreamSummary(phase, sink.length);
    }
  }

  // Diagnostic counters: surfaced once per phase via the [_streamSummary] log
  // so we can tell at a glance how the stream pipeline is behaving — how many
  // frames the camera actually delivered, how many were dropped to the busy
  // semaphore, how many failed pose extraction, and the first observed image
  // format/dimensions/rotation triple. Reset at the start of each phase.
  int _framesDelivered = 0;
  int _framesDroppedBusy = 0;
  int _framesErrored = 0;
  String? _firstFrameSummary;
  String? _firstErrorSummary;

  /// Per-frame handler driven by `startImageStream`. Skips reentry while
  /// pose is busy, marshals the CameraImage planes into the plugin's expected
  /// shape, then appends a `gait.PoseFrame` to [sink].
  ///
  /// Errors are caught and counted rather than thrown — one bad frame must
  /// not abort a recording — but the first error of a run is captured with
  /// full type + message so the post-phase summary log can surface it.
  Future<void> _onCameraFrame(
    CameraImage image,
    List<gait.PoseFrame> sink,
  ) async {
    if (!_captureActive) return;
    _framesDelivered++;
    if (_isProcessingFrame) {
      _framesDroppedBusy++;
      return;
    }
    final startedAt = _captureStartedAt;
    if (startedAt == null) return;
    _isProcessingFrame = true;
    final idx = _frameSeq++;
    final tMs = DateTime.now().difference(startedAt).inMilliseconds;
    try {
      // ML Kit consumes a single InputImage built from CameraImage planes.
      // Android camera plugin delivers YUV_420_888 → flattened NV21 bytes;
      // iOS delivers BGRA8888 (single plane). We pass them through directly —
      // ML Kit handles row-stride internally on Android, so no Dart-side
      // repack is needed (the old flutter_pose_detection converter bug is
      // gone with the plugin).
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;
      _firstFrameSummary ??= 'format=${image.format.group}, '
          '${image.width}x${image.height}, '
          'planes=${image.planes.length}, '
          'firstPlaneBytes=${image.planes.first.bytes.length}';
      final poses = await _pose.processImage(inputImage);
      final pose = poses.isEmpty ? null : poses.first;
      final landmarks = pose == null ? null : _buildLandmarkList(pose, image);
      double confidence = 0;
      if (landmarks != null) {
        double meanVis(int a, int b, int c) =>
            (landmarks[a].visibility +
                landmarks[b].visibility +
                landmarks[c].visibility) /
            3.0;
        final r = meanVis(
            gait.Lm.rightHip, gait.Lm.rightKnee, gait.Lm.rightAnkle);
        final l =
            meanVis(gait.Lm.leftHip, gait.Lm.leftKnee, gait.Lm.leftAnkle);
        confidence = r > l ? r : l;
      }
      // Keep null-landmark frames too: the pipeline's `framesSkipped`
      // accounting and diagnostics rely on seeing the full denominator.
      sink.add(gait.PoseFrame(
        frameIdx: idx,
        sampledIdx: sink.length,
        timeSec: tMs / 1000.0,
        landmarks: landmarks,
        confidence: confidence,
      ));
    } catch (e, st) {
      _framesErrored++;
      // For DetectionError specifically, the actual Android-side cause sits
      // in `platformMessage` — the public toString hides it. Use dynamic
      // access so we don't have to import the plugin's private error type.
      String? platformMsg;
      try {
        platformMsg = (e as dynamic).platformMessage as String?;
      } catch (_) {/* not a DetectionError */}
      _firstErrorSummary ??= '${e.runtimeType}: $e'
          '${platformMsg == null ? "" : " | platformMessage=$platformMsg"}'
          '\n${st.toString().split('\n').take(3).join(' | ')}';
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Build a Google ML Kit `InputImage` from the camera plugin's `CameraImage`.
  ///
  /// Android delivers YUV_420_888 across 3 planes; ML Kit's Android side
  /// expects a single flattened NV21 byte buffer. iOS delivers BGRA8888 in
  /// one plane and ML Kit's iOS side wants raw plane bytes + bytesPerRow.
  /// We branch on `Platform` because the plugin's documented contract differs
  /// per-OS.
  InputImage? _buildInputImage(CameraImage image) {
    final cam = _camera?.description;
    if (cam == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(cam.sensorOrientation)
        ?? InputImageRotation.rotation0deg;

    if (Platform.isAndroid) {
      // Flatten YUV_420_888 planes into NV21 (Y followed by interleaved VU).
      final nv21 = _yuv420ToNv21(image);
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    // iOS: BGRA8888, single plane.
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Flatten a CameraImage's YUV_420_888 planes into a single NV21 buffer
  /// (Y followed by interleaved VU). Honours rowStride/pixelStride so the
  /// output is dense regardless of how the camera HAL padded the input.
  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final ySize = width * height;
    final uvSize = ySize ~/ 2;
    final out = Uint8List(ySize + uvSize);

    // Y plane: copy row-by-row, stripping any rowStride padding.
    if (yPlane.bytesPerRow == width) {
      out.setRange(0, ySize, yBytes);
    } else {
      for (var row = 0; row < height; row++) {
        final src = row * yPlane.bytesPerRow;
        out.setRange(row * width, (row + 1) * width, yBytes, src);
      }
    }

    // Chroma: interleave as VU (NV21). pixelStride=2 means U/V already
    // live in the same buffer one byte apart, so we can sometimes bulk-copy;
    // pixelStride=1 (planar) means we need to interleave manually.
    final uPx = uPlane.bytesPerPixel ?? 1;
    final vPx = vPlane.bytesPerPixel ?? 1;
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final uStride = uPlane.bytesPerRow;
    final vStride = vPlane.bytesPerRow;
    final uLen = uBytes.length;
    final vLen = vBytes.length;

    var dst = ySize;
    for (var row = 0; row < uvHeight; row++) {
      final uRow = row * uStride;
      final vRow = row * vStride;
      for (var col = 0; col < uvWidth; col++) {
        final uIdx = uRow + col * uPx;
        final vIdx = vRow + col * vPx;
        out[dst++] = vIdx < vLen ? vBytes[vIdx] : 0;
        out[dst++] = uIdx < uLen ? uBytes[uIdx] : 0;
      }
    }

    return out;
  }

  /// Adapt ML Kit's typed-enum landmark map to the 33-index `List<Landmark>`
  /// the gait pipeline expects (indices defined in [gait.Lm], matching
  /// MediaPipe BlazePose). ML Kit returns landmarks in image-pixel space —
  /// we normalise to [0, 1] against the frame size so the pipeline math
  /// (which is resolution-agnostic) keeps working unchanged.
  List<gait.Landmark> _buildLandmarkList(mlkit.Pose pose, CameraImage image) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final out = List<gait.Landmark>.filled(33, gait.Landmark.zero);
    for (final entry in pose.landmarks.entries) {
      final idx = entry.key.index;
      if (idx < 0 || idx >= 33) continue;
      final lm = entry.value;
      out[idx] = gait.Landmark(
        x: w == 0 ? 0 : lm.x / w,
        y: h == 0 ? 0 : lm.y / h,
        z: lm.z,
        visibility: lm.likelihood,
      );
    }
    return out;
  }

  void _resetStreamCounters() {
    _framesDelivered = 0;
    _framesDroppedBusy = 0;
    _framesErrored = 0;
    _firstFrameSummary = null;
    _firstErrorSummary = null;
  }

  void _logStreamSummary(_Phase phase, int sinkLen) {
    // ignore: avoid_print
    print('[GaitCapture] ${phase.name} stream summary: '
        'delivered=$_framesDelivered, droppedBusy=$_framesDroppedBusy, '
        'errored=$_framesErrored, sinkLen=$sinkLen, '
        'firstFrame=${_firstFrameSummary ?? "<none — callback never fired>"}'
        '${_firstErrorSummary == null ? "" : ", firstError=$_firstErrorSummary"}');
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


  void _restartCapture() {
    setState(() {
      _frontalShots.clear();
      _sagittalShots.clear();
      _error = null;
      _canRetry = false;
      _phase = _Phase.prepFrontal;
      _status = 'Walk TOWARD the camera (frontal). Tap start when ready.';
    });
  }

  Future<void> _analyse() async {
    setState(() {
      _phase = _Phase.analysing;
      _status = 'Computing gait metrics…';
    });
    final total = Stopwatch()..start();
    try {
      // Pose extraction now runs inline during streaming capture — the lists
      // already carry `PoseFrame`s with landmarks. The standalone batch step
      // (the old `_runPoseOn`) is gone, and with it the post-capture wait.
      //
      // Effective fps is computed from the *achieved* sample count over the
      // 5-second capture window rather than a hardcoded interval, because
      // streaming throughput depends on pose-inference latency. The gait
      // pipeline's `targetSampleFps = 30` subsampling clamps to ≥1, so any
      // achieved fps from ~5 to ~30 results in no further subsampling.
      final frontalFps = _frontalShots.length / _captureSeconds;
      final sagittalFps = _sagittalShots.length / _captureSeconds;
      final fps =
          (frontalFps > sagittalFps ? frontalFps : sagittalFps).clamp(1.0, 60.0);

      final metricsSw = Stopwatch()..start();
      final gaitResult = await ref.read(gaitServiceProvider).analyseFrames(
            frontalFrames: _frontalShots,
            sagittalFrames: _sagittalShots,
            fps: fps,
          );
      metricsSw.stop();

      // Gate the expensive LLM call. If the pose pipeline could not extract a
      // bilateral signal (one leg out of frame, too few usable frames, etc.)
      // we'd otherwise hand Gemma a payload full of "not detected" fields and
      // burn minutes of decode for a response we couldn't trust.
      final insufficient = validateMetricsForAnalysis(gaitResult.metrics);
      if (insufficient != null) {
        // ignore: avoid_print
        print('[GaitCapture] metrics insufficient, skipping LLM: '
            '$insufficient');
        if (!mounted) return;
        setState(() {
          _phase = _Phase.failed;
          _error = insufficient;
          _canRetry = true;
        });
        return;
      }

      setState(() => _status = 'Asking Gemma for guidance…');
      final sessionNumber =
          ref.read(gaitSessionsProvider).length + 1;
      final llmSw = Stopwatch()..start();
      final analysis = await ref.read(gemmaServiceProvider).analyseGait(
            metrics: gaitResult.metrics,
            age: widget.age,
            knee: widget.knee,
            lang: widget.lang,
            sessionNumber: sessionNumber,
          );
      llmSw.stop();
      total.stop();
      // ignore: avoid_print
      print('[GaitCapture] analysis timing: '
          'frames=${_frontalShots.length}+${_sagittalShots.length} '
          '(@${fps.toStringAsFixed(1)}fps, pose ran inline during capture), '
          'metrics=${metricsSw.elapsedMilliseconds}ms, '
          'llm=${llmSw.elapsedMilliseconds}ms, '
          'total=${total.elapsedMilliseconds}ms');

      final session = GaitSession.fromMetrics(gaitResult.metrics);
      await StorageService.saveGaitSession(session);
      if (!mounted) return;
      bumpData(ref);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GaitResultScreen(
            response: analysis,
            lang: widget.lang,
          ),
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
              if (_canRetry) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _restartCapture,
                    child: const Text('Record again'),
                  ),
                ),
                const SizedBox(height: KneedleTheme.space3),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ),
              ] else
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
