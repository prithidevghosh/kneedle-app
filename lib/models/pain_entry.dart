import 'package:hive/hive.dart';

/// Pain journal entry — written by Gemma function-call `record_pain_entry`,
/// or directly from the journal screen's manual form.
class PainEntry {
  PainEntry({
    required this.id,
    required this.painScore,
    required this.location,
    required this.context,
    required this.timestamp,
    this.transcript,
  });

  /// Stable id (millis-since-epoch) — used as Hive key.
  final int id;

  /// 0-10 numeric pain rating.
  final int painScore;

  /// Free-text body location, e.g. "right knee, inner side".
  final String location;

  /// Trigger / activity / time-of-day context.
  final String context;

  final DateTime timestamp;

  /// Original voice transcript when the entry came from the voice flow.
  /// Null for manual entries.
  final String? transcript;

  Map<String, Object?> toJson() => {
        'id': id,
        'pain_score': painScore,
        'location': location,
        'context': context,
        'timestamp': timestamp.toIso8601String(),
        'transcript': transcript,
      };
}

class PainEntryAdapter extends TypeAdapter<PainEntry> {
  @override
  final int typeId = 1;

  @override
  PainEntry read(BinaryReader r) {
    final fields = r.readByte();
    final map = <int, dynamic>{
      for (var i = 0; i < fields; i++) r.readByte(): r.read(),
    };
    return PainEntry(
      id: map[0] as int,
      painScore: map[1] as int,
      location: map[2] as String,
      context: map[3] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map[4] as int),
      transcript: map[5] as String?,
    );
  }

  @override
  void write(BinaryWriter w, PainEntry obj) {
    w
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.painScore)
      ..writeByte(2)
      ..write(obj.location)
      ..writeByte(3)
      ..write(obj.context)
      ..writeByte(4)
      ..write(obj.timestamp.millisecondsSinceEpoch)
      ..writeByte(5)
      ..write(obj.transcript);
  }
}
