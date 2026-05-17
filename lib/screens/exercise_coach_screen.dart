import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/analysis_response.dart';
import '../models/exercise_session.dart';
import '../models/gait_session.dart';
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
    this.repsLabel,
    this.reason,
  });
  final String name;
  final int targetReps;
  final String cue;
  final String? repsLabel;
  final String? reason;
}

/// Parse the first integer out of strings like "15×3" / "10x3" / "12 reps".
/// Falls back to 10 when no number is found.
int _parseTargetReps(String reps) {
  final m = RegExp(r'(\d+)').firstMatch(reps);
  if (m == null) return 10;
  final v = int.tryParse(m.group(1)!);
  if (v == null || v <= 0) return 10;
  return v;
}

_Prescription _toPrescription(PrescribedExercise pe) {
  final def = pe.def;
  return _Prescription(
    name: def.nameEn.isNotEmpty ? def.nameEn : def.name,
    targetReps: _parseTargetReps(def.repsEn.isNotEmpty ? def.repsEn : def.reps),
    cue: def.descriptionEn.isNotEmpty
        ? def.descriptionEn
        : def.description,
    repsLabel: def.repsEn.isNotEmpty ? def.repsEn : def.reps,
    reason: pe.reason,
  );
}

class _SessionPlan {
  _SessionPlan({
    required this.session,
    required this.label,
    required this.exercises,
  });
  final GaitSession session;
  final String label;
  final List<_Prescription> exercises;
}

/// Build the per-session plan list (oldest = Session 1, newest last) from the
/// gait history. Sessions without a persisted analysis (older saves) or with
/// no exercises in the analysis are dropped — there's nothing to coach for
/// them.
List<_SessionPlan> _buildSessionPlans(List<GaitSession> sessions) {
  // `recentGaitSessions` returns newest-first; reverse so Session 1 is the
  // chronologically first capture.
  final ordered = sessions.reversed.toList();
  final out = <_SessionPlan>[];
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    final raw = s.analysisJson;
    if (raw == null || raw.isEmpty) continue;
    final analysis = AnalysisResponse.fromStoredJson(raw);
    if (analysis == null || analysis.exercises.isEmpty) continue;
    out.add(_SessionPlan(
      session: s,
      label: 'Session ${i + 1}',
      exercises: [for (final e in analysis.exercises) _toPrescription(e)],
    ));
  }
  return out;
}

class _ExerciseCoachScreenState extends ConsumerState<ExerciseCoachScreen> {
  // Pace: one rep every 3 seconds. TTS announces the count on each tick.
  static const Duration _repInterval = Duration(seconds: 3);

  _Prescription? _active;
  int _reps = 0;
  DateTime? _started;
  bool _paused = false;
  Timer? _ticker;

  // Which session's prescribed plan is currently selected. Held as a session
  // id (stable across rebuilds) rather than an index so newly-saved sessions
  // don't shift the selection. Null = "use the most recent session" (default
  // when the screen opens).
  int? _selectedSessionId;

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
    final exerciseSessions = ref.watch(exerciseSessionsProvider);
    final gaitSessions = ref.watch(gaitSessionsProvider);
    final today = _todaysSessions(exerciseSessions);
    final plans = _buildSessionPlans(gaitSessions);

    _SessionPlan? selected;
    if (plans.isNotEmpty) {
      if (_selectedSessionId != null) {
        for (final p in plans) {
          if (p.session.id == _selectedSessionId) {
            selected = p;
            break;
          }
        }
      }
      // Default: newest session (last in chronological order).
      selected ??= plans.last;
    }

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(title: const Text('Exercise coach')),
      body: SafeArea(
        child: _active == null
            ? _PlanView(
                plans: plans,
                selected: selected,
                today: today,
                onSelectSession: (p) =>
                    setState(() => _selectedSessionId = p.session.id),
                onStart: _start,
              )
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
    required this.plans,
    required this.selected,
    required this.today,
    required this.onSelectSession,
    required this.onStart,
  });
  final List<_SessionPlan> plans;
  final _SessionPlan? selected;
  final Map<String, ExerciseSession> today;
  final void Function(_SessionPlan) onSelectSession;
  final void Function(_Prescription) onStart;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty || selected == null) {
      return _EmptyPlan();
    }
    final plan = selected!.exercises;
    final completedCount = plan
        .where((p) => (today[p.name]?.repsCompleted ?? 0) >= p.targetReps)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KneedleTheme.space5,
        KneedleTheme.space4,
        KneedleTheme.space5,
        KneedleTheme.space7,
      ),
      children: [
        if (plans.length > 1) ...[
          Text(
            'SESSION',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: KneedleTheme.inkMuted,
                ),
          ),
          const SizedBox(height: KneedleTheme.space2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in plans) ...[
                  _SessionChip(
                    label: p.label,
                    timestamp: p.session.timestamp,
                    selected: p.session.id == selected!.session.id,
                    onTap: () => onSelectSession(p),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: KneedleTheme.space4),
        ],
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
          'PRESCRIBED · ${selected!.label.toUpperCase()}',
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

class _SessionChip extends StatelessWidget {
  const _SessionChip({
    required this.label,
    required this.timestamp,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final DateTime timestamp;
  final bool selected;
  final VoidCallback onTap;

  String _shortDate(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? KneedleTheme.sage : Colors.white,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? KneedleTheme.sage : KneedleTheme.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : KneedleTheme.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                _shortDate(timestamp),
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : KneedleTheme.inkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(KneedleTheme.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.self_improvement_rounded,
            size: 48,
            color: KneedleTheme.inkFaint,
          ),
          const SizedBox(height: KneedleTheme.space4),
          Text(
            'No prescribed exercises yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: KneedleTheme.space2),
          const Text(
            'Run a gait check first — the personalised exercise plan from '
            'that report will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: KneedleTheme.inkMuted, height: 1.4),
          ),
        ],
      ),
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
                      '${prescription.repsLabel ?? '${prescription.targetReps} reps'} · ${prescription.cue}',
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
