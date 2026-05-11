import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Large circular mic button that gently "breathes" while listening.
class KMicButton extends StatefulWidget {
  const KMicButton({
    super.key,
    required this.listening,
    required this.onTap,
    this.size = 132,
  });

  final bool listening;
  final VoidCallback onTap;
  final double size;

  @override
  State<KMicButton> createState() => _KMicButtonState();
}

class _KMicButtonState extends State<KMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.listening) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant KMicButton old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.listening && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(_c.value);
          final color =
              widget.listening ? KneedleTheme.coral : KneedleTheme.sage;
          return SizedBox(
            width: widget.size + 60,
            height: widget.size + 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.listening) ...[
                  _ring(widget.size + 24 + t * 30,
                      color.withValues(alpha: 0.10 * (1 - t))),
                  _ring(widget.size + 8 + t * 24,
                      color.withValues(alpha: 0.18 * (1 - t * 0.6))),
                ],
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.listening
                          ? const [KneedleTheme.coral, Color(0xFFB45A3D)]
                          : const [KneedleTheme.sage, KneedleTheme.sageDeep],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.listening ? Icons.graphic_eq : Icons.mic_rounded,
                    color: Colors.white,
                    size: widget.size * 0.36,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      );
}
