import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/pdf_service.dart';
import '../widgets/widgets.dart';

class DoctorReportScreen extends ConsumerStatefulWidget {
  const DoctorReportScreen({super.key});

  @override
  ConsumerState<DoctorReportScreen> createState() =>
      _DoctorReportScreenState();
}

class _DoctorReportScreenState extends ConsumerState<DoctorReportScreen> {
  bool _busy = false;
  File? _generated;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pain = ref.read(painEntriesProvider);
      final gait = ref.read(gaitSessionsProvider);
      final ex = ref.read(exerciseSessionsProvider);
      final f = await PdfService.generate(
        painEntries: pain,
        gaitSessions: gait,
        exerciseSessions: ex,
      );
      if (!mounted) return;
      setState(() => _generated = f);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final f = _generated;
    if (f == null) return;
    await PdfService.shareReport(f);
  }

  @override
  Widget build(BuildContext context) {
    final pain = ref.watch(painEntriesProvider);
    final gait = ref.watch(gaitSessionsProvider);
    final ex = ref.watch(exerciseSessionsProvider);

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(title: const Text('Doctor report')),
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF1F6F4), Color(0xFFE4EFEC)],
                ),
                boxShadow: KneedleTheme.shadowSoft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(KneedleTheme.radiusMd),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.description_rounded,
                      color: KneedleTheme.sageDeep,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: KneedleTheme.space4),
                  Text(
                    'One-page clinical summary',
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: KneedleTheme.sageDeep,
                            ),
                  ),
                  const SizedBox(height: KneedleTheme.space2),
                  const Text(
                    'A PDF you can share with your physician or physiotherapist. Built entirely on-device — nothing leaves your phone unless you choose to share.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: KneedleTheme.sageDeep,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KneedleTheme.space6),
            const KSectionTitle(
              eyebrow: 'Included',
              title: 'What goes in the report',
            ),
            const SizedBox(height: KneedleTheme.space4),
            _IncludesRow(
              icon: Icons.bubble_chart_outlined,
              title: 'Pain log',
              count: pain.length,
              unit: 'entries',
            ),
            const SizedBox(height: KneedleTheme.space2),
            _IncludesRow(
              icon: Icons.directions_walk_rounded,
              title: 'Gait sessions',
              count: gait.length,
              unit: 'walks',
            ),
            const SizedBox(height: KneedleTheme.space2),
            _IncludesRow(
              icon: Icons.self_improvement_rounded,
              title: 'Exercise',
              count: ex.length,
              unit: 'sessions',
            ),
            const SizedBox(height: KneedleTheme.space6),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(_busy ? 'Generating…' : 'Generate PDF'),
            ),
            if (_generated != null) ...[
              const SizedBox(height: KneedleTheme.space4),
              KCard(
                tone: KCardTone.sage,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.check_rounded,
                          color: KneedleTheme.success, size: 24),
                    ),
                    const SizedBox(width: KneedleTheme.space4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Report ready',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: KneedleTheme.sageDeep),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Saved locally · tap share to send it.',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  KneedleTheme.sageDeep.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KneedleTheme.space3),
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share PDF'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: KneedleTheme.space4),
              KCard(
                tone: KCardTone.danger,
                child: Text(
                  _error!,
                  style: const TextStyle(color: KneedleTheme.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IncludesRow extends StatelessWidget {
  const _IncludesRow({
    required this.icon,
    required this.title,
    required this.count,
    required this.unit,
  });

  final IconData icon;
  final String title;
  final int count;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.symmetric(
        horizontal: KneedleTheme.space4,
        vertical: KneedleTheme.space3,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: KneedleTheme.sageTint,
              borderRadius: BorderRadius.circular(KneedleTheme.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: KneedleTheme.sageDeep, size: 20),
          ),
          const SizedBox(width: KneedleTheme.space4),
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KneedleTheme.ink,
                letterSpacing: -0.3,
              ),
              children: [
                TextSpan(text: '$count'),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
}
