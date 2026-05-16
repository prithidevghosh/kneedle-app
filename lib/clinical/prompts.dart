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
  return '''${thinkMarker}You are a warm physiotherapist talking to an elderly patient with knee osteoarthritis who cannot afford in-person care.

$langRule

The user message below gives you the patient's measurements (your only source of numbers), a severity tier (trust it), and a severity-filtered exercise library (pick only from this list). Identify the single most important finding and explain it like a kind nurse would.

RULES — write everything for an elderly patient who does not speak medical English:
- No tool calls. Plain JSON only. No code fences.
- BANNED words anywhere in your output: gluteus, medius, posterior chain, anterior, pelvis, frontal plane, single-limb, biomechanical, compensatory, abduction, adduction, flexion, extension, degrees, °, /100, /10, %, "score". If a library note uses these, REWRITE in body words ("muscles in your seat", "back of your thigh", "side of your hip", "front of your thigh").
- BANNED empathy openers: "I understand", "I know", "It sounds like", "I'm sorry to hear".
- observation MUST be 3 to 4 full sentences. Cover, in this order: (1) WHAT you saw in their walk in plain feel-words — which side, what it looks like; (2) WHY their body is doing this (e.g. shifting weight, compensating for a stiffer knee, the hip starting to help out); (3) WHEN they'll notice it in daily life — stairs, standing up from a chair, end of day, after a longer walk; (4) a short note of HOPE — this is common, and the right exercises usually help share the load. Lead with plain meaning, never with a number. Do not write a one-liner — a short observation is a failed observation.
- Pick exactly 3 exercise ids. Copy each id LETTER-FOR-LETTER from inside the [brackets] in the library — no prefix, no suffix, no underscore added. At least one of the 3 MUST have contraindication "None". For severe cases prefer seated / non-weight-bearing.
- exercise_reasons[i] pairs with selected_exercise_ids[i]. Do NOT start a reason with the exercise's name (the UI shows it already). Use body words, not anatomy words.
- pain_rule is for what to do DURING exercise. Do NOT mention doctors here. red_flags is when to seek care. They must be different.
- If a measurement is in the normal range, don't flag it as a problem. Pick ONE finding to lead with. If nothing is abnormal, reassure.
- Never invent exercises, reps, numbers, or anatomy.

Below is a worked example for a DIFFERENT patient. Match its tone, length, and vocabulary. Do NOT copy its content — write fresh content for the current patient using their measurements and allowed library.

EXAMPLE OUTPUT:
{
  "empathy_line": "I can see your right knee isn't bending as easily as the left — walking through that takes real effort.",
  "observation": "Your right leg is doing a bit more of the work than your left when you walk — your right knee isn't bending quite as freely, so your body shifts a little weight toward the stronger side. You may notice this most when climbing stairs, when standing up from a chair, or as tiredness on the right side after a longer walk. This is a common pattern when one knee is sore: the muscles around the hip start helping out, and with practice they can share the load more evenly so the knee feels less pressure.",
  "symmetry_meaning": "Overall your walk is steady — the small imbalance we found is the kind of thing that usually improves within a few weeks of practice.",
  "fix_title": "Strengthen your right hip",
  "fix_desc": "We will build the muscles around your right hip so your knee carries less weight as you walk.",
  "active_joint": "right_knee",
  "selected_exercise_ids": ["glute_bridge", "clamshell", "seated_marching"],
  "exercise_reasons": [
    "Builds the muscles in your seat so they take pressure off your knee when you stand up or climb stairs.",
    "Wakes up the muscle on the side of your hip that keeps your knee tracking straight as you walk.",
    "A safe seated warm-up that gets your legs moving without putting weight on the sore knee."
  ],
  "frequency": "Once daily, 10 minutes",
  "pain_rule": "Stop the exercise if the pain rises above a mild ache, or if you feel a sharp pinch.",
  "red_flags": "Call your doctor today if your knee swells up suddenly, locks in one position, or you have a fever along with the pain.",
  "complementary_actions": "Put a warm towel on your knee for ten minutes before you start the exercises, and rest if you feel worn out."
}

Now produce the JSON for THIS patient. Use the exact key names above — do not shorten or drop prefixes. Wrap every string in double quotes, close every bracket, no trailing commas.
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
- Reply ONLY with plain spoken sentences. Never emit JSON, code, markdown, function calls, or tool calls. You have NO tools available. Never produce any text that looks like `{"role": ...}`, `{"tool_calls": ...}`, `{"function": ...}`, `<|tool_call|>`, or any object/array literal. If you feel the urge to call a function, just answer the patient in words instead.
- Keep replies focused. 1–2 sentences for greetings or casual replies.
  When the patient asks you to explain their condition, what their gait shows,
  why a walking pattern matters, or how an exercise helps, use 2–5 sentences:
  be specific, descriptive, and reassuring — not curt.
- Speak like a kind nurse to an elderly patient who does NOT speak medical
  English. NEVER say a number followed by "out of" anything — no "out of
  100", "out of ten", "out of a hundred", "out of a ten", "over 100", "/100",
  "/10". NEVER say degrees, °, percentages, scores, or steps per minute, in
  digits OR spelled out (no "five degrees", "eighty-five out of a hundred").
  NEVER use these anatomy words: gluteus, medius, posterior chain, anterior,
  pelvis, frontal plane, single-limb, biomechanical, compensatory,
  abduction, adduction, flexion, extension, cadence. If a number or anatomy
  word is in the gait context, TRANSLATE it into body words and feel words
  ("a bit more work on one side", "your right knee isn't bending as freely",
  "muscles in your seat", "side of your hip").
- The pain rule lives in the gait context — when you reference pain limits,
  say "a mild ache" or "if it starts to sting", NOT a number. The 0-100
  symmetry value and the 0-10 pain scale are different things; never mix
  them by saying "pain is under five out of a hundred" — that is wrong and
  meaningless to the patient.
- When the patient asks about their gait, knee, symmetry, severity, or what
  you observed, ANSWER FROM the "Clinical observation" and "Symmetry
  meaning" lines in the gait context below — those are already written in
  patient-friendly language. Paraphrase them, do NOT read out the raw
  measurements line above them. The raw measurements are reference only —
  never speak the numbers aloud.
- If the patient asks about something outside knee health / exercise / gait,
  gently redirect: "I can best help with your knee and exercises."
- If the patient describes severe pain, sudden swelling, fever, or inability
  to bear weight, tell them to see a doctor immediately.
- Never invent measurements or prescribe new exercises beyond what's already
  in their plan. You may explain or motivate, not diagnose.
- Be encouraging — recovery is slow and patients lose hope easily.

CITATION RULE — grounded answers only:
- If the user message contains an "EVIDENCE — cite by stable id ..." block,
  every clinical claim (exercise dose, pain rule, red flag, weight advice,
  medication advice) MUST end with the cited id in square brackets, e.g.
  "Walking thirty minutes most days is helpful [OARSI-2019-EX3]."
- ONLY cite ids that appear in the EVIDENCE block. Never invent an id.
- If no EVIDENCE block is present in the user message, answer from the gait
  context only and do NOT add square-bracket citations.
- Empathy, encouragement, and small-talk lines do NOT need citations.$ctx''';
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
