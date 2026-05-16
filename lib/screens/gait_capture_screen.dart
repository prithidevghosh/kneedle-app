import 'dart:async';
import 'dart:convert';
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
import '../gait/frame_jpeg.dart';
import '../gait/landmark.dart' as gait;
import '../gait/pipeline.dart';
import '../services/gemma_service.dart';
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
  mlkit.PoseDetector? _pose = mlkit.PoseDetector(
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

  // Live progress fed into the animated analysing panel. Updated as the
  // gait pipeline finishes and Gemma streams tokens back.
  String _analysisStage = 'prepare';
  String _analysisMessage = 'Reading pose metrics…';
  String _analysisPartial = '';
  LlmStats? _analysisStats;
  GaitMetrics? _liveMetrics;

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

  // Up to 2 JPEG snapshots per view, captured at ~30% and ~70% of the recording
  // window. Handed to GemmaService.analyseGait so the LLM gets visual context
  // alongside the MediaPipe metrics. See `frame_jpeg.dart` for conversion.
  final List<Uint8List> _frontalImages = [];
  final List<Uint8List> _sagittalImages = [];
  // Wall-clock targets (ms from capture start) at which we encode a JPEG of
  // the next available frame. Kept as a mutable per-phase queue so each
  // _onCameraFrame call can pop the head when it matches.
  final List<int> _pendingSnapshotMs = [];
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
    _pose?.close();
    _pose = null;
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
          // Offline-only recognition — see VoiceService for the rationale.
          listenOptions: SpeechListenOptions(
            onDevice: true,
            partialResults: true,
          ),
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
  Future<void> _runCapture(
    List<gait.PoseFrame> sink,
    List<Uint8List> jpegSink,
    _Phase phase,
  ) async {
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
    // Two snapshots per phase, at ~30% and ~70% of the recording window.
    // Picked so neither falls on the countdown ramp-up nor the trailing
    // stop-walk frame, and both are mid-stride.
    _pendingSnapshotMs
      ..clear()
      ..addAll([
        (_captureSeconds * 1000 * 0.30).round(),
        (_captureSeconds * 1000 * 0.70).round(),
      ]);

    try {
      // The camera-plugin listener signature is void(CameraImage), so we
      // can't `await` the async handler here. The plugin will simply drop
      // further frames while `_isProcessingFrame == true`, which is the
      // backpressure mechanism we want — pose runs serially, camera supplies
      // at native FPS, mismatch resolved by dropping rather than queueing.
      await _camera!.startImageStream((image) {
        _onCameraFrame(image, sink, jpegSink);
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
    List<Uint8List> jpegSink,
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

    // Opportunistically grab a JPEG snapshot if we've crossed the next
    // scheduled snapshot time. Synchronous CPU cost (~30–80ms on this device)
    // sits before pose inference, so we trade one slightly-slower frame per
    // snapshot for not having to keep the raw CameraImage alive past the
    // callback.
    if (_pendingSnapshotMs.isNotEmpty && tMs >= _pendingSnapshotMs.first) {
      _pendingSnapshotMs.removeAt(0);
      try {
        final sensor = _camera?.description.sensorOrientation ?? 0;
        final jpeg =
            encodeCameraImageAsJpeg(image, sensorOrientation: sensor);
        if (jpeg != null) {
          jpegSink.add(jpeg);
          // ignore: avoid_print
          print('[GaitCapture] captured JPEG snapshot '
              '#${jpegSink.length} @ ${tMs}ms (${jpeg.length} bytes)');
        }
      } catch (e) {
        // ignore: avoid_print
        print('[GaitCapture] JPEG snapshot failed at ${tMs}ms: $e');
      }
    }
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
      final detector = _pose;
      if (detector == null) return;
      final poses = await detector.processImage(inputImage);
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
      _frontalImages.clear();
      _sagittalImages.clear();
      await _runCapture(_frontalShots, _frontalImages, _Phase.recordFrontal);
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
      await _runCapture(_sagittalShots, _sagittalImages, _Phase.recordSagittal);
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
      _frontalImages.clear();
      _sagittalImages.clear();
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
      _analysisStage = 'prepare';
      _analysisMessage = 'Crunching pose keypoints…';
      _analysisPartial = '';
      _analysisStats = null;
      _liveMetrics = null;
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
      if (mounted) {
        setState(() {
          _liveMetrics = gaitResult.metrics;
          _analysisStage = 'metrics';
          _analysisMessage =
              'Pose pipeline done in ${metricsSw.elapsedMilliseconds}ms';
        });
      }

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
      // Release the camera before invoking the LLM. The camera preview's
      // SurfaceView and LiteRT's GPU delegate share the device's OpenCL
      // command queue; when both are active the queue can fail mid-decode
      // with CL_INVALID_COMMAND_QUEUE (error -36), and Gemma falls back to
      // the safety-default response. Disposing entirely (not just pausing)
      // ensures Android also frees the surface buffers. The user navigates
      // away on success (pushReplacement) so the controller isn't needed
      // again; on failure we never return to the capture phase from here.
      try {
        await _camera?.dispose();
        _camera = null;
      } catch (_) {/* best-effort */}
      // Also close the ML Kit pose detector before invoking the LLM. On
      // Android, PoseDetector runs through TFLite's GPU delegate and holds
      // an OpenCL command queue; if it's still alive when LiteRT-LM starts
      // decoding, the queue gets invalidated mid-stream and the native
      // executor fails with CL_INVALID_COMMAND_QUEUE (error -36). Pose work
      // is complete by this point (all frames already processed), so it's
      // safe to release the detector entirely. dispose() will no-op the
      // second close on screen teardown.
      try {
        await _pose?.close();
        _pose = null;
      } catch (_) {/* best-effort */}
      final sessionNumber =
          ref.read(gaitSessionsProvider).length + 1;
      final llmSw = Stopwatch()..start();
      final analysis = await ref.read(gemmaServiceProvider).analyseGait(
            metrics: gaitResult.metrics,
            age: widget.age,
            knee: widget.knee,
            lang: widget.lang,
            sessionNumber: sessionNumber,
            frontalFrames: _frontalImages,
            sagittalFrames: _sagittalImages,
            onEvent: (e) {
              if (!mounted) return;
              setState(() {
                _analysisStage = e.stage;
                if (e.message.isNotEmpty) _analysisMessage = e.message;
                if (e.partial.isNotEmpty) _analysisPartial = e.partial;
                if (e.stats != null) _analysisStats = e.stats;
              });
            },
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

      // Persist the full analysis JSON alongside the metrics so the result
      // screen can be reopened from history without re-running Gemma.
      final session = GaitSession.fromMetrics(
        gaitResult.metrics,
        analysisJson: jsonEncode(analysis.toContextJson()),
      );
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
      return _AnalysisProgressView(
        frontalImages: _frontalImages,
        sagittalImages: _sagittalImages,
        metrics: _liveMetrics,
        stage: _analysisStage,
        message: _analysisMessage,
        partial: _analysisPartial,
        stats: _analysisStats,
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

// ─── Animated analysing screen ─────────────────────────────────────────────

/// Interactive "we're thinking" panel shown while the gait pipeline + Gemma
/// finish. Replaces a plain spinner with:
///   * a deck of the 4 captured JPEGs with a sweeping scan-line overlay,
///   * an animated stick figure annotated with the live MediaPipe angles,
///   * a stage stepper (Pose → Vision → Plan) driven by `stage`,
///   * a live "Gemma is drafting" text panel that streams in tokens,
///   * a tokens-per-second pill that ticks up as Gemma decodes.
class _AnalysisProgressView extends StatefulWidget {
  const _AnalysisProgressView({
    required this.frontalImages,
    required this.sagittalImages,
    required this.metrics,
    required this.stage,
    required this.message,
    required this.partial,
    required this.stats,
  });

  final List<Uint8List> frontalImages;
  final List<Uint8List> sagittalImages;
  final GaitMetrics? metrics;
  final String stage;
  final String message;
  final String partial;
  final LlmStats? stats;

  @override
  State<_AnalysisProgressView> createState() => _AnalysisProgressViewState();
}

class _AnalysisProgressViewState extends State<_AnalysisProgressView>
    with TickerProviderStateMixin {
  late final AnimationController _scan;
  late final AnimationController _pulse;
  late final AnimationController _carousel;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _carousel = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _scan.dispose();
    _pulse.dispose();
    _carousel.dispose();
    super.dispose();
  }

  int get _stageIndex => switch (widget.stage) {
        'prepare' => 0,
        'metrics' => 1,
        'prefill' => 2,
        'streaming' => 3,
        'parse' || 'done' => 4,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final frames = [...widget.frontalImages, ...widget.sagittalImages];
    return Container(
      color: KneedleTheme.cream,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          KneedleTheme.space5,
          KneedleTheme.space6,
          KneedleTheme.space5,
          KneedleTheme.space6,
        ),
        children: [
          _StageStepper(stageIndex: _stageIndex),
          const SizedBox(height: KneedleTheme.space5),
          if (frames.isNotEmpty)
            _FrameDeck(
              frames: frames,
              labels: [
                for (var i = 0; i < widget.frontalImages.length; i++)
                  'Frontal · ${i == 0 ? 'mid' : 'late'}',
                for (var i = 0; i < widget.sagittalImages.length; i++)
                  'Sagittal · ${i == 0 ? 'mid' : 'late'}',
              ],
              scan: _scan,
              carousel: _carousel,
            ),
          const SizedBox(height: KneedleTheme.space5),
          _BodyAngleDiagram(
            metrics: widget.metrics,
            pulse: _pulse,
          ),
          const SizedBox(height: KneedleTheme.space5),
          _ThinkingPanel(
            stage: widget.stage,
            message: widget.message,
            partial: widget.partial,
            stats: widget.stats,
            pulse: _pulse,
          ),
        ],
      ),
    );
  }
}

class _StageStepper extends StatelessWidget {
  const _StageStepper({required this.stageIndex});
  final int stageIndex;

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('Pose', Icons.accessibility_new_rounded),
      ('Metrics', Icons.straighten_rounded),
      ('Vision', Icons.image_search_rounded),
      ('Reasoning', Icons.psychology_alt_rounded),
      ('Plan', Icons.checklist_rounded),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: _StageDot(
              label: steps[i].$1,
              icon: steps[i].$2,
              active: i == stageIndex,
              done: i < stageIndex,
            ),
          ),
          if (i < steps.length - 1)
            Container(
              width: 12,
              height: 2,
              color: i < stageIndex
                  ? KneedleTheme.sage
                  : KneedleTheme.hairline,
            ),
        ],
      ],
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({
    required this.label,
    required this.icon,
    required this.active,
    required this.done,
  });
  final String label;
  final IconData icon;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final Color bg = done
        ? KneedleTheme.sage
        : active
            ? KneedleTheme.sageTint
            : KneedleTheme.surface;
    final Color fg = done
        ? Colors.white
        : active
            ? KneedleTheme.sageDeep
            : KneedleTheme.inkFaint;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? KneedleTheme.sage : KneedleTheme.hairline,
              width: active ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(done ? Icons.check_rounded : icon, size: 18, color: fg),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? KneedleTheme.sageDeep : KneedleTheme.inkFaint,
          ),
        ),
      ],
    );
  }
}

class _FrameDeck extends StatelessWidget {
  const _FrameDeck({
    required this.frames,
    required this.labels,
    required this.scan,
    required this.carousel,
  });
  final List<Uint8List> frames;
  final List<String> labels;
  final AnimationController scan;
  final AnimationController carousel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: frames.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _FrameTile(
          bytes: frames[i],
          label: i < labels.length ? labels[i] : 'Frame ${i + 1}',
          scan: scan,
          carousel: carousel,
          delay: i * 0.18,
        ),
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.bytes,
    required this.label,
    required this.scan,
    required this.carousel,
    required this.delay,
  });
  final Uint8List bytes;
  final String label;
  final AnimationController scan;
  final AnimationController carousel;
  final double delay;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            // Sage tint so the scan line reads as "being analyzed".
            Container(color: KneedleTheme.sage.withValues(alpha: 0.18)),
            AnimatedBuilder(
              animation: scan,
              builder: (_, __) {
                final t = (scan.value + delay) % 1.0;
                return Align(
                  alignment: Alignment(0, -1 + 2 * t),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          KneedleTheme.sage.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: KneedleTheme.sage.withValues(alpha: 0.6),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyAngleDiagram extends StatelessWidget {
  const _BodyAngleDiagram({required this.metrics, required this.pulse});
  final GaitMetrics? metrics;
  final AnimationController pulse;

  String _fmtAngle(num? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°';

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final pills = <_AnglePill>[
      _AnglePill(
        label: 'Right knee',
        value: _fmtAngle(m?.kneeAngleRight),
        color: KneedleTheme.sage,
        ready: m != null,
      ),
      _AnglePill(
        label: 'Left knee',
        value: _fmtAngle(m?.kneeAngleLeft),
        color: KneedleTheme.sage,
        ready: m != null,
      ),
      _AnglePill(
        label: 'Symmetry',
        value: m?.symmetryScore == null
            ? '—'
            : '${m!.symmetryScore!.toStringAsFixed(0)}/100',
        color: KneedleTheme.amber,
        ready: m?.symmetryScore != null,
      ),
      _AnglePill(
        label: 'Trunk lean',
        value: _fmtAngle(m?.trunkLeanAngle),
        color: KneedleTheme.sageDeep,
        ready: m?.trunkLeanAngle != null,
      ),
      _AnglePill(
        label: 'Cadence',
        value: m?.cadence == null
            ? '—'
            : '${m!.cadence!.toStringAsFixed(0)} spm',
        color: KneedleTheme.sageDeep,
        ready: m?.cadence != null,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(KneedleTheme.space5),
      decoration: BoxDecoration(
        color: KneedleTheme.surface,
        borderRadius: BorderRadius.circular(KneedleTheme.radiusXl),
        border: Border.all(color: KneedleTheme.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (_, __) {
              final t = pulse.value;
              return SizedBox(
                width: 96,
                height: 140,
                child: CustomPaint(
                  painter: _StickFigurePainter(
                    pulse: t,
                    accent: KneedleTheme.sage,
                    inactive: KneedleTheme.hairline,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: KneedleTheme.space4),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final p in pills) p],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnglePill extends StatelessWidget {
  const _AnglePill({
    required this.label,
    required this.value,
    required this.color,
    required this.ready,
  });
  final String label;
  final String value;
  final Color color;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ready ? color.withValues(alpha: 0.14) : KneedleTheme.cream,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: ready ? color.withValues(alpha: 0.45) : KneedleTheme.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ready ? color : KneedleTheme.inkFaint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label  ',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: KneedleTheme.inkMuted,
              letterSpacing: 0.2,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ready ? KneedleTheme.ink : KneedleTheme.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickFigurePainter extends CustomPainter {
  _StickFigurePainter({
    required this.pulse,
    required this.accent,
    required this.inactive,
  });
  final double pulse;
  final Color accent;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final head = Offset(cx, size.height * 0.10);
    final neck = Offset(cx, size.height * 0.22);
    final hipL = Offset(cx - 14, size.height * 0.50);
    final hipR = Offset(cx + 14, size.height * 0.50);
    final kneeL = Offset(cx - 18, size.height * 0.70);
    final kneeR = Offset(cx + 18, size.height * 0.70);
    final ankleL = Offset(cx - 22, size.height * 0.92);
    final ankleR = Offset(cx + 22, size.height * 0.92);
    final shoulderL = Offset(cx - 18, size.height * 0.28);
    final shoulderR = Offset(cx + 18, size.height * 0.28);
    final handL = Offset(cx - 28, size.height * 0.50);
    final handR = Offset(cx + 28, size.height * 0.50);

    final body = Paint()
      ..color = inactive
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(head, 9, body);
    canvas.drawLine(neck, Offset(cx, size.height * 0.55), body);
    canvas.drawLine(shoulderL, shoulderR, body);
    canvas.drawLine(shoulderL, handL, body);
    canvas.drawLine(shoulderR, handR, body);
    canvas.drawLine(hipL, hipR, body);
    canvas.drawLine(hipL, kneeL, body);
    canvas.drawLine(hipR, kneeR, body);
    canvas.drawLine(kneeL, ankleL, body);
    canvas.drawLine(kneeR, ankleR, body);

    // Glowing knee markers — pulse alpha so it reads as "being measured".
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.35 + 0.55 * pulse)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(kneeL, 7 + 3 * pulse, glow);
    canvas.drawCircle(kneeR, 7 + 3 * pulse, glow);
    final dot = Paint()..color = accent;
    canvas.drawCircle(kneeL, 4, dot);
    canvas.drawCircle(kneeR, 4, dot);
  }

  @override
  bool shouldRepaint(covariant _StickFigurePainter old) =>
      old.pulse != pulse || old.accent != accent;
}

class _ThinkingPanel extends StatelessWidget {
  const _ThinkingPanel({
    required this.stage,
    required this.message,
    required this.partial,
    required this.stats,
    required this.pulse,
  });
  final String stage;
  final String message;
  final String partial;
  final LlmStats? stats;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    final isStreaming = stage == 'streaming';
    return Container(
      padding: const EdgeInsets.all(KneedleTheme.space5),
      decoration: BoxDecoration(
        color: KneedleTheme.surface,
        borderRadius: BorderRadius.circular(KneedleTheme.radiusXl),
        border: Border.all(color: KneedleTheme.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isStreaming
                        ? KneedleTheme.sage
                            .withValues(alpha: 0.4 + 0.6 * pulse.value)
                        : KneedleTheme.amber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (stats != null) _TpsPill(stats: stats!),
            ],
          ),
          const SizedBox(height: KneedleTheme.space3),
          if (partial.isEmpty)
            Text(
              isStreaming
                  ? 'Gemma is warming up the vision encoder…'
                  : 'Setting up the on-device model…',
              style: const TextStyle(
                fontSize: 13,
                color: KneedleTheme.inkMuted,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                reverse: true,
                physics: const BouncingScrollPhysics(),
                child: Text(
                  // Show the tail so the user follows the latest tokens.
                  partial.length > 900
                      ? '…${partial.substring(partial.length - 900)}'
                      : partial,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: KneedleTheme.inkMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TpsPill extends StatelessWidget {
  const _TpsPill({required this.stats});
  final LlmStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: KneedleTheme.sageTint,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded,
              size: 14, color: KneedleTheme.sageDeep),
          const SizedBox(width: 3),
          Text(
            '${stats.tokensPerSecond.toStringAsFixed(1)} tok/s',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: KneedleTheme.sageDeep,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
