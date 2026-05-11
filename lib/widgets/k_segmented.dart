import 'package:flutter/material.dart';

import '../core/theme.dart';

/// iOS-style pill segmented control. Easier to scan than tabs for older users.
class KSegmented extends StatelessWidget {
  const KSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KneedleTheme.creamWarm,
        borderRadius: BorderRadius.circular(KneedleTheme.radiusMd),
        border: Border.all(color: KneedleTheme.hairlineSoft),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? Colors.white : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(KneedleTheme.radiusSm - 2),
                    boxShadow: i == index ? KneedleTheme.shadowSoft : null,
                  ),
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      color: i == index
                          ? KneedleTheme.ink
                          : KneedleTheme.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
