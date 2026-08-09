import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A compact summary card with several (value, label) stats, e.g.
/// "128 Products · 452 Variants · 12 Ordered this month".
class AppProductSummary extends StatelessWidget {
  const AppProductSummary({super.key, required this.stats});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final s in stats) ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.$1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    s.$2,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (s != stats.last)
                Container(
                  height: 34,
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
