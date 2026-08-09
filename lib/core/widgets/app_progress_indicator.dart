import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A labelled linear progress bar for order progress (0..1) with a percentage
/// and current-stage caption.
class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({
    super.key,
    required this.progress,
    required this.stageLabel,
    this.caption,
  });

  final double progress; // 0..1
  final String stageLabel;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order progress', style: theme.textTheme.titleMedium),
                Text('${(progress * 100).round()}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0, 1)),
                duration: const Duration(milliseconds: 600),
                builder: (context, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(stageLabel,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (caption != null)
              Text(caption!,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
