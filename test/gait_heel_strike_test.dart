import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kneedle/gait/heel_strike.dart';

void main() {
  test('detects synthetic sinusoidal heel strikes', () {
    // 5 cycles of a sin wave at ~1 Hz over 5 s, sampled at 30 fps.
    // Heel-strike events correspond to peaks → 5 expected events.
    const fps = 30.0;
    final ankleY = <double>[
      for (var i = 0; i < 150; i++)
        // Amplitude 0.04 (above 0.015 prominence floor) + slow trend.
        0.5 + 0.04 * math.sin(2 * math.pi * (i / fps)),
    ];
    final vis = List<double>.filled(150, 1.0);
    final peaks = detectHeelStrikes(ankleY, vis, sampleFps: fps);
    expect(peaks.length, inInclusiveRange(4, 6));
  });

  test('rejects flat / sub-prominence input', () {
    final flat = List<double>.filled(60, 0.5);
    final vis = List<double>.filled(60, 1.0);
    expect(detectHeelStrikes(flat, vis), isEmpty);
  });

  test('labelPhases yields no labels with <2 strikes', () {
    expect(labelPhases(50, [10]), isEmpty);
    expect(labelPhases(50, []), isEmpty);
  });

  test('labelPhases assigns loading_response right after a heel strike', () {
    final labels = labelPhases(40, [0, 30]);
    expect(labels[0], 'loading_response');
    // 10% of 30 = 3 → frame 3 should be mid_stance.
    expect(labels[3], 'mid_stance');
  });
}
