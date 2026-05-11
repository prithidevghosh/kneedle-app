import 'constants.dart';
import 'frontal.dart';
import 'geometry.dart';
import 'kl_score.dart';
import 'knee_phase.dart';
import 'landmark.dart';
import 'sagittal.dart';
import 'temporal.dart';

/// Final patient-facing metrics. Field names mirror `GaitMetrics` in
/// `kneedle-backend/models.py`.
class GaitMetrics {
  GaitMetrics({
    this.kneeAngleRight,
    this.kneeAngleLeft,
    this.kneeAngleDiff,
    this.symmetryScore,
    this.trunkLeanAngle,
    this.trunkLeanDirection,
    this.toeOutAngleRight,
    this.toeOutAngleLeft,
    this.cadence,
    this.framesAnalysed = 0,
    this.confidence = 0,
    this.frontalFramesAnalyzed = 0,
    this.frontalFramesSkipped = 0,
    this.sagittalFramesAnalyzed = 0,
    this.sagittalFramesSkipped = 0,
    this.heelStrikeEventsRight = 0,
    this.heelStrikeEventsLeft = 0,
    this.gaitCyclesDetected = 0,
    this.klProxyScore = 0,
    this.klProxyGrade = 'kl_0',
    this.clinicalFlags = const <String>[],
    this.bilateralPatternDetected = false,
    this.rightLoadingResponsePeak,
    this.leftLoadingResponsePeak,
    this.rightMidStanceAngle,
    this.leftMidStanceAngle,
    this.rightPeakSwingFlexion,
    this.leftPeakSwingFlexion,
    this.rightRomDelta,
    this.leftRomDelta,
    this.rightExtensionLag,
    this.leftExtensionLag,
    this.hipExtensionTerminalStance,
    this.ankleDorsiflexion,
    this.trunkAnteriorLeanDeg = 0,
    this.rightVarusValgusThrust = 0,
    this.leftVarusValgusThrust = 0,
    this.rightStaticAlignmentDeviation = 0,
    this.leftStaticAlignmentDeviation = 0,
    this.pelvicObliquityDeg = 0,
    this.trendelenburgFlag = false,
    this.stepWidthProxy = 0,
    this.fppaRight = 0,
    this.fppaLeft = 0,
    this.strideTimeAsymmetry = 0,
    this.doubleSupportRatio = 20,
    this.gaitSpeedProxy = 0,
    this.fallbackMode = false,
    this.severity = 'normal',
  });

  final double? kneeAngleRight;
  final double? kneeAngleLeft;
  final double? kneeAngleDiff;
  final double? symmetryScore;
  final double? trunkLeanAngle;
  final String? trunkLeanDirection;
  final double? toeOutAngleRight;
  final double? toeOutAngleLeft;
  final double? cadence;
  final int framesAnalysed;
  final double confidence;
  final int frontalFramesAnalyzed;
  final int frontalFramesSkipped;
  final int sagittalFramesAnalyzed;
  final int sagittalFramesSkipped;
  final int heelStrikeEventsRight;
  final int heelStrikeEventsLeft;
  final int gaitCyclesDetected;
  final double klProxyScore;
  final String klProxyGrade;
  final List<String> clinicalFlags;
  final bool bilateralPatternDetected;
  final double? rightLoadingResponsePeak;
  final double? leftLoadingResponsePeak;
  final double? rightMidStanceAngle;
  final double? leftMidStanceAngle;
  final double? rightPeakSwingFlexion;
  final double? leftPeakSwingFlexion;
  final double? rightRomDelta;
  final double? leftRomDelta;
  final double? rightExtensionLag;
  final double? leftExtensionLag;
  final double? hipExtensionTerminalStance;
  final double? ankleDorsiflexion;
  final double trunkAnteriorLeanDeg;
  final double rightVarusValgusThrust;
  final double leftVarusValgusThrust;
  final double rightStaticAlignmentDeviation;
  final double leftStaticAlignmentDeviation;
  final double pelvicObliquityDeg;
  final bool trendelenburgFlag;
  final double stepWidthProxy;
  final double fppaRight;
  final double fppaLeft;
  final double strideTimeAsymmetry;
  final double doubleSupportRatio;
  final double gaitSpeedProxy;
  final bool fallbackMode;
  final String severity;

  Map<String, Object?> toJson() => {
        'knee_angle_right': kneeAngleRight,
        'knee_angle_left': kneeAngleLeft,
        'knee_angle_diff': kneeAngleDiff,
        'symmetry_score': symmetryScore,
        'trunk_lean_angle': trunkLeanAngle,
        'trunk_lean_direction': trunkLeanDirection,
        'cadence': cadence,
        'frames_analysed': framesAnalysed,
        'confidence': confidence,
        'kl_proxy_score': klProxyScore,
        'kl_proxy_grade': klProxyGrade,
        'clinical_flags': clinicalFlags,
        'bilateral_pattern_detected': bilateralPatternDetected,
        'right_loading_response_peak': rightLoadingResponsePeak,
        'left_loading_response_peak': leftLoadingResponsePeak,
        'right_peak_swing_flexion': rightPeakSwingFlexion,
        'left_peak_swing_flexion': leftPeakSwingFlexion,
        'right_static_alignment_deviation': rightStaticAlignmentDeviation,
        'left_static_alignment_deviation': leftStaticAlignmentDeviation,
        'pelvic_obliquity_deg': pelvicObliquityDeg,
        'trendelenburg_flag': trendelenburgFlag,
        'cadence_steps_min': cadence,
        'double_support_ratio': doubleSupportRatio,
        'gait_speed_proxy': gaitSpeedProxy,
        'severity': severity,
        'fallback_mode': fallbackMode,
      };
}

/// Per-view sample bundle handed in to `analyseGaitDual`. The pose backend
/// (camera frames + `flutter_pose_detection`, or imported video) is responsible
/// for assembling this — the gait library has no Flutter or platform deps.
class PoseSample {
  PoseSample({
    required this.frames,
    required this.fps,
    required this.effectiveFps,
    required this.framesAnalyzed,
    required this.framesSkipped,
    required this.confidence,
  });

  final List<PoseFrame> frames;
  final double fps;
  final double effectiveFps;
  final int framesAnalyzed;
  final int framesSkipped;
  final double confidence;

  static PoseSample fromFrames(List<PoseFrame> frames, double fps) {
    final sampleInterval =
        (fps / GaitConst.targetSampleFps).round().clamp(1, 1 << 30);
    final effectiveFps = fps / sampleInterval;
    var analysed = 0;
    final confs = <double>[];
    for (final f in frames) {
      if (f.landmarks != null) confs.add(f.confidence);
      if (f.landmarks != null && f.confidence >= GaitConst.minFrameConfidence) {
        analysed++;
      }
    }
    final meanConf = confs.isEmpty ? 0.0 : Round.r3(mean(confs));
    return PoseSample(
      frames: frames,
      fps: fps,
      effectiveFps: effectiveFps,
      framesAnalyzed: analysed,
      framesSkipped: frames.length - analysed,
      confidence: meanConf,
    );
  }
}

/// Full dual-view biomechanical pipeline. Returns the patient-facing metrics
/// plus a small `extra` map mirroring the Python implementation's contract.
({GaitMetrics metrics, Map<String, Object?> extra}) analyseGaitDual({
  required PoseSample frontal,
  required PoseSample sagittal,
}) {
  SagittalResult sagRes = SagittalResult.empty;
  FrontalResult froRes = FrontalResult.empty;
  var fallbackMode = false;

  try {
    sagRes = extractSagittal(sagittal.frames, effectiveFps: sagittal.effectiveFps);
  } catch (_) {
    fallbackMode = true;
  }
  try {
    froRes = extractFrontal(frontal.frames, effectiveFps: frontal.effectiveFps);
  } catch (_) {
    fallbackMode = true;
  }

  final temporal = extractTemporal(
    sagittalFrames: sagittal.frames,
    frontalFrames: frontal.frames,
    sagHsRight: sagRes.hsRight,
    sagHsLeft: sagRes.hsLeft,
    froHsRight: froRes.hsRightFrontal,
    froHsLeft: froRes.hsLeftFrontal,
  );

  final kneeR = sagRes.kneeRight;
  final kneeL = sagRes.kneeLeft;

  final rAvg = kneeR.avgFullCycle;
  final lAvg = kneeL.avgFullCycle;
  final rN = sagRes.kneeRightN;
  final lN = sagRes.kneeLeftN;
  final maxN = (rN > lN ? rN : lN).clamp(1, 1 << 30);
  final minN = rN < lN ? rN : lN;
  final samplesBalanced = rN >= 10 && lN >= 10 && (minN / maxN) >= 0.4;

  double? symmetry;
  if (rAvg != 0 && lAvg != 0 && samplesBalanced) {
    symmetry = Round.r1(
      (100.0 - (rAvg - lAvg).abs() * 2.5).clamp(0.0, 100.0),
    );
  }

  final params = GaitParams(
    kneeRight: kneeR,
    kneeLeft: kneeL,
    rightVarusValgusThrust: froRes.rightVvt,
    leftVarusValgusThrust: froRes.leftVvt,
    rightStaticAlignmentDeviation: froRes.rightStaticAlignment,
    leftStaticAlignmentDeviation: froRes.leftStaticAlignment,
    pelvicObliquityDeg: froRes.pelvicObliquityDeg,
    trendelenburgFlag: froRes.trendelenburgFlag,
    trunkLateralLeanDeg: froRes.trunkLateralLeanDeg,
    trunkLeanDirection: froRes.trunkLeanDirection,
    stepWidthProxy: froRes.stepWidthProxy,
    fppaRight: froRes.fppaRight,
    fppaLeft: froRes.fppaLeft,
    hipExtensionTerminalStance: sagRes.hipExtensionTerminalStance,
    ankleDorsiflexion: sagRes.ankleDorsiflexion,
    trunkAnteriorLeanDeg: sagRes.trunkAnteriorLeanDeg,
    cadence: temporal.cadence,
    strideTimeAsymmetry: temporal.strideTimeAsymmetry,
    doubleSupportRatio: temporal.doubleSupportRatio,
    gaitSpeedProxy: sagRes.gaitSpeedProxy,
    symmetryScore: symmetry ?? 0,
    frontalConfidence: frontal.confidence,
    sagittalConfidence: sagittal.confidence,
    frontalFramesAnalyzed: frontal.framesAnalyzed,
    frontalFramesSkipped: frontal.framesSkipped,
    sagittalFramesAnalyzed: sagittal.framesAnalyzed,
    sagittalFramesSkipped: sagittal.framesSkipped,
    heelStrikeEventsRight: temporal.heelStrikeEventsRight,
    heelStrikeEventsLeft: temporal.heelStrikeEventsLeft,
    gaitCyclesDetected: temporal.gaitCyclesDetected,
    fallbackMode: fallbackMode,
  );

  final kl = computeKlProxy(params);
  final flags = List<String>.from(kl.flags);
  final bilateral = checkBilateral(params);
  if (bilateral) flags.add('bilateral_oa_pattern');

  var severity = klToSeverity[kl.grade] ?? 'normal';
  if (bilateral && (severity == 'normal' || severity == 'mild')) {
    severity = 'moderate';
  }

  final hasBoth = sagittal.framesAnalyzed > 0 && frontal.framesAnalyzed > 0;
  final overallConf = hasBoth
      ? Round.r3(
          frontal.confidence < sagittal.confidence
              ? frontal.confidence
              : sagittal.confidence,
        )
      : (frontal.confidence > sagittal.confidence
          ? frontal.confidence
          : sagittal.confidence);

  final metrics = GaitMetrics(
    kneeAngleRight: rAvg == 0 ? null : rAvg,
    kneeAngleLeft: lAvg == 0 ? null : lAvg,
    kneeAngleDiff: (rAvg != 0 && lAvg != 0 && samplesBalanced)
        ? Round.r1((rAvg - lAvg).abs())
        : null,
    symmetryScore: symmetry,
    trunkLeanAngle: froRes.trunkLateralLeanDeg,
    trunkLeanDirection: froRes.trunkLeanDirection,
    cadence: params.cadence,
    framesAnalysed: frontal.framesAnalyzed + sagittal.framesAnalyzed,
    confidence: overallConf,
    frontalFramesAnalyzed: frontal.framesAnalyzed,
    frontalFramesSkipped: frontal.framesSkipped,
    sagittalFramesAnalyzed: sagittal.framesAnalyzed,
    sagittalFramesSkipped: sagittal.framesSkipped,
    heelStrikeEventsRight: temporal.heelStrikeEventsRight,
    heelStrikeEventsLeft: temporal.heelStrikeEventsLeft,
    gaitCyclesDetected: temporal.gaitCyclesDetected,
    klProxyScore: kl.score,
    klProxyGrade: kl.grade,
    clinicalFlags: flags,
    bilateralPatternDetected: bilateral,
    rightLoadingResponsePeak: kneeR.loadingResponsePeak,
    leftLoadingResponsePeak: kneeL.loadingResponsePeak,
    rightMidStanceAngle: kneeR.midStanceAngle,
    leftMidStanceAngle: kneeL.midStanceAngle,
    rightPeakSwingFlexion: kneeR.peakSwingFlexion,
    leftPeakSwingFlexion: kneeL.peakSwingFlexion,
    rightRomDelta: kneeR.romDelta,
    leftRomDelta: kneeL.romDelta,
    rightExtensionLag: kneeR.extensionLag,
    leftExtensionLag: kneeL.extensionLag,
    hipExtensionTerminalStance: params.hipExtensionTerminalStance,
    ankleDorsiflexion: params.ankleDorsiflexion,
    trunkAnteriorLeanDeg: params.trunkAnteriorLeanDeg,
    rightVarusValgusThrust: params.rightVarusValgusThrust,
    leftVarusValgusThrust: params.leftVarusValgusThrust,
    rightStaticAlignmentDeviation: params.rightStaticAlignmentDeviation,
    leftStaticAlignmentDeviation: params.leftStaticAlignmentDeviation,
    pelvicObliquityDeg: params.pelvicObliquityDeg,
    trendelenburgFlag: params.trendelenburgFlag,
    stepWidthProxy: params.stepWidthProxy,
    fppaRight: params.fppaRight,
    fppaLeft: params.fppaLeft,
    strideTimeAsymmetry: params.strideTimeAsymmetry,
    doubleSupportRatio: params.doubleSupportRatio,
    gaitSpeedProxy: params.gaitSpeedProxy,
    fallbackMode: fallbackMode,
    severity: severity,
  );

  final extra = <String, Object?>{
    'severity': severity,
    'kl_score': kl.score,
    'kl_grade': kl.grade,
    'clinical_flags': flags,
    'bilateral_pattern_detected': bilateral,
    'primary_view_confidence': metrics.confidence,
  };

  return (metrics: metrics, extra: extra);
}
