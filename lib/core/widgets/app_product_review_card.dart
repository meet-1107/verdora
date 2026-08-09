import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_category_image.dart';

/// A compact, read-only product line for the checkout/order review page.
class AppProductReviewCard extends StatelessWidget {
  const AppProductReviewCard({
    super.key,
    required this.name,
    required this.variantLabel,
    required this.quantity,
    required this.rate,
    required this.total,
    this.imageUrl,
    this.discount,
  });

  final String name;
  final String variantLabel;
  final String quantity;
  final String rate;
  final String total;
  final String? imageUrl;
  final String? discount; // e.g. "5%"

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCategoryImage(
                imageUrl: imageUrl, size: 52, icon: Icons.inventory_2_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    '$variantLabel · $rate'
                    '${discount != null ? ' · $discount off' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text('Qty: $quantity',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(total,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
