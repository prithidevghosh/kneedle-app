import 'package:hive/hive.dart';

class ExerciseSession {
  ExerciseSession({
    required this.id,
    required this.exerciseName,
    required this.repsCompleted,
    required this.durationSec,
    required this.timestamp,
    this.notes,
  });

  final int id;
  final String exerciseName;
  final int repsCompleted;
  final int durationSec;
  final DateTime timestamp;
  final String? notes;
}

class ExerciseSessionAdapter extends TypeAdapter<ExerciseSession> {
  @override
  final int typeId = 2;

  @override
  ExerciseSession read(BinaryReader r) {
    final fields = r.readByte();
    final map = <int, dynamic>{
      for (var i = 0; i < fields; i++) r.readByte(): r.read(),
    };
    return ExerciseSession(
      id: map[0] as int,
      exerciseName: map[1] as String,
      repsCompleted: map[2] as int,
      durationSec: map[3] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map[4] as int),
      notes: map[5] as String?,
    );
  }

  @override
  void write(BinaryWriter w, ExerciseSession obj) {
    w
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.exerciseName)
      ..writeByte(2)
      ..write(obj.repsCompleted)
      ..writeByte(3)
      ..write(obj.durationSec)
      ..writeByte(4)
      ..write(obj.timestamp.millisecondsSinceEpoch)
      ..writeByte(5)
      ..write(obj.notes);
  }
}
