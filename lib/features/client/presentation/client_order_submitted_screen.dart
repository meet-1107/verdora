import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Confirmation screen after a purchase order is submitted.
class ClientOrderSubmittedScreen extends StatelessWidget {
  const ClientOrderSubmittedScreen({super.key, required this.reference});

  /// A short reference for the submitted order (its document id).
  final String reference;

  void _home(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _track(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    context.go('/client/orders');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                builder: (context, t, child) =>
                    Transform.scale(scale: t, child: child),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      color: AppColors.success, size: 64),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Order submitted successfully',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your purchase order has been sent to your administrator for '
                'review and approval.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                    'Reference: ${reference.substring(0, reference.length < 8 ? reference.length : 8)}',
                    style: theme.textTheme.bodySmall),
              ),
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _track(context),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Track Order'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _home(context),
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
