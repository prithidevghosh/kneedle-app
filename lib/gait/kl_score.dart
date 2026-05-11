import 'knee_phase.dart';

class GaitParams {
  GaitParams({
    required this.kneeRight,
    required this.kneeLeft,
    this.rightVarusValgusThrust = 0,
    this.leftVarusValgusThrust = 0,
    this.rightStaticAlignmentDeviation = 0,
    this.leftStaticAlignmentDeviation = 0,
    this.pelvicObliquityDeg = 0,
    this.trendelenburgFlag = false,
    this.trunkLateralLeanDeg = 0,
    this.trunkLeanDirection = 'neutral',
    this.stepWidthProxy = 0,
    this.fppaRight = 0,
    this.fppaLeft = 0,
    this.hipExtensionTerminalStance,
    this.ankleDorsiflexion,
    this.trunkAnteriorLeanDeg = 0,
    this.cadence = 0,
    this.strideTimeAsymmetry = 0,
    this.doubleSupportRatio = 20,
    this.gaitSpeedProxy = 0,
    this.symmetryScore = 0,
    this.frontalConfidence = 0,
    this.sagittalConfidence = 0,
    this.frontalFramesAnalyzed = 0,
    this.frontalFramesSkipped = 0,
    this.sagittalFramesAnalyzed = 0,
    this.sagittalFramesSkipped = 0,
    this.heelStrikeEventsRight = 0,
    this.heelStrikeEventsLeft = 0,
    this.gaitCyclesDetected = 0,
    this.fallbackMode = false,
  });

  final KneePhaseAngles kneeRight;
  final KneePhaseAngles kneeLeft;
  final double rightVarusValgusThrust;
  final double leftVarusValgusThrust;
  final double rightStaticAlignmentDeviation;
  final double leftStaticAlignmentDeviation;
  final double pelvicObliquityDeg;
  final bool trendelenburgFlag;
  final double trunkLateralLeanDeg;
  final String trunkLeanDirection;
  final double stepWidthProxy;
  final double fppaRight;
  final double fppaLeft;
  final double? hipExtensionTerminalStance;
  final double? ankleDorsiflexion;
  final double trunkAnteriorLeanDeg;
  final double cadence;
  final double strideTimeAsymmetry;
  final double doubleSupportRatio;
  final double gaitSpeedProxy;
  final double symmetryScore;
  final double frontalConfidence;
  final double sagittalConfidence;
  final int frontalFramesAnalyzed;
  final int frontalFramesSkipped;
  final int sagittalFramesAnalyzed;
  final int sagittalFramesSkipped;
  final int heelStrikeEventsRight;
  final int heelStrikeEventsLeft;
  final int gaitCyclesDetected;
  final bool fallbackMode;
}

class KlResult {
  const KlResult(this.score, this.grade, this.flags);
  final double score;
  final String grade;
  final List<String> flags;
}

/// KL-proxy scoring — direct port of `_compute_kl_proxy` in gait_analyzer.py.
///
/// All threshold rationales are preserved in `gait_analyzer.py`; do not retune
/// without consulting that file's comments.
KlResult computeKlProxy(GaitParams p) {
  var score = 0.0;
  final flags = <String>[];

  for (final entry in <({String name, KneePhaseAngles knee})>[
    (name: 'right', knee: p.kneeRight),
    (name: 'left', knee: p.kneeLeft),
  ]) {
    final side = entry.name;
    final k = entry.knee;
    if (k.loadingResponsePeak != null) {
      if (k.loadingResponsePeak! < 5) {
        score += 2;
        flags.add('${side}_loading_response_absent');
      } else if (k.loadingResponsePeak! < 10) {
        score += 1;
        flags.add('${side}_loading_response_reduced');
      }
    }
    if (k.peakSwingFlexion != null) {
      if (k.peakSwingFlexion! < 18) {
        score += 2;
        flags.add('${side}_swing_flexion_severe');
      } else if (k.peakSwingFlexion! < 28) {
        score += 1;
        flags.add('${side}_swing_flexion_reduced');
      }
    }
    if (k.extensionLag != null && k.extensionLag! > 10) {
      score += 1;
      flags.add('${side}_flexion_contracture');
    }
  }

  if (p.rightVarusValgusThrust.abs() > 8 ||
      p.leftVarusValgusThrust.abs() > 8) {
    score += 2;
    flags.add('significant_varus_valgus_thrust');
  } else if (p.rightVarusValgusThrust.abs() > 5 ||
      p.leftVarusValgusThrust.abs() > 5) {
    score += 1;
    flags.add('mild_varus_valgus_thrust');
  }

  final maxStatic = p.rightStaticAlignmentDeviation >
          p.leftStaticAlignmentDeviation
      ? p.rightStaticAlignmentDeviation
      : p.leftStaticAlignmentDeviation;
  if (maxStatic > 10) {
    score += 10;
    flags.add('severe_static_varus_valgus_deformity');
  } else if (maxStatic > 6) {
    score += 6;
    flags.add('moderate_static_varus_valgus_deformity');
  } else if (maxStatic > 4) {
    score += 4;
    flags.add('mild_static_varus_valgus_deformity');
  }

  if (p.trendelenburgFlag) {
    score += 1;
    flags.add('trendelenburg_positive');
  }
  if (p.trunkLateralLeanDeg > 8) {
    score += 1;
    flags.add('significant_trunk_lean');
  }
  if (p.fppaRight.abs() > 15 || p.fppaLeft.abs() > 15) {
    score += 1;
    flags.add('fppa_deviation');
  }

  final minStrikes =
      p.heelStrikeEventsRight < p.heelStrikeEventsLeft
          ? p.heelStrikeEventsRight
          : p.heelStrikeEventsLeft;
  final cadencePlausible = p.cadence >= 40 && p.cadence <= 180;
  final dsPlausible = p.doubleSupportRatio <= 50;

  if (minStrikes >= 3 && cadencePlausible && dsPlausible) {
    if (p.doubleSupportRatio > 35) {
      score += 2;
      flags.add('high_double_support');
    } else if (p.doubleSupportRatio > 28) {
      score += 1;
      flags.add('elevated_double_support');
    }
    if (p.strideTimeAsymmetry > 15) {
      score += 1;
      flags.add('high_stride_asymmetry');
    }
    if (p.cadence < 70) {
      score += 1;
      flags.add('low_cadence');
    }
  }

  if (p.hipExtensionTerminalStance != null &&
      p.hipExtensionTerminalStance! < 5) {
    score += 1;
    flags.add('reduced_hip_extension');
  }
  if (p.ankleDorsiflexion != null && p.ankleDorsiflexion! < 5) {
    score += 1;
    flags.add('reduced_ankle_dorsiflexion');
  }

  // Threshold ladder — ascending. First match wins.
  const ladder = <(double, String)>[
    (3, 'kl_0'),
    (5, 'kl_1'),
    (8, 'kl_2'),
    (11, 'kl_3'),
    (16, 'kl_4'),
  ];
  String grade = 'kl_4';
  for (final (threshold, label) in ladder) {
    if (score <= threshold) {
      grade = label;
      break;
    }
  }
  return KlResult(score, grade, flags);
}

bool checkBilateral(GaitParams p) {
  final r = p.kneeRight;
  final l = p.kneeLeft;
  final bothLr = r.loadingResponsePeak != null &&
      l.loadingResponsePeak != null &&
      r.loadingResponsePeak! < 12 &&
      l.loadingResponsePeak! < 12;
  final bothSw = r.peakSwingFlexion != null &&
      l.peakSwingFlexion != null &&
      r.peakSwingFlexion! < 50 &&
      l.peakSwingFlexion! < 50;
  final bothStatic = p.rightStaticAlignmentDeviation > 4 &&
      p.leftStaticAlignmentDeviation > 4;
  return (bothLr && bothSw) || bothStatic;
}

const Map<String, String> klToSeverity = {
  'kl_0': 'normal',
  'kl_1': 'mild',
  'kl_2': 'moderate',
  'kl_3': 'severe',
  'kl_4': 'severe',
};
