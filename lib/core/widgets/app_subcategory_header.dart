import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_category_image.dart';

/// Header block for a drill-down screen: large image + name + optional
/// description + a stats row. Reusable for category/subcategory contexts.
class AppSubcategoryHeader extends StatelessWidget {
  const AppSubcategoryHeader({
    super.key,
    required this.name,
    required this.stats,
    this.imageUrl,
    this.description,
    this.icon = Icons.category_outlined,
  });

  final String name;

  /// (value, label) pairs, e.g. ("4", "Subcategories").
  final List<(String, String)> stats;
  final String? imageUrl;
  final String? description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppCategoryImage(imageUrl: imageUrl, size: 64, icon: icon),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontSize: 22),
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                for (final s in stats) ...[
                  _stat(theme, s.$1, s.$2),
                  if (s != stats.last)
                    Container(
                      height: 28,
                      width: 1,
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      color: scheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(ThemeData theme, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
