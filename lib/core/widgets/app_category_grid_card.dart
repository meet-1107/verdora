import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_category_image.dart';

/// A grid tile for a category: centered image, name (max 2 lines), product
/// count, and a subtle navigation arrow. Tap opens products; long-press exposes
/// quick options. Dumb widget — pass display values.
class AppCategoryGridCard extends StatelessWidget {
  const AppCategoryGridCard({
    super.key,
    required this.name,
    required this.productCount,
    this.imageUrl,
    this.favorite = false,
    this.onTap,
    this.onLongPress,
  });

  final String name;
  final int productCount;
  final String? imageUrl;
  final bool favorite;
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
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: AppSpacing.xs),
                  AppCategoryImage(imageUrl: imageUrl, size: 92),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
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
            if (favorite)
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.sm,
                child: Icon(Icons.star, size: 18, color: scheme.primary),
              ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
