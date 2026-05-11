import 'package:flutter_test/flutter_test.dart';
import 'package:kneedle/gait/kl_score.dart';
import 'package:kneedle/gait/knee_phase.dart';

GaitParams _healthy() => GaitParams(
      kneeRight: const KneePhaseAngles(
        loadingResponsePeak: 18,
        midStanceAngle: 8,
        peakSwingFlexion: 60,
        romDelta: 52,
        extensionLag: 2,
        avgFullCycle: 30,
      ),
      kneeLeft: const KneePhaseAngles(
        loadingResponsePeak: 17,
        midStanceAngle: 8,
        peakSwingFlexion: 60,
        romDelta: 52,
        extensionLag: 2,
        avgFullCycle: 30,
      ),
      cadence: 110,
      doubleSupportRatio: 22,
      strideTimeAsymmetry: 2,
      heelStrikeEventsRight: 8,
      heelStrikeEventsLeft: 8,
      hipExtensionTerminalStance: 12,
      ankleDorsiflexion: 10,
    );

void main() {
  test('healthy walker scores kl_0', () {
    final r = computeKlProxy(_healthy());
    expect(r.grade, 'kl_0');
    expect(r.flags, isEmpty);
  });

  test('severe static deformity pushes to kl_3+', () {
    final p = GaitParams(
      kneeRight: _healthy().kneeRight,
      kneeLeft: _healthy().kneeLeft,
      rightStaticAlignmentDeviation: 12, // > 10 → +10
      cadence: 110,
      doubleSupportRatio: 22,
      heelStrikeEventsRight: 8,
      heelStrikeEventsLeft: 8,
    );
    final r = computeKlProxy(p);
    expect(r.flags, contains('severe_static_varus_valgus_deformity'));
    expect(['kl_3', 'kl_4'], contains(r.grade));
  });

  test('bilateral pattern detector', () {
    final base = _healthy();
    final p = GaitParams(
      kneeRight: const KneePhaseAngles(
        loadingResponsePeak: 8,
        peakSwingFlexion: 30,
        midStanceAngle: 6,
        romDelta: 24,
        extensionLag: 4,
        avgFullCycle: 18,
      ),
      kneeLeft: const KneePhaseAngles(
        loadingResponsePeak: 9,
        peakSwingFlexion: 32,
        midStanceAngle: 6,
        romDelta: 26,
        extensionLag: 4,
        avgFullCycle: 18,
      ),
      cadence: base.cadence,
    );
    expect(checkBilateral(p), isTrue);
  });
}
