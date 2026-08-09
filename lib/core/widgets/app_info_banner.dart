import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A tinted informational banner (icon + title + optional message). Used for
/// review headers, savings notices, offline notices, etc.
class AppInfoBanner extends StatelessWidget {
  const AppInfoBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.message,
  });

  final IconData icon;
  final String title;
  final Color color;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
