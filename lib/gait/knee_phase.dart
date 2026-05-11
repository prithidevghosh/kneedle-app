/// Per-side knee phase angle aggregates. Mirrors `KneePhaseAngles` in
/// gait_analyzer.py.
///
/// All values stored as clinical FLEXION (0° = full extension, larger value
/// = more bend), so KL thresholds and "extension lag" semantics match standard
/// biomechanics references.
class KneePhaseAngles {
  const KneePhaseAngles({
    this.loadingResponsePeak,
    this.midStanceAngle,
    this.peakSwingFlexion,
    this.romDelta,
    this.extensionLag,
    this.avgFullCycle = 0.0,
  });

  final double? loadingResponsePeak;
  final double? midStanceAngle;
  final double? peakSwingFlexion;
  final double? romDelta;
  final double? extensionLag;
  final double avgFullCycle;

  static const KneePhaseAngles empty = KneePhaseAngles();
}
