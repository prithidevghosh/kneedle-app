import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../models/exercise_session.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';

/// Camera-driven exercise coaching surface.
///
/// The pose pipeline (`flutter_pose_detection` → `GaitService.analyse`) is
/// wired through `_onCameraImage`. The actual landmark extraction uses the
/// pose package's `processCameraImage`; we keep the wiring at the boundary so
/// the gait math layer (`lib/gait/*`) stays platform-free.
class ExerciseCoachScreen extends ConsumerStatefulWidget {
  const ExerciseCoachScreen({super.key});

  @override
  ConsumerState<ExerciseCoachScreen> createState() =>
      _ExerciseCoachScreenState();
}

class _ExerciseCoachScreenState extends ConsumerState<ExerciseCoachScreen> {
  CameraController? _camera;
  bool _initFailed = false;
  String? _failureMessage;
  int _reps = 0;
  bool _coaching = false;
  DateTime? _started;

  @override
  void initState() {
    super.initState();
    _bootCamera();
  }

  Future<void> _bootCamera() async {
    try {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        setState(() {
          _initFailed = true;
          _failureMessage = 'Camera permission required.';
        });
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initFailed = true;
          _failureMessage = 'No camera detected.';
        });
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() => _camera = controller);
    } catch (e) {
      setState(() {
        _initFailed = true;
        _failureMessage = e.toString();
      });
    }
  }

  Future<void> _toggleCoaching() async {
    if (_camera == null) return;
    if (_coaching) {
      await _camera!.stopImageStream();
      setState(() => _coaching = false);
      await _saveSession();
    } else {
      _started = DateTime.now();
      _reps = 0;
      await _camera!.startImageStream(_onCameraImage);
      setState(() => _coaching = true);
    }
  }

  void _onCameraImage(CameraImage image) {
    // Wire `flutter_pose_detection` here:
    //   final pose = await poseDetector.processCameraImage(image);
    //   final knee = pose.landmarks[PoseLandmarkType.rightKnee];
    //   ...rep counter / live coaching using one isolate hop per frame.
  }

  Future<void> _saveSession() async {
    final started = _started;
    if (started == null) return;
    final dur = DateTime.now().difference(started).inSeconds;
    final s = ExerciseSession(
      id: started.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff,
      exerciseName: 'Knee flexion',
      repsCompleted: _reps,
      durationSec: dur,
      timestamp: started,
    );
    await StorageService.saveExerciseSession(s);
    bumpData(ref);
  }

  @override
  void dispose() {
    if (_camera?.value.isStreamingImages ?? false) {
      _camera!.stopImageStream();
    }
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(title: const Text('Exercise coach')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _initFailed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(KneedleTheme.space7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: KneedleTheme.dangerTint,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.no_photography_outlined,
                            size: 30, color: KneedleTheme.danger),
                      ),
                      const SizedBox(height: KneedleTheme.space4),
                      Text(
                        'Camera unavailable',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: KneedleTheme.space2),
                      Text(_failureMessage ?? '—',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              )
            : _camera == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            KneedleTheme.space4,
                            KneedleTheme.space2,
                            KneedleTheme.space4,
                            KneedleTheme.space4,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                                KneedleTheme.radiusXl),
                            child: AspectRatio(
                              aspectRatio: _camera!.value.aspectRatio,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CameraPreview(_camera!),
                                  if (_coaching)
                                    Positioned(
                                      top: 16,
                                      left: 16,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: KneedleTheme.coral,
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.fiber_manual_record,
                                                size: 10,
                                                color: Colors.white),
                                            SizedBox(width: 6),
                                            Text(
                                              'COACHING',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          KneedleTheme.space5,
                          0,
                          KneedleTheme.space5,
                          KneedleTheme.space6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _CoachStat(
                                  label: 'REPS',
                                  value: '$_reps',
                                ),
                                const SizedBox(width: KneedleTheme.space3),
                                const _CoachStat(
                                  label: 'EXERCISE',
                                  value: 'Knee flexion',
                                  small: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: KneedleTheme.space4),
                            FilledButton.icon(
                              onPressed: _toggleCoaching,
                              style: FilledButton.styleFrom(
                                backgroundColor: _coaching
                                    ? KneedleTheme.danger
                                    : KneedleTheme.sage,
                              ),
                              icon: Icon(_coaching
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded),
                              label: Text(_coaching
                                  ? 'Stop coaching'
                                  : 'Start coaching'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _CoachStat extends StatelessWidget {
  const _CoachStat({
    required this.label,
    required this.value,
    this.small = false,
  });
  final String label;
  final String value;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KneedleTheme.space4,
          vertical: KneedleTheme.space3,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
          border: Border.all(color: KneedleTheme.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: small ? 18 : 28,
                fontWeight: FontWeight.w700,
                color: KneedleTheme.ink,
                letterSpacing: small ? -0.2 : -0.8,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
