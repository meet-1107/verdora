import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Large hero card summarising an order's current status, with a pulsing icon
/// for the live/current state. Dumb widget.
class AppHeroStatusCard extends StatefulWidget {
  const AppHeroStatusCard({
    super.key,
    required this.orderNumber,
    required this.statusLabel,
    required this.statusColor,
    required this.icon,
    required this.description,
    this.nextStep,
    this.lastUpdated,
    this.pulse = true,
  });

  final String orderNumber;
  final String statusLabel;
  final Color statusColor;
  final IconData icon;
  final String description;
  final String? nextStep;
  final String? lastUpdated;
  final bool pulse;

  @override
  State<AppHeroStatusCard> createState() => _AppHeroStatusCardState();
}

class _AppHeroStatusCardState extends State<AppHeroStatusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.orderNumber,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onPrimaryContainer)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FadeTransition(
                opacity: widget.pulse
                    ? Tween<double>(begin: 0.5, end: 1).animate(_c)
                    : const AlwaysStoppedAnimation(1),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: widget.statusColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: widget.statusColor, size: 28),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.statusLabel,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        )),
                    Text(widget.description,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onPrimaryContainer)),
                  ],
                ),
              ),
            ],
          ),
          if (widget.nextStep != null || widget.lastUpdated != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(color: scheme.onPrimaryContainer.withValues(alpha: 0.2)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (widget.nextStep != null)
                  Expanded(
                      child: _meta(theme, scheme, 'Next step', widget.nextStep!)),
                if (widget.lastUpdated != null)
                  Expanded(
                      child: _meta(
                          theme, scheme, 'Last updated', widget.lastUpdated!)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _meta(ThemeData theme, ColorScheme scheme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: scheme.onPrimaryContainer)),
      ],
    );
  }
}
