import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A compact horizontal progress timeline for an order's lifecycle:
/// Pending → Approved → Packing → Dispatched (final). Terminal negative
/// states (cancelled/rejected) render as a single red indicator.
/// Takes the order-status string value so it stays independent of the enum.
class AppOrderTimeline extends StatelessWidget {
  const AppOrderTimeline({super.key, required this.statusValue});

  final String statusValue;

  static const _steps = ['Pending', 'Approved', 'Packing', 'Dispatched'];

  static const _stepOf = {
    'pending': 0,
    'approved': 1,
    'packing': 2,
    'packed': 2,
    'dispatched': 3,
    // Legacy orders that reached these states show as fully dispatched.
    'delivered': 3,
    'completed': 3,
  };

  bool get _isNegative =>
      statusValue == 'cancelled' ||
      statusValue == 'rejected' ||
      statusValue == 'returned';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isNegative) {
      return Row(
        children: [
          const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
          const SizedBox(width: 6),
          Text(
            statusValue[0].toUpperCase() + statusValue.substring(1),
            style: const TextStyle(
                color: AppColors.error,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    final active = _stepOf[statusValue] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              _dot(scheme, i <= active, i == active),
              if (i < _steps.length - 1)
                Expanded(
                  child: Container(
                    height: 3,
                    color: i < active
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _steps[active],
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _dot(ColorScheme scheme, bool filled, bool current) {
    final size = current ? 14.0 : 11.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? scheme.primary : scheme.surface,
        border: Border.all(
          color: filled ? scheme.primary : scheme.outlineVariant,
          width: 2,
        ),
      ),
    );
  }
}
