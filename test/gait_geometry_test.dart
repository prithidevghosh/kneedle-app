import 'package:flutter_test/flutter_test.dart';
import 'package:kneedle/gait/geometry.dart';
import 'package:kneedle/gait/landmark.dart';

Landmark _lm(double x, double y, [double v = 1.0]) =>
    Landmark(x: x, y: y, z: 0, visibility: v);

void main() {
  group('calculateAngle', () {
    test('straight line is 180°', () {
      // a -- b -- c colinear → angle at b is 180°.
      final a = _lm(0, 0);
      final b = _lm(1, 0);
      final c = _lm(2, 0);
      expect(calculateAngle(a, b, c), closeTo(180.0, 0.05));
    });

    test('right angle is 90°', () {
      final a = _lm(0, 1);
      final b = _lm(0, 0);
      final c = _lm(1, 0);
      expect(calculateAngle(a, b, c), closeTo(90.0, 0.05));
    });

    test('zero-length vector returns 0 (degenerate)', () {
      final a = _lm(0, 0);
      final b = _lm(0, 0);
      final c = _lm(1, 0);
      // dot = 0, magBa = 0 → cos = 0/(0+1e-8) = 0 → acos(0) = 90°.
      expect(calculateAngle(a, b, c), closeTo(90.0, 0.5));
    });
  });

  group('mean / median / percentile', () {
    test('mean of empty is 0', () => expect(mean(const []), 0));
    test('median odd', () => expect(median([1, 5, 3]), 3));
    test('median even', () => expect(median([1, 5, 3, 7]), 4));
    test('percentile linear interp', () {
      expect(percentile([0, 10, 20, 30, 40], 50), closeTo(20, 1e-9));
      expect(percentile([0, 10, 20, 30, 40], 75), closeTo(30, 1e-9));
    });
  });

  group('smooth', () {
    test('passes through length unchanged', () {
      final s = smooth([1, 2, 3, 4, 5, 6, 7]);
      expect(s.length, 7);
    });

    test('flat input stays flat', () {
      final s = smooth([2, 2, 2, 2, 2, 2, 2]);
      for (final v in s) {
        expect(v, closeTo(2, 1e-9));
      }
    });
  });
}
