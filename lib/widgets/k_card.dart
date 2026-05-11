import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Soft, hairline-bordered surface used as the base container throughout
/// Kneedle. Defaults to white; `tone` swaps in tinted variants.
enum KCardTone { plain, sage, coral, amber, danger, ink }

class KCard extends StatelessWidget {
  const KCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KneedleTheme.space5),
    this.tone = KCardTone.plain,
    this.onTap,
    this.borderless = false,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final KCardTone tone;
  final VoidCallback? onTap;
  final bool borderless;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (tone) {
      KCardTone.plain => (KneedleTheme.surface, KneedleTheme.hairline),
      KCardTone.sage => (KneedleTheme.sageTint, Colors.transparent),
      KCardTone.coral => (KneedleTheme.coralTint, Colors.transparent),
      KCardTone.amber => (KneedleTheme.amberTint, Colors.transparent),
      KCardTone.danger => (KneedleTheme.dangerTint, Colors.transparent),
      KCardTone.ink => (KneedleTheme.ink, Colors.transparent),
    };

    final radius = BorderRadius.circular(KneedleTheme.radiusLg);
    final decoration = BoxDecoration(
      color: bg,
      borderRadius: radius,
      border: borderless
          ? null
          : Border.all(color: border, width: 1),
      boxShadow: elevated ? KneedleTheme.shadowSoft : null,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: KneedleTheme.sageTint.withValues(alpha: 0.6),
        highlightColor: KneedleTheme.sageSoft,
        child: Ink(
          decoration: decoration.copyWith(color: Colors.transparent),
          child: content,
        ),
      ),
    );
  }
}
