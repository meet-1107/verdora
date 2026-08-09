import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Hero card for the business account center: monogram, business name, party
/// id, a "verified" status badge and key contact rows. Dumb widget.
class AppBusinessProfileCard extends StatelessWidget {
  const AppBusinessProfileCard({
    super.key,
    required this.businessName,
    required this.partyId,
    this.ownerName,
    this.phone,
    this.email,
    this.statusLabel = 'Verified dealer',
  });

  final String businessName;
  final String partyId;
  final String? ownerName;
  final String? phone;
  final String? email;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial =
        businessName.isNotEmpty ? businessName[0].toUpperCase() : '?';
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
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: scheme.primary,
                child: Text(initial,
                    style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 24)),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(businessName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 22)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified,
                              size: 14, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text(statusLabel,
                              style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _row(theme, scheme, Icons.badge_outlined, 'Party ID', partyId),
          if (ownerName != null && ownerName!.isNotEmpty)
            _row(theme, scheme, Icons.person_outline, 'Owner', ownerName!),
          if (phone != null && phone!.isNotEmpty)
            _row(theme, scheme, Icons.phone_outlined, 'Phone', phone!),
          if (email != null && email!.isNotEmpty)
            _row(theme, scheme, Icons.email_outlined, 'Email', email!),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, ColorScheme scheme, IconData icon, String label,
      String value) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
          const SizedBox(width: AppSpacing.sm),
          Text('$label:  ',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
