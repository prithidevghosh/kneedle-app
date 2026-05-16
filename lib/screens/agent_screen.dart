import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/gemma_service.dart';
import '../services/voice_service.dart';
import '../widgets/widgets.dart';
import 'doctor_report_screen.dart';
import 'exercise_coach_screen.dart';
import 'gait_capture_screen.dart';
import 'history_screen.dart';

/// Voice-first "Hey Kneedle" agent. The headline Gemma 4 surface — one
/// utterance can chain through multiple function calls (log pain, schedule
/// reminder, open the gait test, etc.) without the user touching another
/// button.
///
/// Architecture is deliberately minimal:
///   1. STT captures one utterance (manual stop on second tap).
///   2. `GemmaService.chat(transcript)` routes through the existing
///      function-calling dispatcher in `_handleResponse`. Tools fire and
///      append themselves to `GemmaService.lastToolCalls`.
///   3. The screen reads `lastToolCalls`, animates a step row per call,
///      speaks the final reply via TTS, then either auto-dismisses or
///      executes a single navigation intent (`start_gait_test`,
///      `show_history`, `generate_doctor_report`).
///
/// No new model session is created — we reuse the companion chat that's
/// already warmed up. This keeps first-utterance latency comparable to the
/// pain-journal voice flow.
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key, this.localeId = 'en_US'});

  final String localeId;

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

enum _Phase { idle, listening, thinking, done, error }

class _AgentScreenState extends ConsumerState<AgentScreen> {
  _Phase _phase = _Phase.idle;
  String? _transcript;
  String? _reply;
  String? _error;
  List<AgentToolCall> _toolCalls = const [];

  @override
  void dispose() {
    // Don't keep mic / TTS alive past dismissal. Use the singleton directly
    // — `ref.read(...)` throws "Cannot use ref after the widget was disposed"
    // by the time dispose runs, so the cancel never fires and the recognizer
    // stays open, restart-looping on every `error_language_unavailable`.
    VoiceService.instance.cancel();
    super.dispose();
  }

  Future<void> _onMicTap() async {
    final voice = ref.read(voiceServiceProvider);
    final gemma = ref.read(gemmaServiceProvider);

    // Tap-to-stop while listening.
    if (_phase == _Phase.listening) {
      final captured = await voice.stopAndCollect();
      if (!mounted) return;
      if (captured.isEmpty) {
        setState(() {
          _phase = _Phase.error;
          _error = "I didn't catch that — try once more.";
        });
        return;
      }
      setState(() {
        _phase = _Phase.thinking;
        _transcript = captured;
      });
      await _runAgent(gemma, captured, voice);
      return;
    }

    if (_phase == _Phase.thinking) return; // Tap is a no-op mid-think.

    // Reset for a fresh utterance.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'Microphone access is needed. Enable it in Settings.';
      });
      return;
    }

    setState(() {
      _phase = _Phase.listening;
      _transcript = null;
      _reply = null;
      _error = null;
      _toolCalls = const [];
    });
    try {
      await voice.startListening(localeId: widget.localeId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'Voice error: $e';
      });
    }
  }

  Future<void> _runAgent(
    GemmaService gemma,
    String transcript,
    dynamic voice,
  ) async {
    try {
      final reply = await gemma.chat(transcript);
      if (!mounted) return;
      final calls = List<AgentToolCall>.from(gemma.lastToolCalls);
      bumpData(ref); // Refresh Hive-backed providers after any storage write.
      setState(() {
        _phase = _Phase.done;
        _reply = reply;
        _toolCalls = calls;
      });
      // Fire TTS in parallel — DO NOT await it. Some Android TTS engines
      // never call the completion callback that `awaitSpeakCompletion(true)`
      // depends on (a known flutter_tts quirk on certain OEM voices). If we
      // awaited here, the navigation auto-finish below would silently never
      // run and the user would have to tap the manual confirm button —
      // exactly the bug we hit. The dispose hook still stops TTS on teardown.
      // ignore: avoid_dynamic_calls
      unawaited(voice.speak(reply));

      // If a navigation-intent tool fired, auto-finish so `routeToAgent`
      // pushes the destination screen — the user shouldn't have to tap a
      // confirmation button after the agent has already said "opening the
      // walking test". 700ms gives them time to see the reply card and hear
      // the first few words of the acknowledgement before the screen
      // transitions; TTS gets cancelled at that point but the destination
      // screen is the answer anyway.
      if (!mounted) return;
      final hasNav = calls.any((c) => c.ok && c.nav != null);
      if (hasNav) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        _finish();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  /// Pop with whatever navigation intent the model emitted, if any. Home is
  /// then responsible for opening the destination — keeping nav-from-modal
  /// off this screen avoids the "double-pop" race where the destination
  /// would mount while we're still tearing down.
  void _finish() {
    final nav = _toolCalls
        .firstWhere(
          (c) => c.ok && c.nav != null,
          orElse: () => AgentToolCall(name: '', args: {}, result: const {}),
        )
        .nav;
    Navigator.of(context).pop(nav);
  }

  @override
  Widget build(BuildContext context) {
    final mic = switch (_phase) {
      _Phase.listening => KMicState.listening,
      _Phase.thinking => KMicState.processing,
      _ => KMicState.idle,
    };

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Hey Kneedle'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KneedleTheme.space5,
            KneedleTheme.space2,
            KneedleTheme.space5,
            KneedleTheme.space5,
          ),
          physics: const BouncingScrollPhysics(),
          children: [
            const SafetyBanner(),
            const SizedBox(height: KneedleTheme.space5),
            Center(child: KMicButton(state: mic, onTap: _onMicTap)),
            const SizedBox(height: KneedleTheme.space5),
            Text(
              _statusHeading,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: KneedleTheme.space2),
            Text(
              _statusDetail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_transcript != null) ...[
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
                      '"${_transcript!}"',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: KneedleTheme.sageDeep,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_toolCalls.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space4),
              _ToolTimeline(calls: _toolCalls),
            ],
            if (_reply != null && _reply!.isNotEmpty) ...[
              const SizedBox(height: KneedleTheme.space4),
              KCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KNEEDLE',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _reply!,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: KneedleTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: KneedleTheme.space4),
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
            if (_phase == _Phase.done) ...[
              const SizedBox(height: KneedleTheme.space5),
              FilledButton(
                onPressed: _finish,
                child: Text(_finishLabel),
              ),
              const SizedBox(height: KneedleTheme.space2),
              OutlinedButton(
                onPressed: _onMicTap,
                child: const Text('Ask something else'),
              ),
            ],
            if (_phase == _Phase.idle && _transcript == null) ...[
              const SizedBox(height: KneedleTheme.space5),
              _Examples(),
            ],
          ],
        ),
      ),
    );
  }

  String get _statusHeading => switch (_phase) {
        _Phase.idle => 'Tap and speak',
        _Phase.listening => 'Listening…',
        _Phase.thinking => 'Working on it…',
        _Phase.done => _toolCalls.isEmpty ? 'Done' : 'Done — see below',
        _Phase.error => 'Something went wrong',
      };

  String get _statusDetail => switch (_phase) {
        _Phase.idle => '"Log 6/10, remind me to exercise at 7pm" — all '
            'on-device.',
        _Phase.listening => 'Tap again when you finish speaking.',
        _Phase.thinking => 'Gemma is choosing the right tools.',
        _Phase.done => 'Tap below to confirm — Kneedle has already saved '
            'everything.',
        _Phase.error => 'Try again, or close and use the tabs.',
      };

  String get _finishLabel {
    final navCall = _toolCalls.firstWhere(
      (c) => c.ok && c.nav != null,
      orElse: () => AgentToolCall(name: '', args: {}, result: const {}),
    );
    switch (navCall.nav) {
      case 'gait_capture':
        return 'Open walking test';
      case 'exercise':
        return 'Open exercise coach';
      case 'history':
        return 'Open trends';
      case 'doctor_report':
        return 'Open doctor report';
      default:
        return 'Done';
    }
  }

  static const List<_Example> _samples = [
    _Example(
      icon: Icons.edit_note_rounded,
      text: '"My knee is 6 today on the right side."',
    ),
    _Example(
      icon: Icons.alarm_rounded,
      text: '"Remind me to do exercises at 7 pm."',
    ),
    _Example(
      icon: Icons.directions_walk_rounded,
      text: '"Start my walking test."',
    ),
    _Example(
      icon: Icons.description_outlined,
      text: '"Make a doctor report I can share."',
    ),
  ];
}

class _Examples extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRY ASKING',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        for (final e in _AgentScreenState._samples) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: KneedleTheme.surface,
              borderRadius:
                  BorderRadius.circular(KneedleTheme.radiusLg),
              border: Border.all(color: KneedleTheme.hairline),
            ),
            child: Row(
              children: [
                Icon(e.icon, size: 18, color: KneedleTheme.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.text,
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

class _Example {
  const _Example({required this.icon, required this.text});
  final IconData icon;
  final String text;
}

/// One-row-per-tool execution timeline. Reads from
/// `GemmaService.lastToolCalls`, formats each into a single line ("✓ Logged
/// pain 6/10 at right knee") that matches what the agent actually did.
class _ToolTimeline extends StatelessWidget {
  const _ToolTimeline({required this.calls});
  final List<AgentToolCall> calls;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHAT KNEEDLE DID',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        for (final c in calls) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.ok
                  ? KneedleTheme.sageSoft
                  : KneedleTheme.coralTint,
              borderRadius:
                  BorderRadius.circular(KneedleTheme.radiusMd),
              border: Border.all(
                color: c.ok
                    ? KneedleTheme.sage.withValues(alpha: 0.25)
                    : KneedleTheme.coral.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  c.ok
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 20,
                  color: c.ok ? KneedleTheme.sage : KneedleTheme.coral,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _labelForTool(c.name),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: KneedleTheme.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.acknowledgement ??
                            (c.ok ? 'Done.' : 'Skipped.'),
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: KneedleTheme.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _labelForTool(String name) => switch (name) {
        'record_pain_entry' => 'PAIN LOGGED',
        'schedule_reminder' => 'REMINDER SET',
        'add_medication' => 'MEDICATION ADDED',
        'add_appointment' => 'APPOINTMENT ADDED',
        'remove_medication' => 'MEDICATION REMOVED',
        'remove_appointment' => 'APPOINTMENT REMOVED',
        'list_medications' => 'MEDICATIONS',
        'list_appointments' => 'APPOINTMENTS',
        'start_gait_test' => 'WALKING TEST',
        'start_exercise' => 'EXERCISE COACH',
        'show_history' => 'TRENDS',
        'generate_doctor_report' => 'DOCTOR REPORT',
        _ => name.toUpperCase(),
      };
}

/// Push the agent screen and execute any navigation intent the model
/// emitted. Returns when the user closes the modal (and, if applicable, the
/// destination screen).
Future<void> routeToAgent(BuildContext context) async {
  final nav = await Navigator.of(context).push<String?>(
    MaterialPageRoute(
      builder: (_) => const AgentScreen(),
      fullscreenDialog: true,
    ),
  );
  if (nav == null || !context.mounted) return;
  switch (nav) {
    case 'gait_capture':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GaitCaptureScreen()),
      );
      break;
    case 'exercise':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ExerciseCoachScreen()),
      );
      break;
    case 'history':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HistoryScreen()),
      );
      break;
    case 'doctor_report':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DoctorReportScreen()),
      );
      break;
  }
}
