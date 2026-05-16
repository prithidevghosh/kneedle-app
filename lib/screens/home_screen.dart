import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/analysis_response.dart';
import '../models/gait_session.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';
import 'agent_screen.dart';
import 'exercise_coach_screen.dart';
import 'gait_capture_screen.dart';
import 'gait_result_screen.dart';
import 'pain_journal_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pain = ref.watch(painEntriesProvider);
    final gait = ref.watch(gaitSessionsProvider);
    final ex = ref.watch(exerciseSessionsProvider);

    final lastPain = pain.isEmpty ? null : pain.first;
    final lastGait = gait.isEmpty ? null : gait.first;
    final loggedToday = pain
        .where((p) => _isToday(p.timestamp))
        .length;
    final exerciseDays = _streakDays(ex.map((e) => e.timestamp));

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _Header()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                KneedleTheme.space5,
                KneedleTheme.space2,
                KneedleTheme.space5,
                KneedleTheme.space7,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _HeroCard(
                    painScore: lastPain?.painScore,
                    loggedToday: loggedToday,
                    exerciseDays: exerciseDays,
                  ),
                  const SizedBox(height: KneedleTheme.space6),
                  const KSectionTitle(
                    eyebrow: 'Quick actions',
                    title: 'What would you like to do?',
                  ),
                  const SizedBox(height: KneedleTheme.space4),
                  _PrimaryAction(
                    title: 'Hey Kneedle — talk to me',
                    subtitle: 'Speak. Gemma 4 does the rest.',
                    icon: Icons.auto_awesome_rounded,
                    accent: KneedleTheme.sage,
                    accentSoft: KneedleTheme.sageTint,
                    onTap: () => routeToAgent(context),
                  ),
                  const SizedBox(height: KneedleTheme.space3),
                  _PrimaryAction(
                    title: 'Run a gait check',
                    subtitle: '8-second walk · on-device analysis',
                    icon: Icons.directions_walk_rounded,
                    accent: KneedleTheme.amber,
                    accentSoft: KneedleTheme.amberTint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GaitCaptureScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: KneedleTheme.space3),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniAction(
                          title: 'Log pain',
                          subtitle: 'Voice or tap',
                          icon: Icons.mic_rounded,
                          tone: KCardTone.coral,
                          iconColor: KneedleTheme.coral,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PainJournalScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: KneedleTheme.space3),
                      Expanded(
                        child: _MiniAction(
                          title: 'Exercise',
                          subtitle: 'Live coaching',
                          icon: Icons.self_improvement_rounded,
                          tone: KCardTone.amber,
                          iconColor: KneedleTheme.amber,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ExerciseCoachScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KneedleTheme.space7),
                  const KSectionTitle(
                    eyebrow: 'Recent',
                    title: 'Last check-in',
                  ),
                  const SizedBox(height: KneedleTheme.space4),
                  if (lastGait != null)
                    _LastGaitCard(session: lastGait)
                  else
                    KCard(
                      tone: KCardTone.plain,
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: KneedleTheme.sageTint,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: KneedleTheme.sageDeep,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: KneedleTheme.space4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No gait sessions yet',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Run your first check to see knee insights here.',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final part =
        hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KneedleTheme.space5,
        KneedleTheme.space5,
        KneedleTheme.space5,
        KneedleTheme.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good $part',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Kneedle',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: KneedleTheme.hairline),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.notifications_none_rounded,
              color: KneedleTheme.sageDeep,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.painScore,
    required this.loggedToday,
    required this.exerciseDays,
  });

  final int? painScore;
  final int loggedToday;
  final int exerciseDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KneedleTheme.space5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KneedleTheme.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F6F4), Color(0xFFE4EFEC)],
        ),
        boxShadow: KneedleTheme.shadowSoft,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: KneedleTheme.sageDeep,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      painScore == null
                          ? 'How is your knee?'
                          : 'Knee feels ${_descriptor(painScore!)}',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: KneedleTheme.sageDeep,
                              ),
                    ),
                    const SizedBox(height: KneedleTheme.space2),
                    Text(
                      painScore == null
                          ? 'Tap the mic on the Journal tab to log how you feel.'
                          : 'Last logged just now. Keep listening to your body.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KneedleTheme.space3),
              KPainDial(score: painScore, size: 116),
            ],
          ),
          const SizedBox(height: KneedleTheme.space5),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Logged today',
                  value: '$loggedToday',
                  icon: Icons.edit_note_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: KneedleTheme.sageDeep.withValues(alpha: 0.12),
              ),
              Expanded(
                child: _Stat(
                  label: 'Exercise streak',
                  value: exerciseDays == 0 ? '—' : '${exerciseDays}d',
                  icon: Icons.local_fire_department_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _descriptor(int s) {
    if (s <= 2) return 'great';
    if (s <= 4) return 'okay';
    if (s <= 6) return 'sore';
    if (s <= 8) return 'tough';
    return 'rough';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: KneedleTheme.sageDeep, size: 18),
        const SizedBox(width: KneedleTheme.space2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KneedleTheme.sageDeep,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: KneedleTheme.sageDeep.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.accentSoft,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color accentSoft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KCard(
      onTap: onTap,
      padding: const EdgeInsets.all(KneedleTheme.space5),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accentSoft,
              borderRadius: BorderRadius.circular(KneedleTheme.radiusMd),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(width: KneedleTheme.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: KneedleTheme.cream,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: KneedleTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final KCardTone tone;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KCard(
      tone: tone,
      onTap: onTap,
      padding: const EdgeInsets.all(KneedleTheme.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(KneedleTheme.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: KneedleTheme.space3),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: KneedleTheme.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LastGaitCard extends StatelessWidget {
  const _LastGaitCard({required this.session});
  final GaitSession session;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d · h:mm a');
    final sev = session.severity.toLowerCase();
    final (chipBg, chipFg) = switch (sev) {
      'severe' => (KneedleTheme.dangerTint, KneedleTheme.danger),
      'moderate' => (KneedleTheme.amberTint, const Color(0xFF8E5B0A)),
      _ => (KneedleTheme.successTint, KneedleTheme.success),
    };

    return KCard(
      onTap: () => openSavedGaitReport(context, session),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  session.severity.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: chipFg,
                  ),
                ),
              ),
              const SizedBox(width: KneedleTheme.space2),
              Text(
                'KL ${session.klGrade}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KneedleTheme.inkMuted,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                df.format(session.timestamp),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: KneedleTheme.space4),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Symmetry',
                  value: session.symmetryScore == null
                      ? '—'
                      : session.symmetryScore!.toStringAsFixed(0),
                  suffix: '/100',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Cadence',
                  value: session.cadence == null
                      ? '—'
                      : session.cadence!.toStringAsFixed(0),
                  suffix: 'spm',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Speed',
                  value: session.gaitSpeedProxy.toStringAsFixed(1),
                  suffix: '·',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, required this.suffix});
  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KneedleTheme.ink,
              letterSpacing: -0.5,
            ),
            children: [
              TextSpan(text: value),
              TextSpan(
                text: ' $suffix',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KneedleTheme.inkMuted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Push the full result screen for a previously-saved session by
/// rehydrating its persisted JSON. If the session predates the
/// `analysisJson` field (older saves) we surface a snackbar explaining
/// that only summary data is available; we deliberately don't open a
/// half-empty result screen because it would look broken.
Future<void> openSavedGaitReport(
  BuildContext context,
  GaitSession session,
) async {
  final raw = session.analysisJson;
  final rehydrated =
      raw == null ? null : AnalysisResponse.fromStoredJson(raw);
  if (rehydrated == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This session was saved before reports were stored — '
          'run a new gait check to see the full report.',
        ),
      ),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GaitResultScreen(response: rehydrated, lang: 'en'),
    ),
  );
}

bool _isToday(DateTime ts) {
  final now = DateTime.now();
  return ts.year == now.year && ts.month == now.month && ts.day == now.day;
}

int _streakDays(Iterable<DateTime> times) {
  final days = <DateTime>{
    for (final t in times) DateTime(t.year, t.month, t.day),
  };
  var streak = 0;
  var cursor = DateTime.now();
  cursor = DateTime(cursor.year, cursor.month, cursor.day);
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

