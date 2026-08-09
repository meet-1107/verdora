import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum TimelineState { done, current, future }

/// A single node in a vertical order-progress timeline: a status dot + a
/// connector line, with title/description/date/updated-by content.
class AppTimelineStep extends StatelessWidget {
  const AppTimelineStep({
    super.key,
    required this.title,
    required this.state,
    required this.isLast,
    this.description,
    this.timestamp,
    this.updatedBy,
  });

  final String title;
  final TimelineState state;
  final bool isLast;
  final String? description;
  final String? timestamp;
  final String? updatedBy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = state == TimelineState.done;
    final current = state == TimelineState.current;
    final activeColor = current ? AppColors.info : AppColors.success;
    final color = (done || current) ? activeColor : scheme.outlineVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (done || current) ? color : scheme.surface,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(
                  done
                      ? Icons.check
                      : current
                          ? Icons.autorenew
                          : Icons.circle,
                  size: done || current ? 15 : 8,
                  color: (done || current)
                      ? Colors.white
                      : scheme.outlineVariant,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? AppColors.success : scheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        color: (done || current)
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      )),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(description!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ],
                  if (timestamp != null || updatedBy != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (timestamp != null)
                          Text(timestamp!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        if (updatedBy != null) ...[
                          if (timestamp != null)
                            Text('  ·  ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant)),
                          Text(updatedBy!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
