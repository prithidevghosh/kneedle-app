import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../models/pain_entry.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';
import '../widgets/widgets.dart';

class PainJournalScreen extends ConsumerStatefulWidget {
  const PainJournalScreen({super.key});

  @override
  ConsumerState<PainJournalScreen> createState() => _PainJournalScreenState();
}

class _PainJournalScreenState extends ConsumerState<PainJournalScreen> {
  bool _busy = false;
  String _heading = 'How is your knee right now?';
  String _detail = 'Tap the mic and speak — Gemma will log it on-device.';
  String? _lastTranscript;
  String? _lastReply;

  Future<void> _record() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() {
        _heading = 'Microphone needed';
        _detail = 'Allow microphone access in Settings to log by voice.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _heading = 'Listening…';
      _detail = 'Describe your pain in your own words.';
      _lastTranscript = null;
      _lastReply = null;
    });
    try {
      final turn = await ref.read(voiceServiceProvider).captureJournalEntry();
      bumpData(ref);
      setState(() {
        if (turn.transcript.isEmpty) {
          _heading = "Didn't catch that";
          _detail = 'Try again in a quieter spot.';
        } else {
          _heading = 'Logged';
          _detail = 'Saved on-device. Trends update on the Insights tab.';
          _lastTranscript = turn.transcript;
          _lastReply = turn.reply;
        }
      });
    } catch (e) {
      setState(() {
        _heading = 'Voice error';
        _detail = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(painEntriesProvider);
    final df = DateFormat('MMM d · h:mm a');

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(
        title: const Text('Pain journal'),
        actions: [
          IconButton(
            tooltip: 'Manual entry',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _manualEntry,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KneedleTheme.space5,
            KneedleTheme.space2,
            KneedleTheme.space5,
            KneedleTheme.space8,
          ),
          physics: const BouncingScrollPhysics(),
          children: [
            const SizedBox(height: KneedleTheme.space5),
            Center(
              child: KMicButton(
                state: _busy ? KMicState.processing : KMicState.idle,
                onTap: _busy ? () {} : _record,
              ),
            ),
            const SizedBox(height: KneedleTheme.space6),
            Text(
              _heading,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: KneedleTheme.space2),
            Text(
              _detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_lastTranscript != null) ...[
              const SizedBox(height: KneedleTheme.space5),
              KCard(
                tone: KCardTone.sage,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOU SAID',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: KneedleTheme.sageDeep,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"$_lastTranscript"',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: KneedleTheme.sageDeep,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (_lastReply != null && _lastReply!.isNotEmpty) ...[
                      const SizedBox(height: KneedleTheme.space3),
                      const Divider(color: Color(0x33FFFFFF), height: 1),
                      const SizedBox(height: KneedleTheme.space3),
                      Text(
                        'KNEEDLE',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: KneedleTheme.sageDeep,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _lastReply!,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: KneedleTheme.sageDeep,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: KneedleTheme.space7),
            const KSectionTitle(eyebrow: 'Journal', title: 'Recent entries'),
            const SizedBox(height: KneedleTheme.space4),
            if (entries.isEmpty)
              const KEmptyState(
                icon: Icons.history_rounded,
                title: 'No entries yet',
                message:
                    'Your first voice or manual log will appear here.',
              )
            else
              for (final e in entries) ...[
                _EntryCard(entry: e, df: df, onDelete: () => _delete(e)),
                const SizedBox(height: KneedleTheme.space3),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _delete(PainEntry e) async {
    await StorageService.painEntries.delete(e.id);
    bumpData(ref);
  }

  Future<void> _manualEntry() async {
    final score = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PainScoreSheet(),
    );
    if (score == null) return;
    final now = DateTime.now();
    await StorageService.savePainEntry(PainEntry(
      id: now.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff,
      painScore: score,
      location: 'unspecified',
      context: 'manual entry',
      timestamp: now,
    ));
    bumpData(ref);
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.df,
    required this.onDelete,
  });

  final PainEntry entry;
  final DateFormat df;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = entry.painScore;
    final (bg, fg) = s <= 3
        ? (KneedleTheme.successTint, KneedleTheme.success)
        : s <= 6
            ? (KneedleTheme.amberTint, const Color(0xFF8E5B0A))
            : (KneedleTheme.coralTint, KneedleTheme.coral);

    return KCard(
      padding: const EdgeInsets.fromLTRB(
        KneedleTheme.space4,
        KneedleTheme.space4,
        KneedleTheme.space3,
        KneedleTheme.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(KneedleTheme.radiusMd),
            ),
            alignment: Alignment.center,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  letterSpacing: -0.6,
                  height: 1,
                ),
                children: [
                  TextSpan(text: '$s'),
                  TextSpan(
                    text: '/10',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: fg.withValues(alpha: 0.7),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: KneedleTheme.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.location == 'unspecified'
                      ? 'Knee'
                      : _titleCase(entry.location),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(df.format(entry.timestamp),
                    style: Theme.of(context).textTheme.bodySmall),
                if (entry.context.isNotEmpty &&
                    entry.context != 'manual entry') ...[
                  const SizedBox(height: KneedleTheme.space2),
                  Text(
                    entry.context,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: KneedleTheme.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            iconSize: 20,
            color: KneedleTheme.inkFaint,
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _PainScoreSheet extends StatefulWidget {
  const _PainScoreSheet();
  @override
  State<_PainScoreSheet> createState() => _PainScoreSheetState();
}

class _PainScoreSheetState extends State<_PainScoreSheet> {
  int _value = 4;

  Color _colorFor(int s) {
    if (s <= 3) return KneedleTheme.success;
    if (s <= 6) return KneedleTheme.amber;
    return KneedleTheme.coral;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KneedleTheme.space5,
        KneedleTheme.space4,
        KneedleTheme.space5,
        KneedleTheme.space5 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How bad is the pain?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '0 = none · 10 = worst imaginable',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: KneedleTheme.space6),
          Center(
            child: Text(
              '$_value',
              style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w700,
                letterSpacing: -3,
                color: _colorFor(_value),
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: KneedleTheme.space5),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _colorFor(_value),
              inactiveTrackColor: KneedleTheme.hairlineSoft,
              thumbColor: Colors.white,
              overlayColor: _colorFor(_value).withValues(alpha: 0.15),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 14,
                elevation: 4,
              ),
            ),
            child: Slider(
              value: _value.toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              onChanged: (v) => setState(() => _value = v.round()),
            ),
          ),
          const SizedBox(height: KneedleTheme.space5),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_value),
            child: const Text('Log this'),
          ),
          const SizedBox(height: KneedleTheme.space2),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
