import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Client-facing stock status. Clients see STATUS only, never quantities.
enum StockStatus {
  inStock('In stock', AppColors.success),
  lowStock('Low stock', AppColors.warning),
  outOfStock('Out of stock', AppColors.error),
  comingSoon('Coming soon', AppColors.hint);

  const StockStatus(this.label, this.color);
  final String label;
  final Color color;
}

/// A small pill showing stock status with a colour dot.
class AppStockBadge extends StatelessWidget {
  const AppStockBadge({super.key, required this.status, this.compact = false});

  final StockStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: status.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
