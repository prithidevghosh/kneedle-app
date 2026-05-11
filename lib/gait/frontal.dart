import 'dart:math' as math;

import 'constants.dart';
import 'geometry.dart';
import 'heel_strike.dart';
import 'landmark.dart';

class FrontalResult {
  FrontalResult({
    required this.rightVvt,
    required this.leftVvt,
    required this.rightStaticAlignment,
    required this.leftStaticAlignment,
    required this.pelvicObliquityDeg,
    required this.trendelenburgFlag,
    required this.trunkLateralLeanDeg,
    required this.trunkLeanDirection,
    required this.stepWidthProxy,
    required this.fppaRight,
    required this.fppaLeft,
    required this.hsRightFrontal,
    required this.hsLeftFrontal,
    required this.phaseRightFrontal,
  });

  final double rightVvt;
  final double leftVvt;
  final double rightStaticAlignment;
  final double leftStaticAlignment;
  final double pelvicObliquityDeg;
  final bool trendelenburgFlag;
  final double trunkLateralLeanDeg;
  final String trunkLeanDirection;
  final double stepWidthProxy;
  final double fppaRight;
  final double fppaLeft;
  final List<int> hsRightFrontal;
  final List<int> hsLeftFrontal;
  final Map<int, String> phaseRightFrontal;

  static final FrontalResult empty = FrontalResult(
    rightVvt: 0,
    leftVvt: 0,
    rightStaticAlignment: 0,
    leftStaticAlignment: 0,
    pelvicObliquityDeg: 0,
    trendelenburgFlag: false,
    trunkLateralLeanDeg: 0,
    trunkLeanDirection: 'neutral',
    stepWidthProxy: 0,
    fppaRight: 0,
    fppaLeft: 0,
    hsRightFrontal: const [],
    hsLeftFrontal: const [],
    phaseRightFrontal: const {},
  );
}

/// Signed lateral deviation of knee from hip-ankle line, expressed as
/// percent of leg length (camera-distance invariant).
double computeVvt(Landmark hip, Landmark knee, Landmark ankle) {
  final hax = ankle.x - hip.x;
  final hay = ankle.y - hip.y;
  final hkx = knee.x - hip.x;
  final hky = knee.y - hip.y;
  final legLenSq = hax * hax + hay * hay;
  if (legLenSq < 1e-10) return 0;
  final legLen = math.sqrt(legLenSq);
  final t = (hkx * hax + hky * hay) / legLenSq;
  final projx = t * hax;
  final projy = t * hay;
  final devx = hkx - projx;
  final devy = hky - projy;
  final devMag = math.sqrt(devx * devx + devy * devy);
  // 2-D cross product → sign tells which side the knee deviates to.
  final cross = hax * hky - hay * hkx;
  final sign = cross == 0 ? 0.0 : (cross > 0 ? 1.0 : -1.0);
  return Round.r2(sign * devMag / legLen * 100);
}

/// Pelvic tilt in degrees (–90 .. +90). 0 = level.
double pelvicObliquity(Landmark leftHip, Landmark rightHip) {
  final dy = rightHip.y - leftHip.y;
  final dx = (rightHip.x - leftHip.x).abs() + 1e-8;
  return math.atan2(dy, dx) * 180.0 / math.pi;
}

FrontalResult extractFrontal(
  List<PoseFrame> frames, {
  required double effectiveFps,
}) {
  ({List<double> ys, List<double> vis}) ankleSeries(int lmIdx) {
    final ys = <double>[];
    final vis = <double>[];
    for (final f in frames) {
      final lm = f.landmarks;
      if (lm != null &&
          f.confidence >= GaitConst.minFrameConfidence &&
          lm[lmIdx].visibility > GaitConst.minLandmarkVis) {
        ys.add(lm[lmIdx].y);
        vis.add(lm[lmIdx].visibility);
      } else {
        ys.add(0);
        vis.add(0);
      }
    }
    return (ys: ys, vis: vis);
  }

  final right = ankleSeries(Lm.rightAnkle);
  final left = ankleSeries(Lm.leftAnkle);
  final hsRightF =
      detectHeelStrikes(right.ys, right.vis, sampleFps: effectiveFps);
  final hsLeftF = detectHeelStrikes(left.ys, left.vis, sampleFps: effectiveFps);
  final phaseRf = labelPhases(frames.length, hsRightF);
  final phaseLf = labelPhases(frames.length, hsLeftF);

  final vvtR = <double>[];
  final vvtL = <double>[];
  final staticAlignR = <double>[];
  final staticAlignL = <double>[];
  final fppaR = <double>[];
  final fppaL = <double>[];
  final pelvicRMs = <double>[];
  final pelvicLMs = <double>[];
  final trunkLat = <double>[];
  final trunkDirs = <String>[];
  final stepWidths = <double>[];

  for (final hsIdx in [...hsRightF, ...hsLeftF]) {
    if (hsIdx < frames.length) {
      final lm = frames[hsIdx].landmarks;
      if (lm != null) {
        stepWidths.add((lm[Lm.rightAnkle].x - lm[Lm.leftAnkle].x).abs());
      }
    }
  }

  for (var si = 0; si < frames.length; si++) {
    final f = frames[si];
    final lm = f.landmarks;
    if (lm == null || f.confidence < GaitConst.minFrameConfidence) continue;

    final hipLineWidth = (lm[Lm.rightHip].x - lm[Lm.leftHip].x).abs();
    final frontalAligned = hipLineWidth >= 0.08;

    final rOk = lm[Lm.rightHip].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.rightKnee].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.rightAnkle].visibility > GaitConst.minLandmarkVis;
    final lOk = lm[Lm.leftHip].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.leftKnee].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.leftAnkle].visibility > GaitConst.minLandmarkVis;

    if (frontalAligned && rOk) {
      final rDev = computeVvt(lm[Lm.rightHip], lm[Lm.rightKnee], lm[Lm.rightAnkle]);
      staticAlignR.add(rDev.abs());
      if (phaseRf[si] == 'loading_response') {
        vvtR.add(rDev);
        fppaR.add(calculateAngle(
          lm[Lm.rightHip],
          lm[Lm.rightKnee],
          lm[Lm.rightAnkle],
        ));
      }
    }
    if (frontalAligned && lOk) {
      final lDev = computeVvt(lm[Lm.leftHip], lm[Lm.leftKnee], lm[Lm.leftAnkle]);
      staticAlignL.add(lDev.abs());
      if (phaseLf[si] == 'loading_response') {
        vvtL.add(lDev);
        fppaL.add(calculateAngle(
          lm[Lm.leftHip],
          lm[Lm.leftKnee],
          lm[Lm.leftAnkle],
        ));
      }
    }

    if (frontalAligned && phaseRf[si] == 'mid_stance') {
      if (lm[Lm.leftHip].visibility > GaitConst.minLandmarkVis &&
          lm[Lm.rightHip].visibility > GaitConst.minLandmarkVis) {
        pelvicRMs.add(pelvicObliquity(lm[Lm.leftHip], lm[Lm.rightHip]));
      }
    }
    if (frontalAligned && phaseLf[si] == 'mid_stance') {
      if (lm[Lm.leftHip].visibility > GaitConst.minLandmarkVis &&
          lm[Lm.rightHip].visibility > GaitConst.minLandmarkVis) {
        pelvicLMs.add(pelvicObliquity(lm[Lm.leftHip], lm[Lm.rightHip]));
      }
    }

    if (frontalAligned &&
        (phaseRf[si] == 'mid_stance' || phaseLf[si] == 'mid_stance')) {
      final shX = (lm[Lm.leftShoulder].x + lm[Lm.rightShoulder].x) / 2;
      final hpX = (lm[Lm.leftHip].x + lm[Lm.rightHip].x) / 2;
      final shY = (lm[Lm.leftShoulder].y + lm[Lm.rightShoulder].y) / 2;
      final hpY = (lm[Lm.leftHip].y + lm[Lm.rightHip].y) / 2;
      final dx = shX - hpX;
      final dy = (shY - hpY).abs() + 1e-8;
      trunkLat.add((math.atan(dx / dy) * 180.0 / math.pi).abs());
      trunkDirs.add(dx > 0.01 ? 'right' : (dx < -0.01 ? 'left' : 'neutral'));
    }
  }

  double pelvicObliq;
  final allObliq = [...pelvicRMs, ...pelvicLMs];
  if (allObliq.isNotEmpty) {
    pelvicObliq = Round.r1(percentile([for (final a in allObliq) a.abs()], 75));
  } else {
    pelvicObliq = 0;
  }
  final trendelenburg = pelvicObliq > 10.0;

  final trunkLean = trunkLat.isNotEmpty ? Round.r1(mean(trunkLat)) : 0.0;
  String trunkDir = 'neutral';
  if (trunkDirs.isNotEmpty) {
    final counts = <String, int>{};
    for (final d in trunkDirs) {
      counts[d] = (counts[d] ?? 0) + 1;
    }
    var bestK = trunkDirs.first;
    var bestV = -1;
    counts.forEach((k, v) {
      if (v > bestV) {
        bestK = k;
        bestV = v;
      }
    });
    trunkDir = bestK;
  }

  double fppaDev(List<double> v) =>
      v.isEmpty ? 0.0 : Round.r1((180.0 - mean(v)).abs());

  return FrontalResult(
    rightVvt: vvtR.isEmpty ? 0 : Round.r2(mean(vvtR)),
    leftVvt: vvtL.isEmpty ? 0 : Round.r2(mean(vvtL)),
    rightStaticAlignment:
        staticAlignR.isEmpty ? 0 : Round.r2(median(staticAlignR)),
    leftStaticAlignment:
        staticAlignL.isEmpty ? 0 : Round.r2(median(staticAlignL)),
    pelvicObliquityDeg: pelvicObliq,
    trendelenburgFlag: trendelenburg,
    trunkLateralLeanDeg: trunkLean,
    trunkLeanDirection: trunkDir,
    stepWidthProxy: stepWidths.isEmpty ? 0 : Round.r3(mean(stepWidths)),
    fppaRight: fppaDev(fppaR),
    fppaLeft: fppaDev(fppaL),
    hsRightFrontal: hsRightF,
    hsLeftFrontal: hsLeftF,
    phaseRightFrontal: phaseRf,
  );
}
