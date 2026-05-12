import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../models/appointment.dart';
import '../models/medication.dart';
import '../providers/providers.dart';
import '../services/gemma_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/widgets.dart';

/// Voice-driven medication and appointment reminders. Mic input is routed
/// through GemmaService's free-chat path so the model decides whether to
/// invoke `add_medication`, `add_appointment`, `schedule_reminder`, or one of
/// the list-query tools.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  KMicState _micState = KMicState.idle;
  String _heading = 'Ask Kneedle to remember';
  String _detail =
      'Tap the mic, speak, then tap again to stop. Try: "remind me to take Diclofenac at 8pm".';
  String? _lastTranscript;
  String? _lastReply;

  Future<void> _onMicTap() async {
    switch (_micState) {
      case KMicState.idle:
        await _startListening();
        break;
      case KMicState.listening:
        await _stopAndProcess();
        break;
      case KMicState.processing:
        // Ignore taps while inference is running.
        break;
    }
  }

  Future<void> _startListening() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() {
        _heading = 'Microphone needed';
        _detail = 'Allow microphone access in Settings to use voice.';
      });
      return;
    }
    try {
      await ref.read(voiceServiceProvider).startListening();
      if (!mounted) return;
      setState(() {
        _micState = KMicState.listening;
        _heading = 'Listening…';
        _detail = 'Speak naturally. Tap the button again when you\'re done.';
        _lastTranscript = null;
        _lastReply = null;
      });
    } catch (e) {
      setState(() {
        _heading = 'Voice error';
        _detail = '$e';
      });
    }
  }

  Future<void> _stopAndProcess() async {
    final voice = ref.read(voiceServiceProvider);
    setState(() {
      _micState = KMicState.processing;
      _heading = 'Processing…';
      _detail = 'Catching your words.';
    });
    try {
      final transcript = await voice.stopAndCollect();
      if (transcript.isEmpty) {
        setState(() {
          _micState = KMicState.idle;
          _heading = "Didn't catch that";
          _detail = 'Try again in a quieter spot.';
        });
        return;
      }
      setState(() {
        _lastTranscript = transcript;
        _heading = 'Setting up your reminder…';
        _detail = 'Working on-device. This stays private.';
      });

      if (_looksLikeReminder(transcript)) {
        // ignore: unawaited_futures
        voice.speak('Setting up your reminder, just a moment.');
      }

      final reply = await GemmaService.instance.chat(transcript);

      // ignore: unawaited_futures
      voice.speak(reply);

      bumpData(ref);
      if (!mounted) return;
      setState(() {
        _micState = KMicState.idle;
        _heading = 'Done';
        _detail = 'Reminders update below.';
        _lastReply = reply;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _micState = KMicState.idle;
        _heading = 'Voice error';
        _detail = '$e';
      });
    }
  }

  @override
  void dispose() {
    ref.read(voiceServiceProvider).cancel();
    super.dispose();
  }

  static bool _looksLikeReminder(String t) {
    final s = t.toLowerCase();
    return s.contains('remind') ||
        s.contains('medicine') ||
        s.contains('medication') ||
        s.contains('appointment') ||
        s.contains('doctor') ||
        s.contains('visit');
  }

  @override
  Widget build(BuildContext context) {
    final meds = ref.watch(medicationsProvider);
    final appts = ref.watch(appointmentsProvider);

    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            tooltip: 'Add manually',
            icon: const Icon(Icons.add_rounded),
            onPressed: _showAddSheet,
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
            const SizedBox(height: KneedleTheme.space4),
            Center(
              child: KMicButton(
                state: _micState,
                onTap: _onMicTap,
              ),
            ),
            const SizedBox(height: KneedleTheme.space5),
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
            const KSectionTitle(
              eyebrow: 'Medications',
              title: 'Daily reminders',
            ),
            const SizedBox(height: KneedleTheme.space4),
            if (meds.isEmpty)
              const KEmptyState(
                icon: Icons.medication_outlined,
                title: 'No medications yet',
                message:
                    'Say "remind me to take my pill at 8pm" to add one.',
              )
            else
              for (final m in meds) ...[
                _MedicationCard(
                  med: m,
                  onDelete: () => _deleteMedication(m),
                ),
                const SizedBox(height: KneedleTheme.space3),
              ],
            const SizedBox(height: KneedleTheme.space7),
            const KSectionTitle(
              eyebrow: 'Appointments',
              title: 'Upcoming visits',
            ),
            const SizedBox(height: KneedleTheme.space4),
            if (appts.isEmpty)
              const KEmptyState(
                icon: Icons.event_outlined,
                title: 'Nothing scheduled',
                message:
                    'Say "I have an appointment with Dr Sharma next Tuesday at 3pm".',
              )
            else
              for (final a in appts) ...[
                _AppointmentCard(
                  appt: a,
                  onDelete: () => _deleteAppointment(a),
                ),
                const SizedBox(height: KneedleTheme.space3),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMedication(Medication m) async {
    await NotificationService.cancel(m.id);
    await StorageService.deleteMedication(m.id);
    bumpData(ref);
  }

  Future<void> _deleteAppointment(Appointment a) async {
    await NotificationService.cancel(a.id);
    await StorageService.deleteAppointment(a.id);
    bumpData(ref);
  }

  Future<void> _showAddSheet() async {
    final choice = await showModalBottomSheet<_AddKind>(
      context: context,
      builder: (_) => const _AddPickerSheet(),
    );
    if (choice == null || !mounted) return;
    if (choice == _AddKind.medication) {
      await _showAddMedicationSheet();
    } else {
      await _showAddAppointmentSheet();
    }
  }

  Future<void> _showAddMedicationSheet() async {
    final result = await showModalBottomSheet<_NewMedication>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _MedicationSheet(),
    );
    if (result == null) return;
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff;
    final med = Medication(
      id: id,
      name: result.name,
      dose: result.dose,
      hour: result.time.hour,
      minute: result.time.minute,
      createdAt: now,
    );
    await StorageService.saveMedication(med);
    await NotificationService.scheduleDaily(
      id: id,
      title: 'Time for ${med.name}',
      body: med.dose.isEmpty ? 'Daily reminder' : 'Take ${med.dose}',
      hour: med.hour,
      minute: med.minute,
    );
    bumpData(ref);
  }

  Future<void> _showAddAppointmentSheet() async {
    final result = await showModalBottomSheet<_NewAppointment>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AppointmentSheet(),
    );
    if (result == null) return;
    final now = DateTime.now();
    final id = result.when.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff;
    final appt = Appointment(
      id: id,
      title: result.title,
      when: result.when,
      createdAt: now,
      location: result.location.isEmpty ? null : result.location,
    );
    await StorageService.saveAppointment(appt);
    final notifyAt = result.when.subtract(const Duration(hours: 1));
    if (notifyAt.isAfter(now)) {
      await NotificationService.scheduleReminder(
        id: id,
        title: 'Upcoming: ${result.title}',
        body: result.location.isEmpty
            ? 'In 1 hour'
            : 'In 1 hour at ${result.location}',
        when: notifyAt,
      );
    }
    bumpData(ref);
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({required this.med, required this.onDelete});
  final Medication med;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
              color: KneedleTheme.sageTint,
              borderRadius: BorderRadius.circular(KneedleTheme.radiusMd),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.medication_rounded,
              color: KneedleTheme.sageDeep,
              size: 26,
            ),
          ),
          const SizedBox(width: KneedleTheme.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${med.timeLabel} · daily${med.dose.isEmpty ? '' : ' · ${med.dose}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (med.notes != null) ...[
                  const SizedBox(height: KneedleTheme.space2),
                  Text(
                    med.notes!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: KneedleTheme.inkMuted,
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
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appt, required this.onDelete});
  final Appointment appt;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, MMM d');
    final tf = DateFormat('h:mm a');
    final inDays = appt.when.difference(DateTime.now()).inDays;
    final chip = inDays <= 0
        ? 'Today'
        : inDays == 1
            ? 'Tomorrow'
            : 'In $inDays days';

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
              color: KneedleTheme.amberTint,
              borderRadius: BorderRadius.circular(KneedleTheme.radiusMd),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.event_rounded,
              color: Color(0xFF8E5B0A),
              size: 26,
            ),
          ),
          const SizedBox(width: KneedleTheme.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appt.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KneedleTheme.sageTint,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        chip,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KneedleTheme.sageDeep,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${df.format(appt.when)} · ${tf.format(appt.when)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (appt.location != null) ...[
                  const SizedBox(height: KneedleTheme.space2),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: KneedleTheme.inkMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          appt.location!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: KneedleTheme.inkMuted,
                          ),
                        ),
                      ),
                    ],
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
}

enum _AddKind { medication, appointment }

class _AddPickerSheet extends StatelessWidget {
  const _AddPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KneedleTheme.space5,
          KneedleTheme.space2,
          KneedleTheme.space5,
          KneedleTheme.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add a reminder',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: KneedleTheme.space5),
            ListTile(
              leading: const Icon(Icons.medication_rounded,
                  color: KneedleTheme.sageDeep),
              title: const Text('Medication (daily)'),
              subtitle: const Text('Repeats every day at the same time'),
              onTap: () =>
                  Navigator.of(context).pop(_AddKind.medication),
            ),
            ListTile(
              leading: const Icon(Icons.event_rounded,
                  color: Color(0xFF8E5B0A)),
              title: const Text('Appointment'),
              subtitle: const Text('One-off — notifies 1 hour before'),
              onTap: () =>
                  Navigator.of(context).pop(_AddKind.appointment),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewMedication {
  _NewMedication({required this.name, required this.dose, required this.time});
  final String name;
  final String dose;
  final TimeOfDay time;
}

class _MedicationSheet extends StatefulWidget {
  const _MedicationSheet();
  @override
  State<_MedicationSheet> createState() => _MedicationSheetState();
}

class _MedicationSheetState extends State<_MedicationSheet> {
  final _name = TextEditingController();
  final _dose = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
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
          Text('New medication',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: KneedleTheme.space4),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Diclofenac',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: KneedleTheme.space3),
          TextField(
            controller: _dose,
            decoration: const InputDecoration(
              labelText: 'Dose (optional)',
              hintText: 'e.g. 50 mg',
            ),
          ),
          const SizedBox(height: KneedleTheme.space3),
          OutlinedButton.icon(
            onPressed: _pickTime,
            icon: const Icon(Icons.schedule_rounded),
            label: Text('Time · ${_time.format(context)}'),
          ),
          const SizedBox(height: KneedleTheme.space5),
          FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(_NewMedication(
                name: name,
                dose: _dose.text.trim(),
                time: _time,
              ));
            },
            child: const Text('Save reminder'),
          ),
        ],
      ),
    );
  }
}

class _NewAppointment {
  _NewAppointment({
    required this.title,
    required this.when,
    required this.location,
  });
  final String title;
  final DateTime when;
  final String location;
}

class _AppointmentSheet extends StatefulWidget {
  const _AppointmentSheet();
  @override
  State<_AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends State<_AppointmentSheet> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, MMM d');
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
          Text('New appointment',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: KneedleTheme.space4),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Dr Sharma — knee follow-up',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: KneedleTheme.space3),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              hintText: 'Clinic name or address',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: KneedleTheme.space3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Text(df.format(_date)),
                ),
              ),
              const SizedBox(width: KneedleTheme.space3),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(_time.format(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: KneedleTheme.space5),
          FilledButton(
            onPressed: () {
              final title = _title.text.trim();
              if (title.isEmpty) return;
              final when = DateTime(
                _date.year,
                _date.month,
                _date.day,
                _time.hour,
                _time.minute,
              );
              if (!when.isAfter(DateTime.now())) return;
              Navigator.of(context).pop(_NewAppointment(
                title: title,
                when: when,
                location: _location.text.trim(),
              ));
            },
            child: const Text('Save appointment'),
          ),
        ],
      ),
    );
  }
}
