import '../data/exercise_library.dart';
import '../gait/pipeline.dart';

/// LLM prompt builders. 1:1 ports of `build_system_prompt` and
/// `build_user_prompt` in `kneedle-backend/gemma_client.py`.
///
/// Kept in their own file so the prompt copy stays auditable independently of
/// the inference plumbing in `gemma_service.dart`.

const Map<String, String> _langInstruction = {
  'bn':
      'You MUST respond entirely in Bengali (বাংলা). All localized text fields must be in Bengali script.',
  'hi':
      'You MUST respond entirely in Hindi (हिन्दी). All localized text fields must be in Hindi script.',
  'en': 'Respond in clear, simple English.',
};

/// Perf lever: toggle Gemma E2B/E4B's reasoning mode.
///
/// `true` — emit `<|think|>` at the top of the prompt. Model produces a long
/// hidden chain-of-thought before the visible JSON (~1.5-3k extra tokens).
/// Higher quality, but on-device decode runs 3-5× longer.
///
/// `false` — skip the marker. Model commits straight to the JSON. ~5-15%
/// quality dip on prose nuance, but matches the latency target on-device.
const bool kEnableAnalysisThinking = false;

String buildAnalysisSystemPrompt(String lang) {
  final langRule = _langInstruction[lang] ?? _langInstruction['bn']!;
  const thinkMarker = kEnableAnalysisThinking ? '<|think|>\n' : '';
  return '''${thinkMarker}You are a compassionate physiotherapist specialising in knee osteoarthritis.
You are analysing the walking pattern of an elderly patient who cannot afford
in-person physiotherapy and depends on this app.

$langRule

You will be given:
1. Precise biomechanical measurements extracted by MediaPipe Pose from the
   patient's walking video (joint angles, symmetry, trunk lean, cadence).
   These numbers are your source of truth for quantitative claims. Up to 4
   still frames from the same recording (frontal + sagittal views) may be
   attached for visual context — use them to ground your prose, not to
   invent measurements.
2. A pre-computed severity tier (normal/mild/moderate/severe) — TRUST IT.
   "normal" means no clinical OA signs detected — frame the response as
   reassurance + general conditioning, not treatment.
3. A SEVERITY-FILTERED exercise library — you may ONLY pick from this list

Your job is to identify the single primary clinical finding from the
measurements first, then explain it to the patient in warm, simple language,
anchored to specific numbers — not generic advice.

CRITICAL RULES:
- DO NOT emit any function/tool calls. This task has no tools available. Respond with the JSON object below as plain text only.
- Open the observation with empathy or what you observed — never with filler
- Speak directly to the patient in warm, simple language — not medical jargon
- Reference at least one specific measurement in the observation, AND interpret
  it ("your symmetry score is 58 — normal is above 80")
- ONE specific correction only in fix_title/fix_desc — not multiple things
- Pick exactly 3 exercises from the provided library (NOT 2)
- AT LEAST ONE of the 3 exercises MUST have contraindication = "None"
  (a safe fallback the patient can always do)
- For severe cases, prefer non-weight-bearing or seated exercises
- Never invent exercises or modify rep counts
- Never make up measurements — only use the numbers provided
- Be encouraging — this patient is in pain and trying hard

OUTPUT FORMAT — respond with ONLY this JSON, no other text. All text fields
must be in the patient's language (per the rule above). Keep every string
SHORT — this output runs on-device with a tight token budget.
{
  "empathy_line": "ONE warm sentence acknowledging difficulty",
  "observation": "2-3 sentences tying numbers to plain meaning",
  "symmetry_meaning": "ONE sentence interpreting the symmetry score",
  "fix_title": "Short title of the single correction (≤6 words)",
  "fix_desc": "1 sentence description",
  "active_joint": "right_knee OR left_knee OR hips OR ankles",
  "selected_exercise_ids": ["id_1", "id_2", "id_3"],
  "exercise_reasons": ["1-sentence reason for ex1", "for ex2", "for ex3"],
  "frequency": "How often / for how long",
  "pain_rule": "When to stop",
  "red_flags": "When to seek medical care",
  "complementary_actions": "Non-exercise advice — weight, heat, sleeve"
}
''';
}

String buildAnalysisUserPrompt({
  required GaitMetrics metrics,
  required String age,
  required String knee,
  required String severity,
  required List<ExerciseDef> library,
  int frontalFrameCount = 0,
  int sagittalFrameCount = 0,
}) {
  const kneeDesc = {
    'left': 'left knee',
    'right': 'right knee',
    'both': 'both knees',
  };

  var primaryFinding = 'general gait pattern';
  if ((metrics.symmetryScore ?? 100) < 70) {
    final r = metrics.kneeAngleRight ?? 0;
    final l = metrics.kneeAngleLeft ?? 0;
    final worse = r < l ? 'right' : 'left';
    primaryFinding = 'significant gait asymmetry favouring the $worse side';
  } else if ((metrics.trunkLeanAngle ?? 0) > 6) {
    primaryFinding =
        'trunk leaning ${metrics.trunkLeanDirection ?? "to one side"} during walking';
  } else if (metrics.toeOutAngleRight != null &&
      metrics.toeOutAngleLeft != null &&
      metrics.toeOutAngleRight!.abs() < 3 &&
      metrics.toeOutAngleLeft!.abs() < 3) {
    primaryFinding =
        'low toe-out angle — candidate for toe-out gait modification (Shull 2013)';
  }

  const severityGuidance = {
    'severe':
        'SEVERE: Patient has marked deformity / asymmetry / very slow gait. '
            'Prefer seated, supine, or aquatic exercises. Avoid deep knee bends. '
            'Always include quad_set or seated_marching as a safe foundation.',
    'moderate':
        'MODERATE: Patient has noticeable but functional gait deficit. '
            'Mix of supine and standing exercises. Avoid only deep loaded squats.',
    'mild':
        'MILD: Gait is largely preserved. Full library is available, '
            'focus on whichever exercise targets the specific finding.',
    'normal':
        'NORMAL: Gait shows no clinical signs of OA. Recommend general '
            'conditioning (quad strength, calf, hip stability) for prevention. '
            'Frame the response as reassurance, not treatment.',
  };

  String fmtOpt(num? v) => v == null ? 'not detected' : v.toString();

  return '''PATIENT PROFILE:
- Age: $age years old
- Diagnosed condition: Knee osteoarthritis
- Context: Cannot afford physiotherapy, using this app for daily guidance

MEDIAPIPE BIOMECHANICAL MEASUREMENTS (clinically precise):
- Right knee flexion angle: ${fmtOpt(metrics.kneeAngleRight)}°
- Left knee flexion angle: ${fmtOpt(metrics.kneeAngleLeft)}°
- Knee angle difference (asymmetry): ${fmtOpt(metrics.kneeAngleDiff)}°
- Gait symmetry score: ${fmtOpt(metrics.symmetryScore)}/100 (100 = perfect symmetry, normal >80)
- Trunk lateral lean: ${fmtOpt(metrics.trunkLeanAngle)}° toward ${metrics.trunkLeanDirection ?? 'unknown'}
- Right toe-out angle: ${fmtOpt(metrics.toeOutAngleRight)}°
- Left toe-out angle: ${fmtOpt(metrics.toeOutAngleLeft)}°
- Walking cadence: ${fmtOpt(metrics.cadence)} steps/minute
- Frames successfully analysed: ${metrics.framesAnalysed}
- Detection confidence: ${(metrics.confidence * 100).toStringAsFixed(0)}%

PRIMARY CLINICAL FINDING: $primaryFinding
SEVERITY TIER (computed deterministically): ${severity.toUpperCase()}
SEVERITY GUIDANCE: ${severityGuidance[severity] ?? severityGuidance['moderate']}

${(frontalFrameCount + sagittalFrameCount) == 0 ? '''Reason directly from the MediaPipe measurements above. No video frames are
provided — the on-device pose pipeline has already extracted the clinically
relevant signals (knee flexion angles, symmetry, trunk lean, toe-out,
cadence). Treat those numbers as your sole source of truth.''' : '''Reason primarily from the MediaPipe measurements above — those numbers are
your source of truth for any quantitative claim. $frontalFrameCount frontal
(walking toward camera) and $sagittalFrameCount sagittal (walking sideways)
snapshots from the same recording are attached as images for visual context
only; use them to ground your prose ("I can see your trunk leaning right"),
not to invent new measurements.'''}

SEVERITY-FILTERED EXERCISE LIBRARY:
You MUST select exactly 3 exercises from THIS LIST ONLY. Do not invent
exercises. Do not modify rep counts. At least one selection MUST have
contraindication = "None".

${formatLibraryForPrompt(library)}

Provide your assessment in the exact JSON format specified.''';
}

// ─── Voice-chat system prompt — port of voice_chat_service.py ────────────────

const Map<String, String> _voiceLangRule = {
  'bn': 'You MUST respond in Bengali (বাংলা). Use Bengali script only.',
  'hi': 'You MUST respond in Hindi (हिन्दी). Use Devanagari script only.',
  'en': 'Respond in clear, simple English.',
};

String buildVoiceChatSystemPrompt({
  required String lang,
  String? gaitContextBlock,
}) {
  final langRule = _voiceLangRule[lang] ?? _voiceLangRule['en']!;
  final ctx = (gaitContextBlock == null || gaitContextBlock.isEmpty)
      ? ''
      : '\n\nPATIENT\'S LAST GAIT ANALYSIS — use these specifics when answering. '
          'If the patient asks how their knee is doing, summarise from the '
          'observation, severity, symmetry, and clinical flags below. If they '
          'ask about exercises, reference the prescribed list by name.\n'
          '$gaitContextBlock';

  return '''You are a warm, encouraging physiotherapy assistant for elderly patients
with knee osteoarthritis. You speak with patients about their gait, prescribed
exercises, pain management, and recovery progress.

$langRule

CRITICAL RULES:
- Keep replies focused. 1–2 sentences for greetings or casual replies.
  When the patient asks you to explain their condition, what a number means,
  why a walking pattern matters, or how an exercise helps, use 2–5 sentences:
  be specific, descriptive, and reassuring — not curt.
- Speak naturally, like a kind nurse — no medical jargon, no markdown, no lists.
  When you need to give a number, say it in words a patient understands
  ("your right knee bends about 50 degrees, a little less than your left").
- When the patient asks about their knee condition, gait, symmetry, severity,
  or exercises, answer with the SPECIFIC details from the gait analysis below
  (real numbers, the actual observation, named exercises). Do NOT deflect with
  generic "how are you feeling?" small-talk when concrete context exists.
- If the patient asks about something outside knee health / exercise / gait,
  gently redirect: "I can best help with your knee and exercises."
- If the patient describes severe pain, sudden swelling, fever, or inability
  to bear weight, tell them to see a doctor immediately.
- Never invent measurements or prescribe new exercises beyond what's already
  in their plan. You may explain or motivate, not diagnose.
- Be encouraging — recovery is slow and patients lose hope easily.$ctx''';
}

/// Render the gait context as the dense bilingual briefing the backend used.
String formatGaitContextBlock(Map<String, Object?> gait, String lang) {
  final useBn = lang == 'bn';
  String pick(String key) {
    final raw = useBn ? gait[key] : (gait['${key}_en'] ?? gait[key]);
    return raw == null ? '' : raw.toString().trim();
  }

  final metrics = (gait['metrics'] as Map?)?.cast<String, Object?>() ?? const {};
  final flags = (gait['clinical_flags'] as List?)?.cast<String>() ?? const [];
  final flagsStr = flags.isEmpty ? 'none' : flags.join(', ');

  final parts = <String>[
    '- Severity: ${gait['severity'] ?? 'unknown'} (KL grade: ${gait['kl_proxy_grade'] ?? 'unknown'})',
    '- Active joint: ${gait['active_joint'] ?? 'unknown'}',
    '- Symmetry score: ${gait['symmetry_score'] ?? 'unknown'}/100 (band: ${gait['symmetry_band'] ?? 'unknown'})',
    '- Clinical flags: $flagsStr',
    '- Bilateral pattern: ${gait['bilateral_pattern_detected'] ?? false}',
    '- Session number: ${gait['session_number'] ?? 'unknown'}',
  ];

  if (metrics.isNotEmpty) {
    parts.add(
      '- Knee flexion: right=${metrics['knee_angle_right']}° '
      'left=${metrics['knee_angle_left']}° '
      '(diff ${metrics['knee_angle_diff']}°), '
      'cadence=${metrics['cadence']} steps/min',
    );
  }

  if (pick('symmetry_meaning').isNotEmpty) {
    parts.add('- Symmetry meaning: ${pick('symmetry_meaning')}');
  }
  if (pick('observation').isNotEmpty) {
    parts.add('- Clinical observation: ${pick('observation')}');
  }
  if (pick('fix_title').isNotEmpty || pick('fix_desc').isNotEmpty) {
    parts.add('- Recommended fix: ${pick('fix_title')} — ${pick('fix_desc')}');
  }

  final exercises = (gait['exercises'] as List?) ?? const [];
  if (exercises.isNotEmpty) {
    final lines = <String>[];
    for (final raw in exercises) {
      if (raw is! Map) continue;
      final ex = raw.cast<String, Object?>();
      final name = useBn
          ? (ex['name'] ?? ex['name_en'] ?? '')
          : (ex['name_en'] ?? ex['name'] ?? '');
      final reps = useBn
          ? (ex['reps'] ?? ex['reps_en'] ?? '')
          : (ex['reps_en'] ?? ex['reps'] ?? '');
      final reason = (ex['reason'] ?? '').toString().trim();
      var line = '  • $name ($reps)';
      if (reason.isNotEmpty) line += ' — $reason';
      lines.add(line);
    }
    parts.add('- Prescribed exercises:\n${lines.join('\n')}');
  } else {
    parts.add('- Prescribed exercises: none yet');
  }

  if (pick('frequency').isNotEmpty) parts.add('- Frequency: ${pick('frequency')}');
  if (pick('pain_rule').isNotEmpty) parts.add('- Pain rule: ${pick('pain_rule')}');
  if (pick('red_flags').isNotEmpty) parts.add('- Red flags: ${pick('red_flags')}');
  if ((gait['referral_recommended'] == true) && pick('referral_text').isNotEmpty) {
    parts.add('- Referral advised: ${pick('referral_text')}');
  }
  if (pick('complementary_actions').isNotEmpty) {
    parts.add('- Complementary actions: ${pick('complementary_actions')}');
  }

  return parts.join('\n');
}
