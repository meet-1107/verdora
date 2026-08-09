import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A compact "recently ordered" card for one-tap reordering: product name,
/// variant, price and an Add button. Dumb widget.
class AppReorderCard extends StatelessWidget {
  const AppReorderCard({
    super.key,
    required this.productName,
    required this.variantLabel,
    required this.price,
    required this.onAdd,
    this.onTap,
    this.width = 190,
  });

  final String productName;
  final String variantLabel;
  final String price;
  final VoidCallback onAdd;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  variantLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        price,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 34,
                      child: FilledButton(
                        onPressed: onAdd,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        child: const Text('Add'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
