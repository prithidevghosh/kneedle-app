import 'package:hive/hive.dart';

/// One-off appointment (e.g. doctor visit, physio session). Written by Gemma's
/// `add_appointment` function call; a single notification fires 1 hour before
/// the scheduled time.
class Appointment {
  Appointment({
    required this.id,
    required this.title,
    required this.when,
    required this.createdAt,
    this.location,
    this.notes,
  });

  final int id;
  final String title;
  final DateTime when;
  final DateTime createdAt;
  final String? location;
  final String? notes;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'when': when.toIso8601String(),
        'location': location,
        'notes': notes,
      };
}

class AppointmentAdapter extends TypeAdapter<Appointment> {
  @override
  final int typeId = 5;

  @override
  Appointment read(BinaryReader r) {
    final fields = r.readByte();
    final map = <int, dynamic>{
      for (var i = 0; i < fields; i++) r.readByte(): r.read(),
    };
    return Appointment(
      id: map[0] as int,
      title: map[1] as String,
      when: DateTime.fromMillisecondsSinceEpoch(map[2] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[3] as int),
      location: map[4] as String?,
      notes: map[5] as String?,
    );
  }

  @override
  void write(BinaryWriter w, Appointment obj) {
    w
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.when.millisecondsSinceEpoch)
      ..writeByte(3)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(4)
      ..write(obj.location)
      ..writeByte(5)
      ..write(obj.notes);
  }
}
