import 'dart:async';
import 'dart:isolate';

import '../gait/landmark.dart';
import '../gait/pipeline.dart';

/// Live result emitted to the UI for each processed sample.
class GaitResult {
  GaitResult({required this.metrics, required this.extra});
  final GaitMetrics metrics;
  final Map<String, Object?> extra;
}

/// Request payload sent into the worker isolate.
class _GaitRequest {
  _GaitRequest(this.frontal, this.sagittal);
  final PoseSample frontal;
  final PoseSample sagittal;
}

/// Worker-isolate-backed gait pipeline.
///
/// The UI / camera layer collects pose frames (via `flutter_pose_detection`
/// adapted to [PoseFrame]) and calls [analyse] with one frontal sample bundle
/// and one sagittal sample bundle. The heavy math runs in a long-lived
/// background isolate so the UI thread is never blocked.
class GaitService {
  GaitService._();
  static final GaitService instance = GaitService._();

  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final _requests = <int, Completer<GaitResult>>{};
  int _seq = 0;
  Completer<void>? _readyCompleter;

  Future<void> start() async {
    if (_isolate != null) return;
    _readyCompleter = Completer<void>();
    _receivePort.listen(_onMessage);

    _isolate = await Isolate.spawn<SendPort>(
      _entryPoint,
      _receivePort.sendPort,
      debugName: 'gait-pipeline',
    );

    return _readyCompleter!.future;
  }

  void _onMessage(dynamic msg) {
    if (msg is SendPort) {
      _sendPort = msg;
      _readyCompleter?.complete();
      return;
    }
    if (msg is Map && msg['type'] == 'result') {
      final id = msg['id'] as int;
      final completer = _requests.remove(id);
      completer?.complete(
        GaitResult(
          metrics: msg['metrics'] as GaitMetrics,
          extra: (msg['extra'] as Map).cast<String, Object?>(),
        ),
      );
    } else if (msg is Map && msg['type'] == 'error') {
      final id = msg['id'] as int;
      final completer = _requests.remove(id);
      completer?.completeError(StateError(msg['error'] as String));
    }
  }

  /// Run the pipeline once over a paired frontal / sagittal sample bundle.
  Future<GaitResult> analyse({
    required PoseSample frontal,
    required PoseSample sagittal,
  }) async {
    if (_sendPort == null) await start();
    final id = ++_seq;
    final completer = Completer<GaitResult>();
    _requests[id] = completer;
    _sendPort!.send({
      'id': id,
      'request': _GaitRequest(frontal, sagittal),
    });
    return completer.future;
  }

  /// Convenience entry for simple "list of frames per view" callers (e.g. a
  /// recorded session). [fps] is the camera capture frame-rate.
  Future<GaitResult> analyseFrames({
    required List<PoseFrame> frontalFrames,
    required List<PoseFrame> sagittalFrames,
    required double fps,
  }) {
    return analyse(
      frontal: PoseSample.fromFrames(frontalFrames, fps),
      sagittal: PoseSample.fromFrames(sagittalFrames, fps),
    );
  }

  Future<void> stop() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  // ─── Isolate entry point ──────────────────────────────────────────────────
  static void _entryPoint(SendPort hostPort) {
    final port = ReceivePort();
    hostPort.send(port.sendPort);
    port.listen((msg) {
      try {
        final id = (msg as Map)['id'] as int;
        final req = msg['request'] as _GaitRequest;
        final res = analyseGaitDual(
          frontal: req.frontal,
          sagittal: req.sagittal,
        );
        hostPort.send({
          'type': 'result',
          'id': id,
          'metrics': res.metrics,
          'extra': res.extra,
        });
      } catch (e) {
        hostPort.send({
          'type': 'error',
          'id': (msg as Map)['id'],
          'error': e.toString(),
        });
      }
    });
  }
}
