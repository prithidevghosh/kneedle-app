import 'geometry.dart';
import 'landmark.dart';

class TemporalParams {
  const TemporalParams({
    required this.cadence,
    required this.strideTimeAsymmetry,
    required this.doubleSupportRatio,
    required this.gaitCyclesDetected,
    required this.heelStrikeEventsRight,
    required this.heelStrikeEventsLeft,
  });

  final double cadence;
  final double strideTimeAsymmetry;
  final double doubleSupportRatio;
  final int gaitCyclesDetected;
  final int heelStrikeEventsRight;
  final int heelStrikeEventsLeft;
}

/// Computes cadence, stride asymmetry, double-support ratio.
///
/// Uses sagittal as primary; falls back to frontal heel-strikes when the
/// sagittal view yields fewer than 3 strikes total.
TemporalParams extractTemporal({
  required List<PoseFrame> sagittalFrames,
  required List<PoseFrame> frontalFrames,
  required List<int> sagHsRight,
  required List<int> sagHsLeft,
  required List<int> froHsRight,
  required List<int> froHsLeft,
}) {
  var framesP = sagittalFrames;
  var hsR = sagHsRight;
  var hsL = sagHsLeft;

  if (hsR.length + hsL.length < 3) {
    framesP = frontalFrames;
    hsR = froHsRight;
    hsL = froHsLeft;
  }

  List<double> times(List<int> hs) => [
        for (final i in hs)
          if (i < framesP.length) framesP[i].timeSec,
      ];

  final rTimes = times(hsR);
  final lTimes = times(hsL);

  final strideR = <double>[
    for (var i = 0; i < rTimes.length - 1; i++) rTimes[i + 1] - rTimes[i],
  ];
  final strideL = <double>[
    for (var i = 0; i < lTimes.length - 1; i++) lTimes[i + 1] - lTimes[i],
  ];

  var cadence = 0.0;
  final allStrikes = [...rTimes, ...lTimes]..sort();
  if (allStrikes.length >= 2) {
    final dur = allStrikes.last - allStrikes.first;
    if (dur > 0) {
      cadence = Round.r1((allStrikes.length - 1) / dur * 60);
    }
  }

  var strideAsym = 0.0;
  if (strideR.isNotEmpty && strideL.isNotEmpty) {
    final mr = mean(strideR);
    final ml = mean(strideL);
    final meanAll = (mr + ml) / 2;
    if (meanAll > 0) {
      strideAsym = Round.r1((mr - ml).abs() / meanAll * 100);
    }
  }

  var doubleSupport = 20.0;
  if (strideR.isNotEmpty &&
      strideL.isNotEmpty &&
      rTimes.isNotEmpty &&
      lTimes.isNotEmpty) {
    final rStanceN = (rTimes.length - 1) < strideR.length
        ? (rTimes.length - 1)
        : strideR.length;
    final lStanceN = (lTimes.length - 1) < strideL.length
        ? (lTimes.length - 1)
        : strideL.length;
    final rStance = <(double, double)>[
      for (var i = 0; i < rStanceN; i++) (rTimes[i], rTimes[i] + 0.6 * strideR[i]),
    ];
    final lStance = <(double, double)>[
      for (var i = 0; i < lStanceN; i++) (lTimes[i], lTimes[i] + 0.6 * strideL[i]),
    ];
    final overlaps = <double>[];
    for (final rs in rStance) {
      for (final ls in lStance) {
        final ovS = rs.$1 > ls.$1 ? rs.$1 : ls.$1;
        final ovE = rs.$2 < ls.$2 ? rs.$2 : ls.$2;
        if (ovE > ovS && (rs.$2 - rs.$1) > 0) {
          overlaps.add((ovE - ovS) / (rs.$2 - rs.$1) * 100);
        }
      }
    }
    if (overlaps.isNotEmpty) {
      doubleSupport = Round.r1(mean(overlaps));
    }
  }

  final gaitCycles =
      strideR.length > strideL.length ? strideR.length : strideL.length;

  return TemporalParams(
    cadence: cadence,
    strideTimeAsymmetry: strideAsym,
    doubleSupportRatio: doubleSupport,
    gaitCyclesDetected: gaitCycles,
    heelStrikeEventsRight: hsR.length,
    heelStrikeEventsLeft: hsL.length,
  );
}
