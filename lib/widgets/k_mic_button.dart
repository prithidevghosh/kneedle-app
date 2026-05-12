import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Visual states for [KMicButton]:
///  * `idle` — sage gradient, mic icon. Tap to start listening.
///  * `listening` — coral gradient, breathing rings. Tap to stop.
///  * `processing` — muted ink gradient, spinner. Tap is a no-op.
enum KMicState { idle, listening, processing }

/// Large circular mic button that gently "breathes" while listening, and
/// shows a spinner while the model is thinking.
class KMicButton extends StatefulWidget {
  const KMicButton({
    super.key,
    required this.state,
    required this.onTap,
    this.size = 132,
  });

  final KMicState state;
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

  bool get _listening => widget.state == KMicState.listening;
  bool get _processing => widget.state == KMicState.processing;

  @override
  void initState() {
    super.initState();
    if (_listening) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant KMicButton old) {
    super.didUpdateWidget(old);
    if (_listening && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!_listening && _c.isAnimating) {
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
      onTap: _processing ? null : widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(_c.value);
          final color = _listening
              ? KneedleTheme.coral
              : _processing
                  ? KneedleTheme.inkMuted
                  : KneedleTheme.sage;
          final gradient = _listening
              ? const [KneedleTheme.coral, Color(0xFFB45A3D)]
              : _processing
                  ? const [KneedleTheme.inkMuted, KneedleTheme.ink]
                  : const [KneedleTheme.sage, KneedleTheme.sageDeep];
          return SizedBox(
            width: widget.size + 60,
            height: widget.size + 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_listening) ...[
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
                      colors: gradient,
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
                  child: _processing
                      ? SizedBox(
                          width: widget.size * 0.42,
                          height: widget.size * 0.42,
                          child: const CircularProgressIndicator(
                            strokeWidth: 3.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(
                          _listening
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
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
