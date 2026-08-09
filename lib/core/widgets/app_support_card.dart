import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// "Need help?" support card with contact rows. Owners provide the contact
/// values and tap handlers (e.g. copy / launch dialer).
class AppSupportCard extends StatelessWidget {
  const AppSupportCard({
    super.key,
    this.phone,
    this.whatsapp,
    this.email,
    this.onTapContact,
  });

  final String? phone;
  final String? whatsapp;
  final String? email;
  final void Function(String value)? onTapContact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Need help?', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text('Contact your company for order assistance.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            if (phone != null && phone!.isNotEmpty)
              _row(context, Icons.call_outlined, 'Call', phone!),
            if (whatsapp != null && whatsapp!.isNotEmpty)
              _row(context, Icons.chat_outlined, 'WhatsApp', whatsapp!),
            if (email != null && email!.isNotEmpty)
              _row(context, Icons.email_outlined, 'Email', email!),
            if ((phone == null || phone!.isEmpty) &&
                (whatsapp == null || whatsapp!.isEmpty) &&
                (email == null || email!.isEmpty))
              Text('No support contact configured.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      trailing: const Icon(Icons.copy, size: 18),
      onTap: onTapContact == null ? null : () => onTapContact!(value),
    );
  }
}
