import 'dart:math' as math;

import 'landmark.dart';

double _round1(double v) => (v * 10).roundToDouble() / 10;
double _round2(double v) => (v * 100).roundToDouble() / 100;
double _round3(double v) => (v * 1000).roundToDouble() / 1000;

/// Round helpers exposed for downstream (matches Python `round(_, n)`).
class Round {
  Round._();
  static double r1(double v) => _round1(v);
  static double r2(double v) => _round2(v);
  static double r3(double v) => _round3(v);
}

/// Angle at B in degrees (0–180) given three landmarks.
///
/// 2D image-plane only (x, y). MediaPipe single-camera z is too noisy for
/// clinical angle math — including it produces impossible joint angles.
double calculateAngle(Landmark a, Landmark b, Landmark c) {
  final bax = a.x - b.x;
  final bay = a.y - b.y;
  final bcx = c.x - b.x;
  final bcy = c.y - b.y;
  final dot = bax * bcx + bay * bcy;
  final magBa = math.sqrt(bax * bax + bay * bay);
  final magBc = math.sqrt(bcx * bcx + bcy * bcy);
  final cos = dot / (magBa * magBc + 1e-8);
  final clamped = cos.clamp(-1.0, 1.0);
  return _round1(math.acos(clamped) * 180.0 / math.pi);
}

/// Toe-out angle. Mirrors Python's `atan2(ankle.x - heel.x, ankle.y - heel.y)`.
double calculateToeOutAngle(Landmark ankle, Landmark heel) {
  return _round1(
    math.atan2(ankle.x - heel.x, ankle.y - heel.y) * 180.0 / math.pi,
  );
}

double? safeMean(List<double> values) {
  if (values.isEmpty) return null;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return _round1(sum / values.length);
}

/// Centred moving average. Edge-padded so output length == input length.
List<double> smooth(List<double> series, {int window = 5}) {
  if (series.length < window) return List<double>.from(series);
  final half = window ~/ 2;
  final padded = <double>[
    for (var i = 0; i < half; i++) series.first,
    ...series,
    for (var i = 0; i < half; i++) series.last,
  ];
  final out = List<double>.filled(series.length, 0);
  for (var i = 0; i < series.length; i++) {
    var sum = 0.0;
    for (var j = 0; j < window; j++) {
      sum += padded[i + j];
    }
    out[i] = sum / window;
  }
  return out;
}

double mean(List<double> values) {
  if (values.isEmpty) return 0;
  var s = 0.0;
  for (final v in values) {
    s += v;
  }
  return s / values.length;
}

double median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.from(values)..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// Linear-interpolated percentile, matches numpy's default.
double percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.from(values)..sort();
  final rank = p / 100 * (sorted.length - 1);
  final lo = rank.floor();
  final hi = rank.ceil();
  if (lo == hi) return sorted[lo];
  final frac = rank - lo;
  return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
}
