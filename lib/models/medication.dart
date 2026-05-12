import 'package:hive/hive.dart';

/// Recurring medication reminder. Persisted by Gemma's `add_medication`
/// function call and surfaced on the Reminders screen. The notification id is
/// derived deterministically from `id` so we can cancel a daily schedule when
/// the user deletes the medication.
class Medication {
  Medication({
    required this.id,
    required this.name,
    required this.dose,
    required this.hour,
    required this.minute,
    required this.createdAt,
    this.notes,
  });

  final int id;
  final String name;
  final String dose;
  final int hour;
  final int minute;
  final DateTime createdAt;
  final String? notes;

  String get timeLabel {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'hour': hour,
        'minute': minute,
        'time': timeLabel,
        'notes': notes,
      };
}

class MedicationAdapter extends TypeAdapter<Medication> {
  @override
  final int typeId = 4;

  @override
  Medication read(BinaryReader r) {
    final fields = r.readByte();
    final map = <int, dynamic>{
      for (var i = 0; i < fields; i++) r.readByte(): r.read(),
    };
    return Medication(
      id: map[0] as int,
      name: map[1] as String,
      dose: map[2] as String,
      hour: map[3] as int,
      minute: map[4] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[5] as int),
      notes: map[6] as String?,
    );
  }

  @override
  void write(BinaryWriter w, Medication obj) {
    w
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.dose)
      ..writeByte(3)
      ..write(obj.hour)
      ..writeByte(4)
      ..write(obj.minute)
      ..writeByte(5)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(6)
      ..write(obj.notes);
  }
}
