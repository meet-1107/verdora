import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A compact metric card (pending orders, revenue, etc.). Colour-accented icon
/// tile + large value + subtitle. Fixed width so several scroll horizontally.
class AppDashboardCard extends StatelessWidget {
  const AppDashboardCard({
    super.key,
    required this.icon,
    required this.value,
    required this.subtitle,
    required this.color,
    this.width = 160,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String subtitle;
  final Color color;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: AppSpacing.md),
                // Scale the value down to fit the card width so the whole
                // number shows (e.g. ₹18,30,556.80) instead of being clipped.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
