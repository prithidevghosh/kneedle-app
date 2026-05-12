/// Tuning constants — ported verbatim from `gait_analyzer.py`.
///
/// Any change to these values changes the clinical interpretation of the
/// pipeline output. Do not adjust without a paired adjustment to KL-proxy
/// scoring thresholds.
class GaitConst {
  GaitConst._();

  /// Effective per-second sample rate after frame skipping.
  static const double targetSampleFps = 30.0;

  /// Minimum mean lower-body landmark visibility for a frame to count as
  /// analysed. Below this MediaPipe is too unsure to feed clinical metrics.
  static const double minFrameConfidence = 0.6;

  /// Minimum per-landmark visibility for that landmark to participate in an
  /// angle calculation. Lowered from the backend's 0.5 to 0.3 because in a
  /// hand-held / single-pass tripod sagittal recording the FAR-side leg is
  /// occluded for most of the gait cycle and MediaPipe assigns it visibility
  /// in the 0.3-0.5 band (its predicted-occluded estimates). At 0.5 we get
  /// zero far-side knee samples and `samples_balanced` always fails, so
  /// `symmetry_score` and `knee_angle_diff` come back null. 0.3 is the
  /// MediaPipe-recommended floor for occlusion-tolerant tracking — noisier
  /// per-frame angles, but avgFullCycle averages it out.
  static const double minLandmarkVis = 0.3;
}

/// Gait phase boundaries as `(lo%, hi%, label)` from heel strike.
const List<(int, int, String)> gaitPhases = [
  (0, 10, 'loading_response'),
  (10, 30, 'mid_stance'),
  (30, 50, 'terminal_stance'),
  (50, 60, 'pre_swing'),
  (60, 73, 'initial_swing'),
  (73, 87, 'mid_swing'),
  (87, 100, 'terminal_swing'),
];

/// Ordered list of phase names — handy for iteration without destructuring.
const List<String> gaitPhaseNames = [
  'loading_response',
  'mid_stance',
  'terminal_stance',
  'pre_swing',
  'initial_swing',
  'mid_swing',
  'terminal_swing',
];

String phaseForPct(double pct) {
  for (final (lo, hi, name) in gaitPhases) {
    if (pct >= lo && pct < hi) return name;
  }
  return 'terminal_swing';
}
