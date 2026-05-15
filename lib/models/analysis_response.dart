
import 'dart:convert';

import '../data/exercise_library.dart';
import '../gait/pipeline.dart';
import '../services/gemma_stats.dart';

/// Bilingual structured exercise prescription. 1:1 with `AnalysisResponse`
/// in `kneedle-backend/models.py`. Produced by `GemmaService.analyseGait`.
class PrescribedExercise {
  const PrescribedExercise({
    required this.def,
    required this.reason,
  });

  final ExerciseDef def;
  final String reason;

  Map<String, Object?> toJson() => {
        ...def.toJson(),
        'reason': reason,
      };
}

class AnalysisResponse {
  AnalysisResponse({
    required this.observation,
    required this.observationEn,
    required this.fixTitle,
    required this.fixDesc,
    required this.fixTitleEn,
    required this.fixDescEn,
    required this.exercises,
    required this.activeJoint,
    required this.symmetryScore,
    required this.sessionNumber,
    required this.metrics,
    this.thinking,
    this.severity = 'moderate',
    this.symmetryBand = 'fair',
    this.symmetryMeaning = '',
    this.symmetryMeaningEn = '',
    this.empathyLine = '',
    this.empathyLineEn = '',
    this.frequency = '',
    this.frequencyEn = '',
    this.painRule = '',
    this.painRuleEn = '',
    this.redFlags = '',
    this.redFlagsEn = '',
    this.referralRecommended = false,
    this.referralText = '',
    this.referralTextEn = '',
    this.complementaryActions = '',
    this.complementaryActionsEn = '',
    this.klProxyGrade = 'kl_0',
    this.clinicalFlags = const [],
    this.bilateralPatternDetected = false,
    this.primaryViewConfidence = 0,
    this.stats,
  });

  /// Telemetry from the Gemma generation call that produced this response —
  /// populated by `GemmaService.analyseGait`, surfaced in the result UI's
  /// tokens-per-second pill. Null for the hardcoded fallback path.
  LlmStats? stats;

  AnalysisResponse copyWith({LlmStats? stats}) {
    final out = AnalysisResponse(
      observation: observation,
      observationEn: observationEn,
      fixTitle: fixTitle,
      fixDesc: fixDesc,
      fixTitleEn: fixTitleEn,
      fixDescEn: fixDescEn,
      exercises: exercises,
      activeJoint: activeJoint,
      symmetryScore: symmetryScore,
      sessionNumber: sessionNumber,
      metrics: metrics,
      thinking: thinking,
      severity: severity,
      symmetryBand: symmetryBand,
      symmetryMeaning: symmetryMeaning,
      symmetryMeaningEn: symmetryMeaningEn,
      empathyLine: empathyLine,
      empathyLineEn: empathyLineEn,
      frequency: frequency,
      frequencyEn: frequencyEn,
      painRule: painRule,
      painRuleEn: painRuleEn,
      redFlags: redFlags,
      redFlagsEn: redFlagsEn,
      referralRecommended: referralRecommended,
      referralText: referralText,
      referralTextEn: referralTextEn,
      complementaryActions: complementaryActions,
      complementaryActionsEn: complementaryActionsEn,
      klProxyGrade: klProxyGrade,
      clinicalFlags: clinicalFlags,
      bilateralPatternDetected: bilateralPatternDetected,
      primaryViewConfidence: primaryViewConfidence,
      stats: stats ?? this.stats,
    );
    return out;
  }

  final String observation;
  final String observationEn;
  final String fixTitle;
  final String fixDesc;
  final String fixTitleEn;
  final String fixDescEn;
  final List<PrescribedExercise> exercises;
  final String activeJoint;
  final double symmetryScore;
  final int sessionNumber;
  final String? thinking;
  final GaitMetrics metrics;
  final String severity;
  final String symmetryBand;
  final String symmetryMeaning;
  final String symmetryMeaningEn;
  final String empathyLine;
  final String empathyLineEn;
  final String frequency;
  final String frequencyEn;
  final String painRule;
  final String painRuleEn;
  final String redFlags;
  final String redFlagsEn;
  final bool referralRecommended;
  final String referralText;
  final String referralTextEn;
  final String complementaryActions;
  final String complementaryActionsEn;
  final String klProxyGrade;
  final List<String> clinicalFlags;
  final bool bilateralPatternDetected;
  final double primaryViewConfidence;

  /// Rehydrate an [AnalysisResponse] from a previously persisted
  /// `toContextJson()` payload (saved on a [GaitSession] as `analysisJson`).
  /// Used by the history / last-check-in surfaces to reopen the full report
  /// without re-running Gemma. Exercise defs are looked up by id from the
  /// in-binary library; any missing id is silently dropped from the result.
  static AnalysisResponse? fromStoredJson(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final map = decoded is Map<String, Object?>
          ? decoded
          : (decoded is Map ? decoded.cast<String, Object?>() : null);
      if (map == null) return null;
      return _fromContextMap(map);
    } catch (_) {
      return null;
    }
  }

  static AnalysisResponse _fromContextMap(Map<String, Object?> m) {
    final metricsRaw = m['metrics'];
    final metricsMap = metricsRaw is Map
        ? metricsRaw.cast<String, Object?>()
        : const <String, Object?>{};
    final metrics = GaitMetrics(
      kneeAngleRight: _d(metricsMap['knee_angle_right']),
      kneeAngleLeft: _d(metricsMap['knee_angle_left']),
      kneeAngleDiff: _d(metricsMap['knee_angle_diff']),
      symmetryScore: _d(metricsMap['symmetry_score']),
      trunkLeanAngle: _d(metricsMap['trunk_lean_angle']),
      trunkLeanDirection: metricsMap['trunk_lean_direction'] as String?,
      cadence: _d(metricsMap['cadence'] ?? metricsMap['cadence_steps_min']),
      framesAnalysed: _i(metricsMap['frames_analysed']) ?? 0,
      confidence: _d(metricsMap['confidence']) ?? 0,
      klProxyScore: _d(metricsMap['kl_proxy_score']) ?? 0,
      klProxyGrade: (metricsMap['kl_proxy_grade'] as String?) ?? 'kl_0',
      clinicalFlags:
          ((metricsMap['clinical_flags'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
      bilateralPatternDetected:
          metricsMap['bilateral_pattern_detected'] == true,
      rightStaticAlignmentDeviation:
          _d(metricsMap['right_static_alignment_deviation']) ?? 0,
      leftStaticAlignmentDeviation:
          _d(metricsMap['left_static_alignment_deviation']) ?? 0,
      doubleSupportRatio: _d(metricsMap['double_support_ratio']) ?? 20,
      gaitSpeedProxy: _d(metricsMap['gait_speed_proxy']) ?? 0,
      severity: (metricsMap['severity'] as String?) ?? 'moderate',
    );

    final exercises = <PrescribedExercise>[];
    for (final raw in (m['exercises'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final ex = raw.cast<String, Object?>();
      final id = ex['id'] as String?;
      if (id == null) continue;
      final def = getExerciseById(id);
      if (def == null) continue;
      exercises.add(PrescribedExercise(
        def: def,
        reason: (ex['reason'] as String?) ?? '',
      ));
    }

    return AnalysisResponse(
      observation: (m['observation'] as String?) ?? '',
      observationEn: (m['observation_en'] as String?) ?? '',
      fixTitle: (m['fix_title'] as String?) ?? '',
      fixDesc: (m['fix_desc'] as String?) ?? '',
      fixTitleEn: (m['fix_title_en'] as String?) ?? '',
      fixDescEn: (m['fix_desc_en'] as String?) ?? '',
      exercises: exercises,
      activeJoint: (m['active_joint'] as String?) ?? 'unknown',
      symmetryScore: _d(m['symmetry_score']) ?? 0,
      sessionNumber: _i(m['session_number']) ?? 1,
      metrics: metrics,
      severity: (m['severity'] as String?) ?? 'moderate',
      symmetryBand: (m['symmetry_band'] as String?) ?? 'fair',
      symmetryMeaning: (m['symmetry_meaning'] as String?) ?? '',
      symmetryMeaningEn: (m['symmetry_meaning_en'] as String?) ?? '',
      empathyLine: (m['empathy_line'] as String?) ?? '',
      empathyLineEn: (m['empathy_line_en'] as String?) ?? '',
      frequency: (m['frequency'] as String?) ?? '',
      frequencyEn: (m['frequency_en'] as String?) ?? '',
      painRule: (m['pain_rule'] as String?) ?? '',
      painRuleEn: (m['pain_rule_en'] as String?) ?? '',
      redFlags: (m['red_flags'] as String?) ?? '',
      redFlagsEn: (m['red_flags_en'] as String?) ?? '',
      referralRecommended: m['referral_recommended'] == true,
      referralText: (m['referral_text'] as String?) ?? '',
      referralTextEn: (m['referral_text_en'] as String?) ?? '',
      complementaryActions: (m['complementary_actions'] as String?) ?? '',
      complementaryActionsEn:
          (m['complementary_actions_en'] as String?) ?? '',
      klProxyGrade: metrics.klProxyGrade,
    );
  }

  static double? _d(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
  static int? _i(Object? v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

  /// Compact JSON used by the voice-chat layer to feed gait context into the
  /// system prompt. Mirrors the bilingual `_format_context_block` payload in
  /// `voice_chat_service.py`.
  Map<String, Object?> toContextJson() => {
        'severity': severity,
        'kl_proxy_grade': klProxyGrade,
        'active_joint': activeJoint,
        'symmetry_score': symmetryScore,
        'symmetry_band': symmetryBand,
        'clinical_flags': clinicalFlags,
        'bilateral_pattern_detected': bilateralPatternDetected,
        'session_number': sessionNumber,
        'metrics': metrics.toJson(),
        'symmetry_meaning': symmetryMeaning,
        'symmetry_meaning_en': symmetryMeaningEn,
        'observation': observation,
        'observation_en': observationEn,
        'fix_title': fixTitle,
        'fix_title_en': fixTitleEn,
        'fix_desc': fixDesc,
        'fix_desc_en': fixDescEn,
        'exercises': [for (final e in exercises) e.toJson()],
        'frequency': frequency,
        'frequency_en': frequencyEn,
        'pain_rule': painRule,
        'pain_rule_en': painRuleEn,
        'red_flags': redFlags,
        'red_flags_en': redFlagsEn,
        'referral_recommended': referralRecommended,
        'referral_text': referralText,
        'referral_text_en': referralTextEn,
        'complementary_actions': complementaryActions,
        'complementary_actions_en': complementaryActionsEn,
      };
}
