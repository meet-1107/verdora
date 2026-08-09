import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_category_image.dart';
import 'app_stock_badge.dart';

/// A B2B product row optimised for fast scanning and ordering. Two layouts:
///  * full (default): image + full name (one auto-shrinking line) + sizes.
///  * compact (Quick Order Mode): name + sizes + a "+" that fires [onQuickAdd].
/// A green tick marks products already in the cart. Dumb widget.
class AppProductCard extends StatelessWidget {
  const AppProductCard({
    super.key,
    required this.name,
    required this.variantCount,
    required this.stock,
    this.imageUrl,
    this.description,
    this.onTap,
    this.onQuickAdd,
    this.compact = false,
    this.inCart = false,
  });

  final String name;
  final int variantCount;
  final StockStatus stock; // kept for API compatibility (no longer shown)
  final String? imageUrl;
  final String? description;
  final VoidCallback? onTap;
  final VoidCallback? onQuickAdd;
  final bool compact;

  /// True when at least one of this product's sizes is already in the cart —
  /// renders a green tick so the dealer knows it's added.
  final bool inCart;

  static const _green = Color(0xFF16A34A);

  String get _variantText =>
      variantCount == 1 ? '1 size' : '$variantCount sizes';

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildFull(context);
  }

  RoundedRectangleBorder get _shape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: inCart
            ? const BorderSide(color: _green, width: 1.5)
            : BorderSide.none,
      );

  Widget _thumb(BuildContext context, double size) => Stack(
        clipBehavior: Clip.none,
        children: [
          AppCategoryImage(
            imageUrl: imageUrl,
            size: size,
            icon: Icons.inventory_2_outlined,
          ),
          if (inCart)
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: _green, size: 22),
              ),
            ),
        ],
      );

  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: _shape,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              _thumb(context, 88),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Full product name on ONE line — auto-shrinks if long,
                    // never truncated.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          maxLines: 1,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _variantText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: _shape,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (inCart) ...[
                          const Icon(Icons.check_circle, color: _green, size: 16),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                name,
                                maxLines: 1,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _variantText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton.filled(
                tooltip: 'Quick add',
                onPressed: onQuickAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
