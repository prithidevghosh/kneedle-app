import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Circular pain-score dial: a soft sage→coral arc on a cream track.
/// Used in the home hero card and gait result. Tap-to-edit handled by parent.
class KPainDial extends StatelessWidget {
  const KPainDial({
    super.key,
    required this.score,
    this.size = 132,
    this.label = 'pain',
  });

  /// Score from 0–10. Null → unlogged ("—").
  final int? score;
  final double size;
  final String label;

  Color _colorFor(int s) {
    if (s <= 3) return KneedleTheme.success;
    if (s <= 6) return KneedleTheme.amber;
    return KneedleTheme.coral;
  }

  @override
  Widget build(BuildContext context) {
    final s = score;
    final pct = s == null ? 0.0 : (s / 10).clamp(0.0, 1.0);
    final color = s == null ? KneedleTheme.inkFaint : _colorFor(s);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DialPainter(progress: pct, color: color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s == null ? '—' : '$s',
                style: TextStyle(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  color: KneedleTheme.ink,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s == null ? 'no log' : '/10 $label',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: KneedleTheme.inkMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = KneedleTheme.hairlineSoft;

    // Track arc — leave a small gap at the bottom for a "scale" feel.
    const sweepTotal = math.pi * 1.5;
    const start = math.pi * 0.75;
    canvas.drawArc(rect, start, sweepTotal, false, track);

    if (progress > 0) {
      final fill = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweepTotal,
          colors: [color.withValues(alpha: 0.7), color],
        ).createShader(rect);
      canvas.drawArc(rect, start, sweepTotal * progress, false, fill);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.color != color;
}
