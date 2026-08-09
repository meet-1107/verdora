import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_category_image.dart';
import 'app_stock_badge.dart';

/// Product header for the order-configuration screen: image + name + category
/// path + SKU + stock badge + variant count. Dumb widget.
class AppProductHeader extends StatelessWidget {
  const AppProductHeader({
    super.key,
    required this.name,
    required this.stock,
    required this.variantCount,
    this.imageUrl,
    this.categoryPath,
    this.sku,
  });

  final String name;
  final StockStatus stock;
  final int variantCount;
  final String? imageUrl;
  final String? categoryPath;
  final String? sku;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCategoryImage(
            imageUrl: imageUrl,
            size: 96,
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                ),
                if (categoryPath != null && categoryPath!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    categoryPath!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (sku != null && sku!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'SKU: $sku',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    AppStockBadge(status: stock, compact: true),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        variantCount == 1
                            ? '1 size'
                            : '$variantCount sizes',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
