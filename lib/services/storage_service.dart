import 'package:hive_flutter/hive_flutter.dart';

import '../models/appointment.dart';
import '../models/exercise_session.dart';
import '../models/gait_session.dart';
import '../models/medication.dart';
import '../models/pain_entry.dart';

/// Hive bootstrap and box accessors. The app's only persistence layer.
class StorageService {
  StorageService._();

  static const _painEntriesBox = 'pain_entries';
  static const _exerciseBox = 'exercise_sessions';
  static const _gaitBox = 'gait_sessions';
  static const _prefsBox = 'preferences';
  static const _medicationsBox = 'medications';
  static const _appointmentsBox = 'appointments';

  static late Box<PainEntry> _painEntries;
  static late Box<ExerciseSession> _exercises;
  static late Box<GaitSession> _gaits;
  static late Box<dynamic> _prefs;
  static late Box<Medication> _medications;
  static late Box<Appointment> _appointments;

  /// Call once from `main()` before `runApp`.
  static Future<void> init() async {
    await Hive.initFlutter('kneedle');
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PainEntryAdapter());
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ExerciseSessionAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GaitSessionAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(MedicationAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(AppointmentAdapter());
    }

    _painEntries = await Hive.openBox<PainEntry>(_painEntriesBox);
    _exercises = await Hive.openBox<ExerciseSession>(_exerciseBox);
    _gaits = await Hive.openBox<GaitSession>(_gaitBox);
    _prefs = await Hive.openBox<dynamic>(_prefsBox);
    _medications = await Hive.openBox<Medication>(_medicationsBox);
    _appointments = await Hive.openBox<Appointment>(_appointmentsBox);
  }

  static Box<PainEntry> get painEntries => _painEntries;
  static Box<ExerciseSession> get exercises => _exercises;
  static Box<GaitSession> get gaits => _gaits;
  static Box<dynamic> get prefs => _prefs;
  static Box<Medication> get medications => _medications;
  static Box<Appointment> get appointments => _appointments;

  static Future<void> savePainEntry(PainEntry e) =>
      _painEntries.put(e.id, e);

  static Future<void> saveExerciseSession(ExerciseSession e) =>
      _exercises.put(e.id, e);

  static Future<void> saveGaitSession(GaitSession g) => _gaits.put(g.id, g);

  static List<PainEntry> recentPainEntries({int limit = 50}) {
    final list = _painEntries.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.take(limit).toList();
  }

  static List<GaitSession> recentGaitSessions({int limit = 50}) {
    final list = _gaits.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.take(limit).toList();
  }

  static List<ExerciseSession> recentExerciseSessions({int limit = 50}) {
    final list = _exercises.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.take(limit).toList();
  }

  static Future<void> saveMedication(Medication m) =>
      _medications.put(m.id, m);

  static Future<void> deleteMedication(int id) => _medications.delete(id);

  static List<Medication> allMedications() {
    final list = _medications.values.toList()
      ..sort((a, b) {
        final ah = a.hour * 60 + a.minute;
        final bh = b.hour * 60 + b.minute;
        return ah.compareTo(bh);
      });
    return list;
  }

  static Future<void> saveAppointment(Appointment a) =>
      _appointments.put(a.id, a);

  static Future<void> deleteAppointment(int id) => _appointments.delete(id);

  static List<Appointment> upcomingAppointments({int limit = 50}) {
    final now = DateTime.now();
    final list = _appointments.values
        .where((a) => a.when.isAfter(now.subtract(const Duration(hours: 1))))
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));
    return list.take(limit).toList();
  }

  static Appointment? nextAppointment() {
    final up = upcomingAppointments(limit: 1);
    return up.isEmpty ? null : up.first;
  }

  static Future<void> close() => Hive.close();
}
