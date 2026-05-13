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
