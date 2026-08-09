import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Delivery / party information card for order review. Dumb widget.
class AppDeliveryCard extends StatelessWidget {
  const AppDeliveryCard({
    super.key,
    required this.partyName,
    this.address,
    this.phone,
    this.transport,
    this.onEdit,
  });

  final String partyName;
  final String? address;
  final String? phone;
  final String? transport;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Delivery information',
                      style: theme.textTheme.titleMedium),
                ),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(partyName,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (address != null && address!.isNotEmpty)
              _line(theme, Icons.location_on_outlined, address!),
            if (phone != null && phone!.isNotEmpty)
              _line(theme, Icons.phone_outlined, phone!),
            if (transport != null && transport!.isNotEmpty)
              _line(theme, Icons.local_shipping_outlined, transport!),
          ],
        ),
      ),
    );
  }

  Widget _line(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
