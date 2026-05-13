import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../models/analysis_response.dart';
import '../providers/providers.dart';
import '../services/gemma_service.dart';
import '../services/voice_service.dart';
import '../widgets/widgets.dart';

/// Voice assistant overlaid on top of a completed gait analysis. The analysis
/// is pinned into the model's system prompt via `chatWithGaitContext`, so the
/// model can answer questions about *this patient's* severity, symmetry,
/// flags, and prescribed exercises rather than generic OA small-talk.
class GaitChatScreen extends ConsumerStatefulWidget {
  const GaitChatScreen({
    super.key,
    required this.response,
    this.lang = 'en',
  });

  final AnalysisResponse response;
  final String lang;

  @override
  ConsumerState<GaitChatScreen> createState() => _GaitChatScreenState();
}

class _GaitChatScreenState extends ConsumerState<GaitChatScreen> {
  final List<_Turn> _turns = [];
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  String? _error;
  // Persistent chat session preloaded with the gait context. Created in
  // initState (kicks off background warmup), torn down in dispose.
  GaitChatSession? _session;

  String get _localeId => switch (widget.lang) {
        'hi' => 'hi_IN',
        'bn' => 'bn_IN',
        _ => 'en_US',
      };

  List<String> get _suggestions => switch (widget.lang) {
        'hi' => const [
            'मेरा घुटना अभी कैसा है?',
            'सिमेट्री स्कोर का क्या मतलब है?',
            'मुझे कौन सा व्यायाम पहले शुरू करना चाहिए?',
            'मेरी चाल में क्या बदलाव आया है?',
          ],
        'bn' => const [
            'আমার হাঁটু এখন কেমন আছে?',
            'সিমেট্রি স্কোরের মানে কী?',
            'কোন ব্যায়াম আগে শুরু করব?',
            'আমার চলার ভঙ্গিতে কী পরিবর্তন এসেছে?',
          ],
        _ => const [
            'How is my knee right now?',
            'What does my symmetry score mean?',
            'Which exercise should I start with?',
            'What changed about how I walk?',
          ],
      };

  @override
  void initState() {
    super.initState();
    // Each visit to this screen starts a fresh conversation — don't carry
    // companion-mode chitchat into the analysis context.
    ref.read(voiceServiceProvider).resetHistory();
    // Open a long-lived chat session preloaded with the gait analysis. This
    // call kicks off a background warmup (prefill of system prompt + gait
    // context block), so by the time the user has finished reading the
    // suggestion chips and tapped the mic, the first prefill is usually
    // done. Subsequent turns reuse the KV cache and only prefill the new
    // user message — typically ~50 tokens vs ~2k for the cold path.
    _openSession();
  }

  Future<void> _openSession() async {
    try {
      final s = await ref.read(gemmaServiceProvider).openGaitChat(
            response: widget.response,
            lang: widget.lang,
          );
      if (!mounted) {
        // Screen was already torn down before the session finished setup —
        // close it immediately so the KV cache doesn't leak.
        await s.close();
        return;
      }
      setState(() => _session = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t open the assistant: $e');
    }
  }

  @override
  void dispose() {
    // Be a good citizen: stop any speech / listening that's still active when
    // the user backs out, otherwise TTS keeps talking from the previous screen.
    // Use the singleton directly — `ref.read` would throw here, since
    // Riverpod has already torn down its scope by the time dispose() runs
    // during widget tree finalization.
    VoiceService.instance.cancel();
    // Release the KV cache. Don't await — dispose() is sync.
    _session?.close();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _onMicTap() async {
    if (_busy) return;
    final session = _session;
    if (session == null) {
      setState(() => _error =
          'Still loading your report — one moment, then try again.');
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _error =
          'Microphone access is needed. Enable it in Settings and try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final voice = ref.read(voiceServiceProvider);
    try {
      final transcript = await voice.captureUtterance(localeId: _localeId);
      if (!mounted) return;
      if (transcript.isEmpty) {
        setState(() =>
            _error = 'I didn\'t catch that — try once more in a quieter spot.');
        return;
      }
      // Persistent session: only the new user message gets prefilled here,
      // not the system prompt + gait context (those are already in KV cache).
      final reply = await session.ask(transcript);
      if (!mounted) return;
      setState(() => _turns.add(_Turn(
            userText: transcript,
            assistantText: reply,
            stats: session.lastStats,
          )));
      _scrollToBottom();
      // Speak the reply but don't block the UI on it finishing — the user
      // can read the bubble immediately, and tapping the mic again will
      // cancel TTS via voice.cancel() in dispose / next capture.
      await voice.speak(reply);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Voice error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(
        title: const Text('Ask Kneedle'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                  KneedleTheme.space5,
                  KneedleTheme.space3,
                  KneedleTheme.space5,
                  KneedleTheme.space5,
                ),
                physics: const BouncingScrollPhysics(),
                children: [
                  _ContextHeader(response: widget.response),
                  const SizedBox(height: KneedleTheme.space4),
                  if (_turns.isEmpty) ...[
                    Text(
                      'Tap the mic and ask anything about your report — your '
                      'knee, your walking pattern, your exercises. I\'ll '
                      'answer using your real numbers.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: KneedleTheme.space4),
                    _SuggestionList(prompts: _suggestions),
                  ] else
                    for (final t in _turns) ...[
                      _UserBubble(text: t.userText),
                      const SizedBox(height: KneedleTheme.space2),
                      _AssistantBubble(text: t.assistantText, stats: t.stats),
                      const SizedBox(height: KneedleTheme.space4),
                    ],
                  if (_error != null) ...[
                    const SizedBox(height: KneedleTheme.space2),
                    KCard(
                      tone: KCardTone.coral,
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: KneedleTheme.danger,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KneedleTheme.space5,
                KneedleTheme.space2,
                KneedleTheme.space5,
                KneedleTheme.space5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KMicButton(
                    state: _busy ? KMicState.processing : KMicState.idle,
                    onTap: _onMicTap,
                  ),
                  const SizedBox(height: KneedleTheme.space3),
                  Text(
                    _busy
                        ? 'Thinking…'
                        : _turns.isEmpty
                            ? 'Tap to ask a question'
                            : 'Tap to ask another',
                    style: const TextStyle(
                      color: KneedleTheme.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Turn {
  const _Turn({
    required this.userText,
    required this.assistantText,
    this.stats,
  });
  final String userText;
  final String assistantText;
  final LlmStats? stats;
}

class _ContextHeader extends StatelessWidget {
  const _ContextHeader({required this.response});
  final AnalysisResponse response;

  @override
  Widget build(BuildContext context) {
    final sev = response.severity.toLowerCase();
    final accent = switch (sev) {
      'severe' => KneedleTheme.danger,
      'moderate' => KneedleTheme.amber,
      _ => KneedleTheme.success,
    };
    final firstExercise = response.exercises.isEmpty
        ? null
        : response.exercises.first.def.nameEn;
    return KCard(
      tone: KCardTone.sage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'YOUR REPORT IS LOADED',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: KneedleTheme.sageDeep,
                      letterSpacing: 1.2,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_titleCase(response.severity)} severity · '
            'symmetry ${response.symmetryScore}/100'
            '${firstExercise == null ? '' : ' · plan starts with $firstExercise'}',
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: KneedleTheme.sageDeep,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.prompts});
  final List<String> prompts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRY ASKING',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: KneedleTheme.inkFaint,
                letterSpacing: 1.2,
              ),
        ),
        const SizedBox(height: 8),
        for (final p in prompts) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: KneedleTheme.surface,
              borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
              border: Border.all(color: KneedleTheme.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    size: 18, color: KneedleTheme.inkFaint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: KneedleTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: KneedleTheme.sage,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, this.stats});
  final String text;
  final LlmStats? stats;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: KneedleTheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: KneedleTheme.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: KneedleTheme.sageTint,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 12,
                      color: KneedleTheme.sageDeep,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'KNEEDLE',
                    style:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: KneedleTheme.inkFaint,
                              letterSpacing: 1.2,
                            ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: KneedleTheme.ink,
                ),
              ),
              if (stats != null) ...[
                const SizedBox(height: 8),
                _GenerationStatsFooter(stats: stats!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Footer pill row showing tokens, decode time, and tokens/sec for the
/// reply just rendered. Same shape used on the gait result screen so the
/// user (and a watching dev) can compare costs across screens at a glance.
class _GenerationStatsFooter extends StatelessWidget {
  const _GenerationStatsFooter({required this.stats});
  final LlmStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(
          icon: Icons.bolt_rounded,
          label: '${stats.tokensPerSecond.toStringAsFixed(1)} tok/s',
          accent: KneedleTheme.sageDeep,
          tint: KneedleTheme.sageTint,
        ),
        const SizedBox(width: 6),
        _StatChip(
          icon: Icons.text_snippet_rounded,
          label: '${stats.outputTokens} tok',
          accent: KneedleTheme.inkMuted,
          tint: KneedleTheme.cream,
        ),
        const SizedBox(width: 6),
        _StatChip(
          icon: Icons.timer_outlined,
          label: '${stats.totalMs}ms',
          accent: KneedleTheme.inkMuted,
          tint: KneedleTheme.cream,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.tint,
  });
  final IconData icon;
  final String label;
  final Color accent;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
