import 'package:hive_flutter/hive_flutter.dart';

import '../models/exercise_session.dart';
import '../models/gait_session.dart';
import '../models/pain_entry.dart';

/// Hive bootstrap and box accessors. The app's only persistence layer.
class StorageService {
  StorageService._();

  static const _painEntriesBox = 'pain_entries';
  static const _exerciseBox = 'exercise_sessions';
  static const _gaitBox = 'gait_sessions';
  static const _prefsBox = 'preferences';

  static late Box<PainEntry> _painEntries;
  static late Box<ExerciseSession> _exercises;
  static late Box<GaitSession> _gaits;
  static late Box<dynamic> _prefs;

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

    _painEntries = await Hive.openBox<PainEntry>(_painEntriesBox);
    _exercises = await Hive.openBox<ExerciseSession>(_exerciseBox);
    _gaits = await Hive.openBox<GaitSession>(_gaitBox);
    _prefs = await Hive.openBox<dynamic>(_prefsBox);
  }

  static Box<PainEntry> get painEntries => _painEntries;
  static Box<ExerciseSession> get exercises => _exercises;
  static Box<GaitSession> get gaits => _gaits;
  static Box<dynamic> get prefs => _prefs;

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

  static Future<void> close() => Hive.close();
}
