import 'package:hive/hive.dart';

import '../gait/pipeline.dart';

/// Persisted gait session — stores the patient-facing fields we need for
/// history charts and the doctor PDF. Raw landmark frames are NOT stored;
/// they're discarded once the pipeline returns its summary.
class GaitSession {
  GaitSession({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.klGrade,
    required this.klScore,
    required this.symmetryScore,
    required this.cadence,
    required this.confidence,
    required this.bilateralPattern,
    required this.clinicalFlags,
    required this.kneeAngleRight,
    required this.kneeAngleLeft,
    required this.rightStaticAlignmentDeviation,
    required this.leftStaticAlignmentDeviation,
    required this.doubleSupportRatio,
    required this.gaitSpeedProxy,
  });

  final int id;
  final DateTime timestamp;
  final String severity;
  final String klGrade;
  final double klScore;
  final double? symmetryScore;
  final double? cadence;
  final double confidence;
  final bool bilateralPattern;
  final List<String> clinicalFlags;
  final double? kneeAngleRight;
  final double? kneeAngleLeft;
  final double rightStaticAlignmentDeviation;
  final double leftStaticAlignmentDeviation;
  final double doubleSupportRatio;
  final double gaitSpeedProxy;

  factory GaitSession.fromMetrics(GaitMetrics m, {DateTime? at}) {
    final ts = at ?? DateTime.now();
    return GaitSession(
      id: ts.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff,
      timestamp: ts,
      severity: m.severity,
      klGrade: m.klProxyGrade,
      klScore: m.klProxyScore,
      symmetryScore: m.symmetryScore,
      cadence: m.cadence,
      confidence: m.confidence,
      bilateralPattern: m.bilateralPatternDetected,
      clinicalFlags: m.clinicalFlags,
      kneeAngleRight: m.kneeAngleRight,
      kneeAngleLeft: m.kneeAngleLeft,
      rightStaticAlignmentDeviation: m.rightStaticAlignmentDeviation,
      leftStaticAlignmentDeviation: m.leftStaticAlignmentDeviation,
      doubleSupportRatio: m.doubleSupportRatio,
      gaitSpeedProxy: m.gaitSpeedProxy,
    );
  }
}

class GaitSessionAdapter extends TypeAdapter<GaitSession> {
  @override
  final int typeId = 3;

  @override
  GaitSession read(BinaryReader r) {
    final fields = r.readByte();
    final map = <int, dynamic>{
      for (var i = 0; i < fields; i++) r.readByte(): r.read(),
    };
    return GaitSession(
      id: map[0] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map[1] as int),
      severity: map[2] as String,
      klGrade: map[3] as String,
      klScore: (map[4] as num).toDouble(),
      symmetryScore: (map[5] as num?)?.toDouble(),
      cadence: (map[6] as num?)?.toDouble(),
      confidence: (map[7] as num).toDouble(),
      bilateralPattern: map[8] as bool,
      clinicalFlags: (map[9] as List).cast<String>(),
      kneeAngleRight: (map[10] as num?)?.toDouble(),
      kneeAngleLeft: (map[11] as num?)?.toDouble(),
      rightStaticAlignmentDeviation: (map[12] as num).toDouble(),
      leftStaticAlignmentDeviation: (map[13] as num).toDouble(),
      doubleSupportRatio: (map[14] as num).toDouble(),
      gaitSpeedProxy: (map[15] as num).toDouble(),
    );
  }

  @override
  void write(BinaryWriter w, GaitSession obj) {
    w
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp.millisecondsSinceEpoch)
      ..writeByte(2)
      ..write(obj.severity)
      ..writeByte(3)
      ..write(obj.klGrade)
      ..writeByte(4)
      ..write(obj.klScore)
      ..writeByte(5)
      ..write(obj.symmetryScore)
      ..writeByte(6)
      ..write(obj.cadence)
      ..writeByte(7)
      ..write(obj.confidence)
      ..writeByte(8)
      ..write(obj.bilateralPattern)
      ..writeByte(9)
      ..write(obj.clinicalFlags)
      ..writeByte(10)
      ..write(obj.kneeAngleRight)
      ..writeByte(11)
      ..write(obj.kneeAngleLeft)
      ..writeByte(12)
      ..write(obj.rightStaticAlignmentDeviation)
      ..writeByte(13)
      ..write(obj.leftStaticAlignmentDeviation)
      ..writeByte(14)
      ..write(obj.doubleSupportRatio)
      ..writeByte(15)
      ..write(obj.gaitSpeedProxy);
  }
}
