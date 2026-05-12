import '../gait/pipeline.dart';

/// Classify gait severity from MediaPipe metrics.
///
/// Direct port of `assess_severity` in `kneedle-backend/gemma_client.py`.
/// KL-proxy grade (set by the dual-video pipeline) takes precedence; legacy
/// heuristics act as fallback for backward compatibility.
String assessSeverity(GaitMetrics m) {
  // KL-proxy grade from dual-video pipeline takes precedence.
  const klMap = {
    'kl_0': 'normal',
    'kl_1': 'mild',
    'kl_2': 'moderate',
    'kl_3': 'severe',
    'kl_4': 'severe',
  };
  final byKl = klMap[m.klProxyGrade];
  if (byKl != null) return byKl;

  final sym = m.symmetryScore;
  final lean = m.trunkLeanAngle ?? 0;
  final diff = m.kneeAngleDiff ?? 0;
  final cad = m.cadence;

  if ((sym != null && sym < 65) ||
      lean > 8 ||
      diff > 15 ||
      (cad != null && cad < 70)) {
    return 'severe';
  }
  if ((sym != null && sym < 80) || lean > 4 || diff > 8) {
    return 'moderate';
  }
  return 'mild';
}

/// Gatekeeper: returns `null` when the metrics carry enough signal for the
/// LLM to produce a meaningful, safe analysis. Otherwise returns a short,
/// patient-facing reason explaining what to fix on the next recording.
///
/// Without this check we'd ship payloads like the production log where
/// `symmetry_score`, `knee_angle_diff`, and both toe-out angles all came back
/// as `not detected` — Gemma would then hallucinate over null fields and we'd
/// burn ~6 minutes of on-device decode for advice the patient can't trust.
String? validateMetricsForAnalysis(GaitMetrics m) {
  if (m.kneeAngleLeft == null && m.kneeAngleRight == null) {
    return 'No knee angles were detected. Make sure your full body is in '
        'frame from head to feet during both recordings.';
  }
  if (m.kneeAngleLeft == null || m.kneeAngleRight == null) {
    return 'Only one knee was detected. Stand so both legs stay in frame '
        'for the whole 8-second recording, then try again.';
  }
  if (m.symmetryScore == null) {
    return 'Could not compute gait symmetry — the frontal and side views '
        'did not line up. Re-record with both legs in frame and steady '
        'walking pace.';
  }
  if (m.framesAnalysed < 8) {
    return 'Too few usable frames were captured (${m.framesAnalysed}). '
        'Try again with better lighting and the full body visible.';
  }
  return null;
}

/// Map raw symmetry score (0–100) to a patient-facing band.
/// Returns "unknown" when score is missing — happens when the sagittal
/// pipeline detected per-side sample imbalance and suppressed the score.
String computeSymmetryBand(double? score) {
  if (score == null) return 'unknown';
  if (score >= 80) return 'good';
  if (score >= 65) return 'fair';
  return 'poor';
}

/// Determine which joint to highlight based on the primary gait finding.
String getActiveJoint(GaitMetrics m) {
  final sym = m.symmetryScore;
  if (sym != null && sym < 70) {
    final r = m.kneeAngleRight;
    final l = m.kneeAngleLeft;
    if (r != null && l != null) {
      return r < l ? 'right_knee' : 'left_knee';
    }
    return 'right_knee';
  }
  final lean = m.trunkLeanAngle ?? 0;
  if (lean > 6) return 'hips';
  final toR = m.toeOutAngleRight;
  if (toR != null && toR.abs() < 5) return 'ankles';
  return 'right_knee';
}
