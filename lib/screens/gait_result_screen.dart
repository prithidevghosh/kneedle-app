import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/analysis_response.dart';
import '../models/gait_session.dart';
import '../models/pain_entry.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';
import 'doctor_report_screen.dart';

class GaitResultScreen extends ConsumerWidget {
  const GaitResultScreen({super.key, required this.response});
  final AnalysisResponse response;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sev = response.severity.toLowerCase();
    final (gradFrom, gradTo, accent) = switch (sev) {
      'severe' => (
          const Color(0xFFF7E5DC),
          const Color(0xFFEFC9B7),
          KneedleTheme.danger,
        ),
      'moderate' => (
          const Color(0xFFF8EBCE),
          const Color(0xFFEFD9A8),
          const Color(0xFF8E5B0A),
        ),
      _ => (
          const Color(0xFFDDEDE3),
          const Color(0xFFB9DACA),
          KneedleTheme.success,
        ),
    };

    final m = response.metrics;
    final sessions = ref.watch(gaitSessionsProvider);
    final painEntries = ref.watch(painEntriesProvider);

    final flagMessages = _translateFlags(response.clinicalFlags);

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(title: const Text('Gait result')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KneedleTheme.space5,
            KneedleTheme.space2,
            KneedleTheme.space5,
            KneedleTheme.space7,
          ),
          physics: const BouncingScrollPhysics(),
          children: [
            // ── HERO: severity + KL/Symmetry pills + body silhouette ──────
            Container(
              padding: const EdgeInsets.all(KneedleTheme.space5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(KneedleTheme.radiusXl),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [gradFrom, gradTo],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GAIT SEVERITY',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: accent),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _titleCase(response.severity),
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.2,
                            color: accent,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: KneedleTheme.space4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Pill(
                              label: 'KL ${response.klProxyGrade}',
                              accent: accent,
                            ),
                            _Pill(
                              label:
                                  'Symmetry ${response.symmetryScore.toStringAsFixed(0)}/100',
                              accent: accent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KneedleTheme.space3),
                  SizedBox(
                    width: 72,
                    height: 110,
                    child: CustomPaint(
                      painter: _BodyDiagramPainter(
                        activeJoint: response.activeJoint,
                        accent: accent,
                        muted: accent.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── #1 EMPATHY LINE ────────────────────────────────────────
            if (response.empathyLine.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space4),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KneedleTheme.space2,
                ),
                child: Text(
                  response.empathyLine,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                    color: KneedleTheme.inkMuted,
                  ),
                ),
              ),
            ],

            // ── OBSERVATION (existing) ─────────────────────────────────
            const SizedBox(height: KneedleTheme.space4),
            KCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OBSERVATION',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    response.observation,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),

            // ── #2 SYMMETRY MEANING ────────────────────────────────────
            if (response.symmetryMeaning.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space3),
              KCard(
                tone: KCardTone.sage,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.balance_rounded,
                      color: KneedleTheme.sageDeep,
                      size: 22,
                    ),
                    const SizedBox(width: KneedleTheme.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Symmetry — ${_titleCase(response.symmetryBand)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: KneedleTheme.sageDeep),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            response.symmetryMeaning,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: KneedleTheme.sageDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── #8 TREND SPARKLINE ─────────────────────────────────────
            if (sessions.length >= 2) ...[
              const SizedBox(height: KneedleTheme.space4),
              _TrendCard(sessions: sessions, accent: accent),
            ],

            // ── #10 PAIN CORRELATION ───────────────────────────────────
            if (painEntries.isNotEmpty) ...[
              () {
                final card = _buildPainCorrelationCard(context, painEntries);
                if (card == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: KneedleTheme.space3),
                  child: card,
                );
              }(),
            ],

            // ── #5 METRIC GRID ─────────────────────────────────────────
            const SizedBox(height: KneedleTheme.space6),
            const KSectionTitle(
              eyebrow: 'Today',
              title: 'Your numbers',
            ),
            const SizedBox(height: KneedleTheme.space4),
            _MetricGrid(metrics: m),

            // ── #7 CLINICAL FLAGS ──────────────────────────────────────
            if (flagMessages.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space4),
              KCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WHAT WE NOTICED',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: KneedleTheme.space2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final msg in flagMessages)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: KneedleTheme.creamWarm,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: KneedleTheme.hairline,
                              ),
                            ),
                            child: Text(
                              msg,
                              style: const TextStyle(
                                fontSize: 13,
                                color: KneedleTheme.ink,
                                height: 1.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // ── TODAY'S FIX (existing) + #3 FREQUENCY ───────────────────
            if (response.fixTitle.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space4),
              KCard(
                tone: KCardTone.sage,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "TODAY'S FIX",
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: KneedleTheme.sageDeep,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      response.fixTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: KneedleTheme.sageDeep),
                    ),
                    const SizedBox(height: KneedleTheme.space2),
                    Text(
                      response.fixDesc,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: KneedleTheme.sageDeep,
                      ),
                    ),
                    if (response.frequency.isNotEmpty) ...[
                      const SizedBox(height: KneedleTheme.space3),
                      Row(
                        children: [
                          const Icon(
                            Icons.event_repeat_rounded,
                            size: 18,
                            color: KneedleTheme.sageDeep,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              response.frequency,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: KneedleTheme.sageDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // ── EXERCISES (existing) ────────────────────────────────────
            if (response.exercises.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space6),
              const KSectionTitle(eyebrow: 'Today', title: 'Exercises'),
              const SizedBox(height: KneedleTheme.space4),
              for (final ex in response.exercises) ...[
                KCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: KneedleTheme.amberTint,
                          borderRadius:
                              BorderRadius.circular(KneedleTheme.radiusSm),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.fitness_center_rounded,
                          color: KneedleTheme.amber,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: KneedleTheme.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ex.def.name,
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            if (ex.def.repsEn.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(ex.def.repsEn,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall),
                            ],
                            if (ex.reason.isNotEmpty) ...[
                              const SizedBox(height: KneedleTheme.space2),
                              Text(ex.reason,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: KneedleTheme.ink)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KneedleTheme.space2),
              ],
            ],

            // ── #4 COMPLEMENTARY ACTIONS ────────────────────────────────
            if (response.complementaryActions.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space4),
              KCard(
                tone: KCardTone.amber,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.local_florist_outlined,
                      color: Color(0xFF8E5B0A),
                      size: 22,
                    ),
                    const SizedBox(width: KneedleTheme.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Daily habits',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8E5B0A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            response.complementaryActions,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Color(0xFF5C3F0F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── PAIN RULE (existing) ────────────────────────────────────
            if (response.painRule.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space4),
              KCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined,
                        color: KneedleTheme.sageDeep, size: 22),
                    const SizedBox(width: KneedleTheme.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pain rule',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(response.painRule,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── RED FLAGS (existing) ────────────────────────────────────
            if (response.redFlags.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space3),
              KCard(
                tone: KCardTone.danger,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: KneedleTheme.danger, size: 22),
                    const SizedBox(width: KneedleTheme.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('See a clinician',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: KneedleTheme.danger)),
                          const SizedBox(height: 2),
                          Text(response.redFlags,
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Color(0xFF5F1F12))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── REFERRAL (existing) ─────────────────────────────────────
            if (response.referralRecommended &&
                response.referralText.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space3),
              KCard(
                tone: KCardTone.amber,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.local_hospital_outlined,
                        color: Color(0xFF8E5B0A), size: 22),
                    const SizedBox(width: KneedleTheme.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Referral recommended',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8E5B0A))),
                          const SizedBox(height: 2),
                          Text(response.referralText,
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Color(0xFF5C3F0F))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── #9 SHARE WITH DOCTOR CTA ───────────────────────────────
            const SizedBox(height: KneedleTheme.space5),
            _ShareWithDoctorButton(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DoctorReportScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildPainCorrelationCard(
    BuildContext context,
    List<PainEntry> entries,
  ) {
    final now = DateTime.now();
    final recent = entries
        .where((e) => now.difference(e.timestamp).inDays <= 14)
        .toList();
    if (recent.isEmpty) return null;

    final avg = recent.map((e) => e.painScore).reduce((a, b) => a + b) /
        recent.length;

    String trendText;
    IconData trendIcon;
    Color trendColor;

    if (recent.length >= 2) {
      final sorted = [...recent]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final firstHalf = sorted.take(sorted.length ~/ 2 == 0 ? 1 : sorted.length ~/ 2);
      final secondHalf = sorted.skip(sorted.length ~/ 2);
      final firstAvg = firstHalf.isEmpty
          ? avg
          : firstHalf.map((e) => e.painScore).reduce((a, b) => a + b) /
              firstHalf.length;
      final secondAvg = secondHalf.isEmpty
          ? avg
          : secondHalf.map((e) => e.painScore).reduce((a, b) => a + b) /
              secondHalf.length;
      final delta = secondAvg - firstAvg;
      if (delta <= -1) {
        trendText = 'Pain trending down — keep going.';
        trendIcon = Icons.trending_down_rounded;
        trendColor = KneedleTheme.success;
      } else if (delta >= 1) {
        trendText = 'Pain trending up. Consider gentler exercises today.';
        trendIcon = Icons.trending_up_rounded;
        trendColor = KneedleTheme.danger;
      } else {
        trendText = 'Pain steady over the last 2 weeks.';
        trendIcon = Icons.trending_flat_rounded;
        trendColor = KneedleTheme.inkMuted;
      }
    } else {
      trendText = 'Log a few more entries to see your pain trend.';
      trendIcon = Icons.trending_flat_rounded;
      trendColor = KneedleTheme.inkMuted;
    }

    return KCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(trendIcon, color: trendColor, size: 22),
          const SizedBox(width: KneedleTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pain · ${avg.toStringAsFixed(1)}/10 avg (last 14 days)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  trendText,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: KneedleTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Maps internal clinical-flag identifiers to plain-language patient copy.
/// Unknown flags are dropped so we never show raw snake_case to the patient.
const _flagLabels = <String, String>{
  'bilateral_oa_pattern':
      'Both knees showing similar wear patterns',
  'fppa_deviation':
      'Knees track slightly inward when stepping',
  'mild_static_varus_valgus_deformity':
      'Slight knee alignment drift in standing posture',
  'moderate_static_varus_valgus_deformity':
      'Noticeable knee alignment drift in standing posture',
  'severe_static_varus_valgus_deformity':
      'Significant knee alignment drift — talk to a clinician',
  'mild_varus_valgus_thrust':
      'Small side-to-side knee shift during walking',
  'significant_varus_valgus_thrust':
      'Noticeable side-to-side knee shift during walking',
  'trendelenburg_positive':
      'Hip dip during single-leg stance — hip stability work helps',
  'significant_trunk_lean':
      'Upper body leans to one side while walking',
  'high_double_support':
      'Spending more time on both feet — likely guarding the knee',
  'elevated_double_support':
      'Slightly cautious stepping pattern',
  'high_stride_asymmetry':
      'Steps timing differs between legs',
  'low_cadence':
      'Walking pace is on the slow side',
  'reduced_hip_extension':
      'Hip not extending fully at the end of each step',
  'reduced_ankle_dorsiflexion':
      'Ankle bend at the front of the step is reduced',
  'right_loading_response_absent':
      'Right knee not bending to absorb impact',
  'right_loading_response_reduced':
      'Right knee impact-absorption is reduced',
  'left_loading_response_absent':
      'Left knee not bending to absorb impact',
  'left_loading_response_reduced':
      'Left knee impact-absorption is reduced',
  'right_swing_flexion_severe':
      'Right knee not bending enough in the swing phase',
  'right_swing_flexion_reduced':
      'Right knee swing-phase bend is reduced',
  'left_swing_flexion_severe':
      'Left knee not bending enough in the swing phase',
  'left_swing_flexion_reduced':
      'Left knee swing-phase bend is reduced',
  'right_flexion_contracture':
      'Right knee not straightening fully',
  'left_flexion_contracture':
      'Left knee not straightening fully',
};

List<String> _translateFlags(List<String> flags) {
  final out = <String>[];
  for (final f in flags) {
    final m = _flagLabels[f];
    if (m != null) out.add(m);
  }
  return out;
}

// ───────────────────────────────────────────────────────────────────────
// Metric grid
// ───────────────────────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final dynamic metrics; // GaitMetrics — kept dynamic to avoid extra import

  @override
  Widget build(BuildContext context) {
    final tiles = <_MetricTileData>[];

    // Knee bend — right
    final kR = metrics.kneeAngleRight as double?;
    if (kR != null) {
      tiles.add(_MetricTileData(
        label: 'Right knee bend',
        value: '${kR.toStringAsFixed(1)}°',
        normal: 'Full bend ~130° for stairs',
        status: _bendStatus(kR),
      ));
    }
    // Knee bend — left
    final kL = metrics.kneeAngleLeft as double?;
    if (kL != null) {
      tiles.add(_MetricTileData(
        label: 'Left knee bend',
        value: '${kL.toStringAsFixed(1)}°',
        normal: 'Full bend ~130° for stairs',
        status: _bendStatus(kL),
      ));
    }
    // Symmetry
    final sym = metrics.symmetryScore as double?;
    if (sym != null) {
      tiles.add(_MetricTileData(
        label: 'Symmetry',
        value: '${sym.toStringAsFixed(0)}/100',
        normal: 'Normal > 80',
        status: sym >= 80
            ? _Status.good
            : (sym >= 65 ? _Status.watch : _Status.concern),
      ));
    }
    // Cadence
    final cad = metrics.cadence as double?;
    if (cad != null) {
      tiles.add(_MetricTileData(
        label: 'Walking pace',
        value: '${cad.toStringAsFixed(0)} spm',
        normal: 'Comfortable 100–120 spm',
        status: (cad >= 100 && cad <= 125)
            ? _Status.good
            : (cad >= 80 ? _Status.watch : _Status.concern),
      ));
    }
    // Trunk lean
    final lean = metrics.trunkLeanAngle as double?;
    if (lean != null) {
      final dir = metrics.trunkLeanDirection as String? ?? 'neutral';
      tiles.add(_MetricTileData(
        label: 'Trunk lean',
        value: '${lean.toStringAsFixed(1)}° $dir',
        normal: 'Normal < 6°',
        status: lean < 6 ? _Status.good : (lean < 10 ? _Status.watch : _Status.concern),
      ));
    }
    // Toe-out
    final tR = metrics.toeOutAngleRight as double?;
    final tL = metrics.toeOutAngleLeft as double?;
    if (tR != null || tL != null) {
      final parts = <String>[];
      if (tR != null) parts.add('R ${tR.toStringAsFixed(1)}°');
      if (tL != null) parts.add('L ${tL.toStringAsFixed(1)}°');
      final avg = ((tR?.abs() ?? 0) + (tL?.abs() ?? 0)) /
          ((tR != null ? 1 : 0) + (tL != null ? 1 : 0));
      tiles.add(_MetricTileData(
        label: 'Toe-out',
        value: parts.join(' · '),
        normal: 'Healthy 5–10°',
        status: (avg >= 5 && avg <= 12)
            ? _Status.good
            : (avg >= 3 ? _Status.watch : _Status.concern),
      ));
    }

    if (tiles.isEmpty) {
      return KCard(
        child: Text(
          'Not enough usable frames for detailed numbers this session.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth > 360;
        final crossAxisCount = twoCol ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: KneedleTheme.space3,
            crossAxisSpacing: KneedleTheme.space3,
            mainAxisExtent: 118,
          ),
          itemBuilder: (_, i) => _MetricTile(data: tiles[i]),
        );
      },
    );
  }

  _Status _bendStatus(double v) {
    // Walking knee flexion peak is typically 15-25° in early stance.
    if (v < 5) return _Status.concern;
    if (v < 10) return _Status.watch;
    return _Status.good;
  }
}

enum _Status { good, watch, concern }

class _MetricTileData {
  const _MetricTileData({
    required this.label,
    required this.value,
    required this.normal,
    required this.status,
  });
  final String label;
  final String value;
  final String normal;
  final _Status status;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});
  final _MetricTileData data;

  @override
  Widget build(BuildContext context) {
    final (dot, bg) = switch (data.status) {
      _Status.good => (KneedleTheme.success, KneedleTheme.successTint),
      _Status.watch => (KneedleTheme.amber, KneedleTheme.amberTint),
      _Status.concern => (KneedleTheme.danger, KneedleTheme.dangerTint),
    };
    return Container(
      padding: const EdgeInsets.all(KneedleTheme.space3),
      decoration: BoxDecoration(
        color: KneedleTheme.surface,
        borderRadius: BorderRadius.circular(KneedleTheme.radiusMd),
        border: Border.all(color: KneedleTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KneedleTheme.inkMuted,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            data.value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KneedleTheme.ink,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              data.normal,
              style: const TextStyle(
                fontSize: 11,
                color: KneedleTheme.ink,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
// Trend sparkline (#8)
// ───────────────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.sessions, required this.accent});
  final List<GaitSession> sessions;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final sorted = [...sessions]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final recent = sorted.length <= 7
        ? sorted
        : sorted.sublist(sorted.length - 7);
    final scores = recent
        .map((s) => s.symmetryScore)
        .where((v) => v != null)
        .cast<double>()
        .toList();
    if (scores.length < 2) return const SizedBox.shrink();

    final last = scores.last;
    final prev = scores[scores.length - 2];
    final delta = last - prev;
    String trendText;
    IconData trendIcon;
    Color trendColor;
    if (delta >= 2) {
      trendText = 'Symmetry up ${delta.toStringAsFixed(0)} from last session';
      trendIcon = Icons.trending_up_rounded;
      trendColor = KneedleTheme.success;
    } else if (delta <= -2) {
      trendText =
          'Symmetry down ${delta.abs().toStringAsFixed(0)} from last session';
      trendIcon = Icons.trending_down_rounded;
      trendColor = KneedleTheme.danger;
    } else {
      trendText = 'Symmetry steady over recent sessions';
      trendIcon = Icons.trending_flat_rounded;
      trendColor = KneedleTheme.inkMuted;
    }

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(trendIcon, color: trendColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trendText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${scores.length} sessions',
                style: const TextStyle(
                  fontSize: 12,
                  color: KneedleTheme.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: KneedleTheme.space3),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(values: scores, accent: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.accent});
  final List<double> values;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final range = (hi - lo).clamp(1.0, double.infinity);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - lo) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final line = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);

    final dot = Paint()..color = accent;
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - lo) / range) * size.height;
      canvas.drawCircle(Offset(x, y), i == values.length - 1 ? 4.0 : 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.accent != accent;
}

// ───────────────────────────────────────────────────────────────────────
// Body silhouette (#6)
// ───────────────────────────────────────────────────────────────────────

class _BodyDiagramPainter extends CustomPainter {
  _BodyDiagramPainter({
    required this.activeJoint,
    required this.accent,
    required this.muted,
  });
  final String activeJoint;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final stroke = Paint()
      ..color = muted
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Head
    canvas.drawCircle(Offset(cx, h * 0.10), w * 0.10, stroke);
    // Torso
    canvas.drawLine(
      Offset(cx, h * 0.20),
      Offset(cx, h * 0.50),
      stroke,
    );
    // Hips (the line between hip joints)
    final hipY = h * 0.50;
    final hipL = Offset(cx - w * 0.18, hipY);
    final hipR = Offset(cx + w * 0.18, hipY);
    canvas.drawLine(hipL, hipR, stroke);
    // Knees
    final kneeY = h * 0.72;
    final kneeL = Offset(cx - w * 0.18, kneeY);
    final kneeR = Offset(cx + w * 0.18, kneeY);
    canvas.drawLine(hipL, kneeL, stroke);
    canvas.drawLine(hipR, kneeR, stroke);
    // Ankles
    final ankleY = h * 0.94;
    final ankleL = Offset(cx - w * 0.18, ankleY);
    final ankleR = Offset(cx + w * 0.18, ankleY);
    canvas.drawLine(kneeL, ankleL, stroke);
    canvas.drawLine(kneeR, ankleR, stroke);
    // Arms (decorative)
    canvas.drawLine(
      Offset(cx, h * 0.25),
      Offset(cx - w * 0.22, h * 0.45),
      stroke,
    );
    canvas.drawLine(
      Offset(cx, h * 0.25),
      Offset(cx + w * 0.22, h * 0.45),
      stroke,
    );

    // Highlight joint
    void highlight(Offset p) {
      final glow = Paint()
        ..color = accent.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      final dot = Paint()
        ..color = accent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 9, glow);
      canvas.drawCircle(p, 5, dot);
    }

    switch (activeJoint) {
      case 'right_knee':
        highlight(kneeR);
        break;
      case 'left_knee':
        highlight(kneeL);
        break;
      case 'hips':
        highlight(hipL);
        highlight(hipR);
        break;
      case 'ankles':
        highlight(ankleL);
        highlight(ankleR);
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BodyDiagramPainter old) =>
      old.activeJoint != activeJoint || old.accent != accent;
}

// ───────────────────────────────────────────────────────────────────────
// Share-with-doctor CTA (#9)
// ───────────────────────────────────────────────────────────────────────

class _ShareWithDoctorButton extends StatelessWidget {
  const _ShareWithDoctorButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KneedleTheme.ink,
      borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: KneedleTheme.space5,
            vertical: KneedleTheme.space4,
          ),
          child: Row(
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                color: KneedleTheme.cream,
                size: 22,
              ),
              SizedBox(width: KneedleTheme.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share with your doctor',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: KneedleTheme.cream,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Build a PDF with gait + pain history',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD4CFC0),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: KneedleTheme.cream,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: accent,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
