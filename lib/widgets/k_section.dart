import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Section header with optional eyebrow label and trailing action.
class KSectionTitle extends StatelessWidget {
  const KSectionTitle({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: KneedleTheme.space1),
              ],
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
