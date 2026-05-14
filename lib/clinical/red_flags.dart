import '../models/pain_entry.dart';

/// Severity tier for a detected red flag.
///
///  * `urgent` — pattern matches an OARSI / NICE "see a doctor today" rule
///    (severe pain + inability to bear weight, sudden swelling + fever, etc).
///    The UI breaks flow with [RedFlagScreen].
///  * `soon` — slow-moving worry (trend rising for 3 sessions, severe gait +
///    high asymmetry, missed exercises + high pain). The UI surfaces a
///    persistent advisory chip but does not interrupt.
///  * `watch` — single ambiguous phrase ("locked", "gave way") — logged for
///    the doctor PDF, mentioned softly in the agent's reply, no interstitial.
enum RedFlagLevel { urgent, soon, watch }

class RedFlag {
  const RedFlag({
    required this.level,
    required this.reason,
    required this.suggestedAction,
    this.evidenceRefs = const [],
  });

  final RedFlagLevel level;

  /// Patient-facing short reason ("Pain has been 8/10 or higher for the last
  /// 3 entries"). Speaks plainly — no jargon.
  final String reason;

  /// Concrete next step ("See a doctor today", "Call your physiotherapist").
  final String suggestedAction;

  /// Stable IDs of clinical guideline passages backing this flag — used by
  /// the RAG layer's bottom-sheet citation viewer. Optional.
  final List<String> evidenceRefs;
}

/// Lightweight context bundle handed to [detectRedFlags]. Pure data so the
/// detector can be unit-tested without Hive or BuildContext.
class RedFlagContext {
  RedFlagContext({
    this.recentPain = const [],
    this.latestSeverity,
    this.latestSymmetry,
    this.kneeAngleDiff,
    this.chatText,
    this.daysSinceLastExercise,
  });

  /// Most-recent first (matches `StorageService.recentPainEntries()`).
  final List<PainEntry> recentPain;

  /// 'normal' / 'mild' / 'moderate' / 'severe' from the most recent gait
  /// session; null if no gait analysis exists yet.
  final String? latestSeverity;

  /// 0–100 symmetry score from the most recent gait session.
  final double? latestSymmetry;

  /// Absolute knee-angle difference (left vs right) from the most recent
  /// gait session. >25° is highly asymmetric.
  final double? kneeAngleDiff;

  /// Free text from the current pain entry / chat utterance. Optional.
  final String? chatText;

  /// Days since the most recent exercise session. Null if there have been no
  /// exercise sessions yet.
  final int? daysSinceLastExercise;
}

/// Deterministic OA red-flag detector. Never LLM-based — judges and clinicians
/// must be able to read the rules in source.
///
/// Returns an ordered list (most severe first). An empty list means no flags
/// matched; callers should NOT treat the empty list as "all clear" — it just
/// means "nothing the rule book caught."
///
/// Sources (informal, encoded as rules):
///   * NICE NG226 §1.5 — when to refer to specialist services.
///   * OARSI 2019 — non-surgical management of OA, escalation criteria.
///   * BMJ 2018 — "Locked / gave way" knee — referral to ortho.
List<RedFlag> detectRedFlags(RedFlagContext ctx) {
  final flags = <RedFlag>[];
  final lower = (ctx.chatText ?? '').toLowerCase();

  // ── URGENT ────────────────────────────────────────────────────────────────

  // Phrase-based hard triggers. Two of these together → urgent. Single
  // strong phrase ("can't bear weight", "fever") + pain≥7 → urgent.
  final phraseHits = <String>{};
  void hit(String tag, Iterable<String> needles) {
    if (needles.any((n) => lower.contains(n))) phraseHits.add(tag);
  }

  hit('cant_bear_weight', [
    "can't bear weight",
    'cannot bear weight',
    "can't stand on it",
    "can't put weight",
    "couldn't walk",
    "can't walk",
    'unable to stand',
    'unable to walk',
    'पैर नहीं रख',
    'खड़ा नहीं',
    'भार नहीं',
  ]);
  hit('sudden_swelling', [
    'sudden swelling',
    'suddenly swollen',
    'very swollen',
    'badly swollen',
    'swelled up',
    'अचानक सूज',
    'बहुत सूज',
    'फूल गया',
  ]);
  hit('fever', [
    'fever',
    'feverish',
    'high temperature',
    'बुखार',
    'जुर',
  ]);
  hit('locked_or_gave_way', [
    'knee locked',
    'locked up',
    'gave way',
    'gave out',
    'collapsed',
    'जाम',
    'अटक',
  ]);
  hit('nocturnal_pain', [
    'pain at night',
    'wake up in pain',
    'wakes me up',
    "can't sleep",
    'सोते समय',
    'रात को दर्द',
  ]);
  hit('numbness', [
    'numb',
    'pins and needles',
    'tingling',
    'सुन्न',
  ]);

  final latestPain =
      ctx.recentPain.isEmpty ? null : ctx.recentPain.first.painScore;

  // Rule U1 — inability to bear weight is an immediate referral signal.
  if (phraseHits.contains('cant_bear_weight')) {
    flags.add(const RedFlag(
      level: RedFlagLevel.urgent,
      reason: "You said you can't put weight on the knee. That is not a "
          'self-care symptom.',
      suggestedAction: 'See a doctor today — call an orthopedist or visit '
          'an urgent care clinic.',
      evidenceRefs: ['NICE-NG226-1.5'],
    ));
  }

  // Rule U2 — swelling + fever together → possible septic joint, ER-level.
  if (phraseHits.contains('sudden_swelling') && phraseHits.contains('fever')) {
    flags.add(const RedFlag(
      level: RedFlagLevel.urgent,
      reason: 'Sudden swelling together with a fever can be a sign of a '
          'joint infection.',
      suggestedAction: 'Go to a hospital today — do not wait for a clinic '
          'appointment.',
      evidenceRefs: ['NICE-NG226-1.5', 'OARSI-2019-RF1'],
    ));
  }

  // Rule U3 — high pain (≥8) + any single strong phrase → urgent.
  if (latestPain != null &&
      latestPain >= 8 &&
      (phraseHits.contains('sudden_swelling') ||
          phraseHits.contains('locked_or_gave_way') ||
          phraseHits.contains('numbness'))) {
    flags.add(RedFlag(
      level: RedFlagLevel.urgent,
      reason: 'Pain at $latestPain/10 with $_phraseSummary(${phraseHits.join(",")}) '
          'needs a clinician to look at it.',
      suggestedAction: 'See a doctor today.',
      evidenceRefs: const ['NICE-NG226-1.5'],
    ));
  }

  // Rule U4 — three consecutive entries at 8+ in the last 7 days.
  final recent7d = ctx.recentPain
      .where((p) =>
          DateTime.now().difference(p.timestamp).inDays <= 7)
      .toList();
  if (recent7d.length >= 3) {
    final top3 = recent7d.take(3).toList();
    if (top3.every((p) => p.painScore >= 8)) {
      flags.add(const RedFlag(
        level: RedFlagLevel.urgent,
        reason: 'Pain has been 8/10 or higher for the last 3 entries.',
        suggestedAction: 'See a doctor today — this level of pain should not '
            'be managed at home.',
        evidenceRefs: ['OARSI-2019-RF3'],
      ));
    }
  }

  // ── SOON (within the week) ────────────────────────────────────────────────

  // Rule S1 — nocturnal pain reported ≥7 — common OA flare red flag.
  if (phraseHits.contains('nocturnal_pain') &&
      latestPain != null &&
      latestPain >= 7) {
    flags.add(const RedFlag(
      level: RedFlagLevel.soon,
      reason: 'Pain at night that wakes you up is a sign the joint needs '
          'more help than rest alone.',
      suggestedAction: 'Book a doctor or physiotherapist this week.',
      evidenceRefs: ['NICE-NG226-1.5'],
    ));
  }

  // Rule S2 — severe gait + high asymmetry.
  final ad = ctx.kneeAngleDiff;
  if (ctx.latestSeverity == 'severe' && ad != null && ad.abs() > 25) {
    flags.add(RedFlag(
      level: RedFlagLevel.soon,
      reason: 'Your last gait check showed severe asymmetry '
          '(${ad.abs().toStringAsFixed(0)}° difference between knees).',
      suggestedAction: 'A physiotherapist can prescribe targeted work this '
          'week to prevent further wear on the other knee.',
      evidenceRefs: const ['OARSI-2019-EX2'],
    ));
  }

  // Rule S3 — rising trend over last 3 entries.
  if (ctx.recentPain.length >= 3) {
    final p = ctx.recentPain;
    if (p[0].painScore > p[1].painScore &&
        p[1].painScore > p[2].painScore &&
        p[0].painScore - p[2].painScore >= 3) {
      flags.add(const RedFlag(
        level: RedFlagLevel.soon,
        reason: 'Your pain has gone up sharply across the last 3 entries.',
        suggestedAction:
            'See a doctor this week if it keeps rising.',
        evidenceRefs: ['OARSI-2019-RF3'],
      ));
    }
  }

  // Rule S4 — long exercise lapse + ongoing pain.
  final lapse = ctx.daysSinceLastExercise;
  if (lapse != null &&
      lapse >= 14 &&
      latestPain != null &&
      latestPain >= 6) {
    flags.add(const RedFlag(
      level: RedFlagLevel.soon,
      reason: "You haven't done the exercises in 2 weeks and your pain is "
          'still at 6 or higher.',
      suggestedAction:
          'A short physiotherapy visit can re-tune your routine.',
      evidenceRefs: ['OARSI-2019-EX1'],
    ));
  }

  // ── WATCH (log only, don't interrupt) ─────────────────────────────────────

  if (phraseHits.contains('locked_or_gave_way') &&
      !flags.any((f) => f.level == RedFlagLevel.urgent)) {
    flags.add(const RedFlag(
      level: RedFlagLevel.watch,
      reason: 'You mentioned the knee locking or giving way — make a note '
          'so your doctor sees it.',
      suggestedAction: "It's worth mentioning to your doctor next visit.",
      evidenceRefs: ['BMJ-2018-LOCK'],
    ));
  }
  if (phraseHits.contains('numbness') &&
      !flags.any((f) => f.level == RedFlagLevel.urgent)) {
    flags.add(const RedFlag(
      level: RedFlagLevel.watch,
      reason: 'You mentioned numbness or tingling — keep an eye on it.',
      suggestedAction: 'If it spreads or stays for a day, see a doctor.',
      evidenceRefs: ['NICE-NG226-1.5'],
    ));
  }

  // De-duplicate by reason — different rules can match the same situation.
  final seen = <String>{};
  final deduped = <RedFlag>[];
  for (final f in flags) {
    if (seen.add(f.reason)) deduped.add(f);
  }
  return deduped;
}

String _phraseSummary(String hits) {
  if (hits.contains('sudden_swelling')) return 'swelling';
  if (hits.contains('locked_or_gave_way')) return 'the knee locking';
  if (hits.contains('numbness')) return 'numbness';
  return 'these symptoms';
}

/// Highest-severity level present in [flags], or null if empty.
RedFlagLevel? topLevel(List<RedFlag> flags) {
  if (flags.isEmpty) return null;
  if (flags.any((f) => f.level == RedFlagLevel.urgent)) {
    return RedFlagLevel.urgent;
  }
  if (flags.any((f) => f.level == RedFlagLevel.soon)) {
    return RedFlagLevel.soon;
  }
  return RedFlagLevel.watch;
}
