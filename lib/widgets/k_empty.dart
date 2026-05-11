import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Friendly empty state — soft sage circle holding an icon, headline, and
/// supporting copy. Used when a list has no entries yet.
class KEmptyState extends StatelessWidget {
  const KEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KneedleTheme.space7,
          vertical: KneedleTheme.space8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: KneedleTheme.sageTint,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 36, color: KneedleTheme.sageDeep),
            ),
            const SizedBox(height: KneedleTheme.space5),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KneedleTheme.space2),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: KneedleTheme.space5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
