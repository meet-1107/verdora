import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Pricing breakdown for the selected variant: rate, discount, final price,
/// pack and box pack. Dumb widget — pass preformatted strings.
class AppPricingCard extends StatelessWidget {
  const AppPricingCard({
    super.key,
    required this.rate,
    required this.finalPrice,
    this.discount,
    this.pack,
    this.boxPack,
  });

  final String rate;
  final String finalPrice;
  final String? discount; // e.g. "5%"
  final String? pack;
  final String? boxPack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            _row(theme, 'Rate', rate),
            if (discount != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _row(theme, 'Discount', discount!, valueColor: scheme.primary),
            ],
            const Divider(height: AppSpacing.xxl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Final price', style: theme.textTheme.titleMedium),
                Text(
                  finalPrice,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (pack != null || boxPack != null) ...[
              const Divider(height: AppSpacing.xxl),
              Row(
                children: [
                  if (pack != null)
                    Expanded(child: _stat(theme, 'Pack', pack!)),
                  if (boxPack != null)
                    Expanded(child: _stat(theme, 'Box pack', boxPack!)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value,
      {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(color: valueColor)),
      ],
    );
  }

  Widget _stat(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
