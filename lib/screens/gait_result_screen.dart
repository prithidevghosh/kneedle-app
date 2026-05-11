import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/analysis_response.dart';
import '../widgets/widgets.dart';

class GaitResultScreen extends StatelessWidget {
  const GaitResultScreen({super.key, required this.response});
  final AnalysisResponse response;

  @override
  Widget build(BuildContext context) {
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
                      _Pill(label: 'KL ${response.klProxyGrade}', accent: accent),
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
            const SizedBox(height: KneedleTheme.space5),
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
                  ],
                ),
              ),
            ],
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
          ],
        ),
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
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
