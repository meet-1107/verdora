import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Order totals breakdown card: a list of (label, value) rows plus an
/// emphasised grand total. Dumb widget — pass preformatted strings.
class AppOrderTotalsCard extends StatelessWidget {
  const AppOrderTotalsCard({
    super.key,
    required this.rows,
    required this.grandTotalLabel,
    required this.grandTotalValue,
  });

  /// (label, value) breakdown lines, e.g. ("Subtotal", "₹50,000").
  final List<(String, String)> rows;
  final String grandTotalLabel;
  final String grandTotalValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            for (final r in rows) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.$1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                  Text(r.$2, style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            const Divider(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(grandTotalLabel, style: theme.textTheme.titleMedium),
                Text(
                  grandTotalValue,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
