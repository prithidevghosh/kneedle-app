import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/exercise_session.dart';
import '../models/gait_session.dart';
import '../models/pain_entry.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pain = ref.watch(painEntriesProvider);
    final gait = ref.watch(gaitSessionsProvider);
    final ex = ref.watch(exerciseSessionsProvider);

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(title: const Text('Insights')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KneedleTheme.space5,
                KneedleTheme.space2,
                KneedleTheme.space5,
                KneedleTheme.space4,
              ),
              child: KSegmented(
                options: const ['Pain', 'Gait', 'Exercise'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: _bodyFor(_tab, pain, gait, ex),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyFor(
    int tab,
    List<PainEntry> pain,
    List<GaitSession> gait,
    List<ExerciseSession> ex,
  ) {
    final df = DateFormat('MMM d · h:mm a');
    final dfShort = DateFormat('MMM d');

    if (tab == 0) {
      if (pain.isEmpty) {
        return const KEmptyState(
          icon: Icons.bubble_chart_outlined,
          title: 'No pain entries yet',
          message: 'Log a pain score to see your trend appear here.',
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          KneedleTheme.space5,
          0,
          KneedleTheme.space5,
          KneedleTheme.space7,
        ),
        physics: const BouncingScrollPhysics(),
        children: [
          _PainTrendCard(entries: pain),
          const SizedBox(height: KneedleTheme.space5),
          for (final e in pain) ...[
            _PainRow(entry: e, df: df),
            const SizedBox(height: KneedleTheme.space2),
          ],
        ],
      );
    }

    if (tab == 1) {
      if (gait.isEmpty) {
        return const KEmptyState(
          icon: Icons.directions_walk_rounded,
          title: 'No gait sessions yet',
          message: 'Run your first 8-second walk to see analysis here.',
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          KneedleTheme.space5,
          0,
          KneedleTheme.space5,
          KneedleTheme.space7,
        ),
        physics: const BouncingScrollPhysics(),
        children: [
          for (final g in gait) ...[
            _GaitRow(session: g, df: dfShort),
            const SizedBox(height: KneedleTheme.space3),
          ],
        ],
      );
    }

    if (ex.isEmpty) {
      return const KEmptyState(
        icon: Icons.self_improvement_rounded,
        title: 'No exercise sessions yet',
        message: 'Reps and duration from the coach will appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KneedleTheme.space5,
        0,
        KneedleTheme.space5,
        KneedleTheme.space7,
      ),
      physics: const BouncingScrollPhysics(),
      children: [
        for (final s in ex) ...[
          _ExerciseRow(session: s, df: dfShort),
          const SizedBox(height: KneedleTheme.space3),
        ],
      ],
    );
  }
}

class _PainTrendCard extends StatelessWidget {
  const _PainTrendCard({required this.entries});
  final List<PainEntry> entries;

  @override
  Widget build(BuildContext context) {
    final last14 = entries.take(14).toList().reversed.toList();
    const maxScore = 10;
    final avg = last14.isEmpty
        ? 0.0
        : last14.map((e) => e.painScore).reduce((a, b) => a + b) /
            last14.length;

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LAST 14 ENTRIES',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text('Average',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  color: KneedleTheme.ink,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '/10',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KneedleTheme.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KneedleTheme.space4),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in last14) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FractionallySizedBox(
                        heightFactor:
                            (e.painScore / maxScore).clamp(0.06, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                KneedleTheme.coral,
                                KneedleTheme.sage,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PainRow extends StatelessWidget {
  const _PainRow({required this.entry, required this.df});
  final PainEntry entry;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final s = entry.painScore;
    final fg = s <= 3
        ? KneedleTheme.success
        : s <= 6
            ? KneedleTheme.amber
            : KneedleTheme.coral;

    return KCard(
      padding: const EdgeInsets.symmetric(
        horizontal: KneedleTheme.space4,
        vertical: KneedleTheme.space3,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: KneedleTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pain $s/10',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(df.format(entry.timestamp),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (entry.context.isNotEmpty && entry.context != 'manual entry')
            Expanded(
              child: Text(
                entry.context,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: KneedleTheme.inkMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GaitRow extends StatelessWidget {
  const _GaitRow({required this.session, required this.df});
  final GaitSession session;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final sev = session.severity.toLowerCase();
    final (bg, fg) = switch (sev) {
      'severe' => (KneedleTheme.dangerTint, KneedleTheme.danger),
      'moderate' => (KneedleTheme.amberTint, const Color(0xFF8E5B0A)),
      _ => (KneedleTheme.successTint, KneedleTheme.success),
    };

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  session.severity.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: fg,
                  ),
                ),
              ),
              const Spacer(),
              Text('KL ${session.klGrade}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KneedleTheme.inkMuted)),
              const SizedBox(width: KneedleTheme.space2),
              Text(df.format(session.timestamp),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: KneedleTheme.space3),
          Row(
            children: [
              _Mini(
                  label: 'Symmetry',
                  value:
                      session.symmetryScore?.toStringAsFixed(0) ?? '—'),
              _Mini(
                  label: 'Cadence',
                  value: session.cadence?.toStringAsFixed(0) ?? '—'),
              _Mini(
                  label: 'Speed',
                  value: session.gaitSpeedProxy.toStringAsFixed(1)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.session, required this.df});
  final ExerciseSession session;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final mins = session.durationSec ~/ 60;
    final secs = session.durationSec % 60;
    return KCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: KneedleTheme.amberTint,
              borderRadius: BorderRadius.circular(KneedleTheme.radiusSm),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.self_improvement_rounded,
                color: KneedleTheme.amber, size: 22),
          ),
          const SizedBox(width: KneedleTheme.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.exerciseName,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${session.repsCompleted} reps · ${mins}m ${secs}s · ${df.format(session.timestamp)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KneedleTheme.ink,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}
