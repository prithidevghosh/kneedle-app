/// Pose-package-independent landmark for the gait math layer.
///
/// `flutter_pose_detection` (and any future pose backend) is adapted to this
/// shape at the service boundary so the gait pipeline stays a pure-Dart
/// library that can run inside an `Isolate` with no Flutter dependency.
class Landmark {
  const Landmark({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  /// Image-space, normalised [0, 1].
  final double x;
  final double y;

  /// Depth, MediaPipe single-camera estimate. Noisy — gait math intentionally
  /// uses 2D only (matches Python implementation, see calculate_angle).
  final double z;

  /// MediaPipe per-landmark visibility, [0, 1].
  final double visibility;

  static const Landmark zero =
      Landmark(x: 0, y: 0, z: 0, visibility: 0);
}

/// MediaPipe BlazePose 33-landmark indices used by the gait pipeline.
///
/// Names mirror `mp.solutions.pose.PoseLandmark` so the Python port reads 1:1.
class Lm {
  Lm._();

  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
  static const int leftHeel = 29;
  static const int rightHeel = 30;
  static const int leftFootIndex = 31;
  static const int rightFootIndex = 32;
}

/// One frame of pose data, sampled from the camera/video pipeline.
class PoseFrame {
  PoseFrame({
    required this.frameIdx,
    required this.sampledIdx,
    required this.timeSec,
    required this.landmarks,
    required this.confidence,
  });

  final int frameIdx;
  final int sampledIdx;
  final double timeSec;

  /// Null when MediaPipe failed to detect any pose in this frame.
  final List<Landmark>? landmarks;

  /// Frame-level confidence: max(rightSideMean, leftSideMean) of hip+knee+ankle
  /// visibility. See `_run_mediapipe` in gait_analyzer.py for rationale.
  final double confidence;
}
