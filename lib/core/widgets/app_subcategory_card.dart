import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_category_image.dart';

/// A subcategory list row: image, name, product count, chevron. Dumb widget.
class AppSubcategoryCard extends StatelessWidget {
  const AppSubcategoryCard({
    super.key,
    required this.name,
    required this.productCount,
    this.imageUrl,
    this.onTap,
    this.onLongPress,
  });

  final String name;
  final int productCount;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              AppCategoryImage(
                imageUrl: imageUrl,
                size: 72,
                icon: Icons.account_tree_outlined,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      productCount == 1 ? '1 product' : '$productCount products',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
