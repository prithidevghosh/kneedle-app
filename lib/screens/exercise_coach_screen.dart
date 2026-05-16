import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/exercise_session.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';

/// Voice-coached exercise surface.
///
/// Each prescribed exercise has a target rep count. Starting a session paces
/// the user at one rep every [_repInterval] — a [Timer.periodic] auto-
/// increments the counter and TTS announces each number, so the user can
/// focus on the movement. A pause/resume toggle and a manual +1 button are
/// kept for users who want to override the pace.
///
/// Completed sessions are persisted via [StorageService.saveExerciseSession]
/// and the "Today" strip above the list surfaces what's already been logged
/// since midnight, so the user can see what's left for the day at a glance.
class ExerciseCoachScreen extends ConsumerStatefulWidget {
  const ExerciseCoachScreen({super.key});

  @override
  ConsumerState<ExerciseCoachScreen> createState() =>
      _ExerciseCoachScreenState();
}

class _Prescription {
  const _Prescription({
    required this.name,
    required this.targetReps,
    required this.cue,
  });
  final String name;
  final int targetReps;
  final String cue;
}

const _plan = <_Prescription>[
  _Prescription(
    name: 'Knee flexion',
    targetReps: 10,
    cue: 'Bend the knee slowly, then straighten.',
  ),
  _Prescription(
    name: 'Quad set',
    targetReps: 10,
    cue: 'Tighten the thigh and hold for five seconds.',
  ),
  _Prescription(
    name: 'Heel slide',
    targetReps: 10,
    cue: 'Slide the heel toward the hip, then back.',
  ),
  _Prescription(
    name: 'Straight leg raise',
    targetReps: 10,
    cue: 'Keep the knee locked and lift the leg.',
  ),
];

class _ExerciseCoachScreenState extends ConsumerState<ExerciseCoachScreen> {
  // Pace: one rep every 3 seconds. TTS announces the count on each tick.
  static const Duration _repInterval = Duration(seconds: 3);

  _Prescription? _active;
  int _reps = 0;
  DateTime? _started;
  bool _paused = false;
  Timer? _ticker;

  // Direct singleton handle so dispose / async callbacks don't have to touch
  // `ref` (which becomes invalid the moment the widget is disposed).
  final VoiceService _voice = VoiceService.instance;

  Future<void> _start(_Prescription p) async {
    setState(() {
      _active = p;
      _reps = 0;
      _started = DateTime.now();
      _paused = false;
    });
    // Speak the intro, then start the pacing timer. We don't await the TTS
    // before starting the timer — on slow devices the first tick should still
    // land ~3s after Start, not 3s after the intro finishes.
    _voice.speak(
      '${p.name}. Target ${p.targetReps} reps. I will count for you.',
    );
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_repInterval, (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    if (!mounted) return;
    final active = _active;
    if (active == null || _paused) return;
    final next = _reps + 1;
    setState(() => _reps = next);
    _voice.speak('$next');
    if (next >= active.targetReps) {
      _stopTicker();
      _finish(reachedTarget: true);
    }
  }

  void _togglePause() {
    final next = !_paused;
    setState(() => _paused = next);
    if (next) {
      _stopTicker();
      _voice.speak('Paused.');
    } else {
      _startTicker();
      _voice.speak('Resuming.');
    }
  }

  void _bumpManual() {
    final active = _active;
    if (active == null) return;
    final next = (_reps + 1).clamp(0, active.targetReps);
    setState(() => _reps = next);
    _voice.speak('$next');
    if (next >= active.targetReps) {
      _stopTicker();
      _finish(reachedTarget: true);
    }
  }

  Future<void> _finish({bool reachedTarget = false}) async {
    final active = _active;
    final started = _started;
    if (active == null || started == null) return;

    _stopTicker();
    final dur = DateTime.now().difference(started).inSeconds;
    final reps = _reps;

    if (reps > 0) {
      final session = ExerciseSession(
        id: started.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff,
        exerciseName: active.name,
        repsCompleted: reps,
        durationSec: dur,
        timestamp: started,
      );
      await StorageService.saveExerciseSession(session);
      // `ref` is only safe while the widget is still mounted — call inside
      // the mounted gate so dispose-while-saving doesn't blow up.
      if (mounted) bumpData(ref);
    }
    if (!mounted) return;

    if (reachedTarget) {
      _voice.speak('Nice work. ${active.name} complete.');
    }

    setState(() {
      _active = null;
      _paused = false;
    });
  }

  void _cancel() {
    _stopTicker();
    // Silence any in-flight TTS so it doesn't keep talking after the user
    // backs out of the active session.
    VoiceService.instance.cancel();
    if (!mounted) return;
    setState(() {
      _active = null;
      _paused = false;
      _reps = 0;
    });
  }

  @override
  void dispose() {
    // Critical: tear down BOTH the pacing timer and any voice activity before
    // the widget is torn down. We use the VoiceService singleton directly
    // since `ref` is invalid by the time dispose runs. `cancel()` stops STT,
    // clears any manual session, AND stops TTS — so the mic / speaker can't
    // outlive the screen.
    _stopTicker();
    VoiceService.instance.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(exerciseSessionsProvider);
    final today = _todaysSessions(sessions);

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(title: const Text('Exercise coach')),
      body: SafeArea(
        child: _active == null
            ? _PlanView(plan: _plan, today: today, onStart: _start)
            : _LiveCoach(
                prescription: _active!,
                reps: _reps,
                paused: _paused,
                interval: _repInterval,
                onIncrement: _bumpManual,
                onTogglePause: _togglePause,
                onFinish: () => _finish(reachedTarget: false),
                onCancel: _cancel,
              ),
      ),
    );
  }

  Map<String, ExerciseSession> _todaysSessions(List<ExerciseSession> all) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final out = <String, ExerciseSession>{};
    for (final s in all) {
      if (s.timestamp.isBefore(start)) continue;
      // Keep the latest session per exercise name.
      final prior = out[s.exerciseName];
      if (prior == null || s.timestamp.isAfter(prior.timestamp)) {
        out[s.exerciseName] = s;
      }
    }
    return out;
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView({
    required this.plan,
    required this.today,
    required this.onStart,
  });
  final List<_Prescription> plan;
  final Map<String, ExerciseSession> today;
  final void Function(_Prescription) onStart;

  @override
  Widget build(BuildContext context) {
    final completedCount =
        plan.where((p) => (today[p.name]?.repsCompleted ?? 0) >= p.targetReps).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KneedleTheme.space5,
        KneedleTheme.space4,
        KneedleTheme.space5,
        KneedleTheme.space7,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(KneedleTheme.space5),
          decoration: BoxDecoration(
            color: KneedleTheme.sageTint,
            borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TODAY'S PROGRESS",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      color: KneedleTheme.sageDeep,
                    ),
              ),
              const SizedBox(height: KneedleTheme.space2),
              Text(
                '$completedCount of ${plan.length} exercises complete',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: KneedleTheme.sageDeep,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: KneedleTheme.space3),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in plan)
                    _TodayChip(
                      label: p.name,
                      session: today[p.name],
                      target: p.targetReps,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: KneedleTheme.space5),
        Text(
          'PRESCRIBED',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: KneedleTheme.inkMuted,
              ),
        ),
        const SizedBox(height: KneedleTheme.space3),
        for (final p in plan) ...[
          _ExerciseCard(
            prescription: p,
            session: today[p.name],
            onStart: () => onStart(p),
          ),
          const SizedBox(height: KneedleTheme.space3),
        ],
      ],
    );
  }
}

class _TodayChip extends StatelessWidget {
  const _TodayChip({
    required this.label,
    required this.target,
    required this.session,
  });
  final String label;
  final int target;
  final ExerciseSession? session;

  @override
  Widget build(BuildContext context) {
    final done = (session?.repsCompleted ?? 0) >= target;
    final partial = session != null && !done;
    final bg = done
        ? KneedleTheme.success
        : partial
            ? KneedleTheme.amberTint
            : Colors.white;
    final fg = done
        ? Colors.white
        : partial
            ? KneedleTheme.ink
            : KneedleTheme.inkMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: done ? KneedleTheme.success : KneedleTheme.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done
                ? Icons.check_rounded
                : partial
                    ? Icons.timelapse_rounded
                    : Icons.circle_outlined,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            session == null
                ? label
                : '$label · ${session!.repsCompleted}/$target',
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.prescription,
    required this.session,
    required this.onStart,
  });
  final _Prescription prescription;
  final ExerciseSession? session;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final done = (session?.repsCompleted ?? 0) >= prescription.targetReps;
    // Make the whole card tappable instead of placing a trailing button next
    // to an `Expanded` child — Flutter's `Row` lays out non-flex children
    // with unbounded width during its intrinsic-sizing pass, and
    // `FilledButton`/`_RenderInputPadding` crashes on that. A full-card
    // `InkWell` sidesteps the issue and gives a much larger tap target.
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
      child: InkWell(
        onTap: onStart,
        borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
        child: Ink(
          padding: const EdgeInsets.all(KneedleTheme.space4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(KneedleTheme.radiusLg),
            border: Border.all(color: KneedleTheme.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      done ? KneedleTheme.successTint : KneedleTheme.sageSoft,
                  borderRadius:
                      BorderRadius.circular(KneedleTheme.radiusMd),
                ),
                alignment: Alignment.center,
                child: Icon(
                  done
                      ? Icons.check_rounded
                      : Icons.fitness_center_rounded,
                  color: done ? KneedleTheme.success : KneedleTheme.sage,
                ),
              ),
              const SizedBox(width: KneedleTheme.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prescription.name,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${prescription.targetReps} reps · ${prescription.cue}',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: KneedleTheme.inkMuted,
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KneedleTheme.space2),
              Text(
                done ? 'Again' : 'Start',
                style: TextStyle(
                  color: done ? KneedleTheme.sageDeep : KneedleTheme.sage,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: done ? KneedleTheme.sageDeep : KneedleTheme.sage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveCoach extends StatelessWidget {
  const _LiveCoach({
    required this.prescription,
    required this.reps,
    required this.paused,
    required this.interval,
    required this.onIncrement,
    required this.onTogglePause,
    required this.onFinish,
    required this.onCancel,
  });

  final _Prescription prescription;
  final int reps;
  final bool paused;
  final Duration interval;
  final VoidCallback onIncrement;
  final VoidCallback onTogglePause;
  final VoidCallback onFinish;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pct = (reps / prescription.targetReps).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KneedleTheme.space5,
        KneedleTheme.space4,
        KneedleTheme.space5,
        KneedleTheme.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            prescription.name.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  color: KneedleTheme.inkMuted,
                ),
          ),
          const SizedBox(height: KneedleTheme.space2),
          Text(
            prescription.cue,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: KneedleTheme.space5),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(KneedleTheme.radiusXl),
                border: Border.all(color: KneedleTheme.hairline),
              ),
              padding: const EdgeInsets.all(KneedleTheme.space6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$reps',
                    style: const TextStyle(
                      fontSize: 140,
                      fontWeight: FontWeight.w800,
                      color: KneedleTheme.sage,
                      height: 1,
                      letterSpacing: -4,
                    ),
                  ),
                  const SizedBox(height: KneedleTheme.space2),
                  Text(
                    'of ${prescription.targetReps} reps',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: KneedleTheme.inkMuted,
                        ),
                  ),
                  const SizedBox(height: KneedleTheme.space5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 10,
                      backgroundColor: KneedleTheme.sageSoft,
                      valueColor: const AlwaysStoppedAnimation(
                          KneedleTheme.sage),
                    ),
                  ),
                  const SizedBox(height: KneedleTheme.space5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        paused
                            ? Icons.pause_circle_outline_rounded
                            : Icons.graphic_eq_rounded,
                        size: 18,
                        color: paused
                            ? KneedleTheme.inkFaint
                            : KneedleTheme.sage,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        paused
                            ? 'Paused — tap resume to continue'
                            : 'Auto-counting · 1 rep every ${interval.inSeconds}s',
                        style: TextStyle(
                          color: paused
                              ? KneedleTheme.inkFaint
                              : KneedleTheme.sage,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KneedleTheme.space4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KneedleTheme.inkMuted,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: KneedleTheme.hairline),
                  ),
                ),
              ),
              const SizedBox(width: KneedleTheme.space3),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onTogglePause,
                  icon: Icon(paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded),
                  label: Text(paused ? 'Resume' : 'Pause'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KneedleTheme.sageSoft,
                    foregroundColor: KneedleTheme.sageDeep,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: KneedleTheme.space3),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Finish'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KneedleTheme.sage,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
