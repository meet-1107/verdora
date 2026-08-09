import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Sticky bottom action bar: live total on the left, a primary action on the
/// right (e.g. "Add to Cart"). Dumb widget.
class AppBottomOrderBar extends StatelessWidget {
  const AppBottomOrderBar({
    super.key,
    required this.totalLabel,
    required this.totalValue,
    required this.actionLabel,
    required this.onAction,
    this.enabled = true,
    this.loading = false,
  });

  final String totalLabel;
  final String totalValue;
  final String actionLabel;
  final VoidCallback onAction;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    totalLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    totalValue,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: (enabled && !loading) ? onAction : null,
                    icon: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_shopping_cart),
                    label: Text(actionLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
