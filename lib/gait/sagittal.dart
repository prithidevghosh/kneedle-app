import 'dart:math' as math;

import 'constants.dart';
import 'geometry.dart';
import 'heel_strike.dart';
import 'knee_phase.dart';
import 'landmark.dart';

/// Result of the sagittal-view extraction. Field names mirror the dict keys
/// produced by `_extract_sagittal` in gait_analyzer.py.
class SagittalResult {
  SagittalResult({
    required this.kneeRight,
    required this.kneeLeft,
    required this.kneeRightN,
    required this.kneeLeftN,
    required this.hipExtensionTerminalStance,
    required this.ankleDorsiflexion,
    required this.trunkAnteriorLeanDeg,
    required this.hsRight,
    required this.hsLeft,
    required this.gaitSpeedProxy,
    required this.phaseRight,
  });

  final KneePhaseAngles kneeRight;
  final KneePhaseAngles kneeLeft;
  final int kneeRightN;
  final int kneeLeftN;
  final double? hipExtensionTerminalStance;
  final double? ankleDorsiflexion;
  final double trunkAnteriorLeanDeg;
  final List<int> hsRight;
  final List<int> hsLeft;
  final double gaitSpeedProxy;
  final Map<int, String> phaseRight;

  static final SagittalResult empty = SagittalResult(
    kneeRight: KneePhaseAngles.empty,
    kneeLeft: KneePhaseAngles.empty,
    kneeRightN: 0,
    kneeLeftN: 0,
    hipExtensionTerminalStance: null,
    ankleDorsiflexion: null,
    trunkAnteriorLeanDeg: 0,
    hsRight: const [],
    hsLeft: const [],
    gaitSpeedProxy: 0,
    phaseRight: const {},
  );
}

SagittalResult extractSagittal(
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
  final hsRight = detectHeelStrikes(right.ys, right.vis, sampleFps: effectiveFps);
  final hsLeft = detectHeelStrikes(left.ys, left.vis, sampleFps: effectiveFps);
  final phaseR = labelPhases(frames.length, hsRight);
  final phaseL = labelPhases(frames.length, hsLeft);

  final kneeByPhase = <String, Map<String, List<double>>>{
    'right': {for (final p in gaitPhaseNames) p: <double>[]},
    'left': {for (final p in gaitPhaseNames) p: <double>[]},
  };
  final kneeAll = <String, List<double>>{
    'right': <double>[],
    'left': <double>[],
  };

  final hipExt = <double>[];
  final ankleDors = <double>[];
  final trunkAnt = <double>[];
  final hipXSeries = <(double t, double hx, double had)>[];

  for (var si = 0; si < frames.length; si++) {
    final f = frames[si];
    final lm = f.landmarks;
    if (lm == null || f.confidence < GaitConst.minFrameConfidence) continue;

    final rVisible = lm[Lm.rightHip].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.rightKnee].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.rightAnkle].visibility > GaitConst.minLandmarkVis;
    final lVisible = lm[Lm.leftHip].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.leftKnee].visibility > GaitConst.minLandmarkVis &&
        lm[Lm.leftAnkle].visibility > GaitConst.minLandmarkVis;

    if (rVisible) {
      final rKnee = 180.0 -
          calculateAngle(lm[Lm.rightHip], lm[Lm.rightKnee], lm[Lm.rightAnkle]);
      kneeAll['right']!.add(rKnee);
      final ph = phaseR[si];
      if (ph != null) kneeByPhase['right']![ph]!.add(rKnee);
    }
    if (lVisible) {
      final lKnee = 180.0 -
          calculateAngle(lm[Lm.leftHip], lm[Lm.leftKnee], lm[Lm.leftAnkle]);
      kneeAll['left']!.add(lKnee);
      final ph = phaseL[si];
      if (ph != null) kneeByPhase['left']![ph]!.add(lKnee);
    }

    if (phaseR[si] == 'terminal_stance') {
      if (lm[Lm.rightHip].visibility > GaitConst.minLandmarkVis &&
          lm[Lm.rightKnee].visibility > GaitConst.minLandmarkVis) {
        final dx = lm[Lm.rightKnee].x - lm[Lm.rightHip].x;
        final dy = (lm[Lm.rightKnee].y - lm[Lm.rightHip].y).abs() + 1e-8;
        hipExt.add(math.atan2(dx.abs(), dy) * 180.0 / math.pi);
      }
    }

    if (phaseR[si] == 'mid_stance') {
      if (lm[Lm.rightKnee].visibility > GaitConst.minLandmarkVis &&
          lm[Lm.rightAnkle].visibility > GaitConst.minLandmarkVis &&
          lm[Lm.rightFootIndex].visibility > GaitConst.minLandmarkVis) {
        ankleDors.add(calculateAngle(
          lm[Lm.rightKnee],
          lm[Lm.rightAnkle],
          lm[Lm.rightFootIndex],
        ));
      }
    }

    final shX = (lm[Lm.leftShoulder].x + lm[Lm.rightShoulder].x) / 2;
    final hpX = (lm[Lm.leftHip].x + lm[Lm.rightHip].x) / 2;
    final shY = (lm[Lm.leftShoulder].y + lm[Lm.rightShoulder].y) / 2;
    final hpY = (lm[Lm.leftHip].y + lm[Lm.rightHip].y) / 2;
    trunkAnt.add(
      (math.atan((shX - hpX) / ((shY - hpY).abs() + 1e-8)) * 180.0 / math.pi)
          .abs(),
    );

    final hipX = (lm[Lm.leftHip].x + lm[Lm.rightHip].x) / 2;
    final ankleYMid = (lm[Lm.leftAnkle].y + lm[Lm.rightAnkle].y) / 2;
    final hipAnkleDist = (ankleYMid - hpY).abs() + 1e-6;
    hipXSeries.add((f.timeSec, hipX, hipAnkleDist));
  }

  KneePhaseAngles buildKpa(String side) {
    final kp = kneeByPhase[side]!;
    final lr = safeMean(kp['loading_response']!);
    final ms = safeMean(kp['mid_stance']!);
    final swingVals = [...kp['initial_swing']!, ...kp['mid_swing']!];
    double? sw;
    if (swingVals.isNotEmpty) {
      var m = swingVals.first;
      for (final v in swingVals) {
        if (v > m) m = v;
      }
      sw = Round.r1(m);
    }
    final allV = kneeAll[side]!;
    double? extLag;
    if (allV.isNotEmpty) {
      var m = allV.first;
      for (final v in allV) {
        if (v < m) m = v;
      }
      extLag = Round.r1(m);
    }
    final rd = (sw != null && ms != null) ? Round.r1(sw - ms) : null;
    final avg = allV.isNotEmpty ? Round.r1(mean(allV)) : 0.0;
    return KneePhaseAngles(
      loadingResponsePeak: lr,
      midStanceAngle: ms,
      peakSwingFlexion: sw,
      romDelta: rd,
      extensionLag: extLag,
      avgFullCycle: avg,
    );
  }

  var gaitSpeedProxy = 0.0;
  if (hipXSeries.length >= 2) {
    final first = hipXSeries.first;
    final last = hipXSeries.last;
    final dur = last.$1 - first.$1;
    final disp = (last.$2 - first.$2).abs();
    final meanBh =
        mean([for (final s in hipXSeries) s.$3]) + 1e-6;
    if (dur > 0) {
      gaitSpeedProxy = Round.r3(disp / dur / meanBh);
    }
  }

  return SagittalResult(
    kneeRight: buildKpa('right'),
    kneeLeft: buildKpa('left'),
    kneeRightN: kneeAll['right']!.length,
    kneeLeftN: kneeAll['left']!.length,
    hipExtensionTerminalStance: safeMean(hipExt),
    ankleDorsiflexion: safeMean(ankleDors),
    trunkAnteriorLeanDeg: trunkAnt.isNotEmpty ? Round.r1(mean(trunkAnt)) : 0.0,
    hsRight: hsRight,
    hsLeft: hsLeft,
    gaitSpeedProxy: gaitSpeedProxy,
    phaseRight: phaseR,
  );
}
