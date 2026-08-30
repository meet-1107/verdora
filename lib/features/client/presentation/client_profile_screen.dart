import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_business_profile_card.dart';
import '../../../core/widgets/app_dashboard_card.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_support_card.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../orders/presentation/order_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import 'client_discounts_screen.dart';
import 'client_invoices_screen.dart';

/// Business Account Center — an enterprise account hub for dealers (not a
/// personal profile). Reads existing providers; no business logic changes.
class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final party = ref.watch(currentPartyProvider).valueOrNull;
    final orders = ref.watch(clientOrdersProvider).valueOrNull ?? const [];
    final settings = ref.watch(companySettingsProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);

    final invoices = orders.where((o) => o.invoiceNo != null).toList();
    final totalPurchase =
        invoices.fold<double>(0, (s, o) => s + o.grandTotal);
    final memberSince =
        party?.createdAt != null ? '${party!.createdAt!.year}' : '—';

    final name = party?.name.isNotEmpty == true
        ? party!.name
        : (user?.name ?? 'Business');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Business Profile'),
            Text('Manage your account',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.huge),
        children: [
          AppBusinessProfileCard(
            businessName: name,
            partyId: party?.partyCode ?? '—',
            ownerName: party?.ownerName,
            phone: party?.phone,
            email: party?.email ?? user?.email,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 118,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _stat(Icons.receipt_long_outlined, '${orders.length}', 'Orders',
                    AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                _stat(Icons.description_outlined, '${invoices.length}',
                    'Invoices', AppColors.info),
                const SizedBox(width: AppSpacing.md),
                _stat(Icons.account_balance_wallet_outlined,
                    Formatters.moneyCompact(totalPurchase), 'Purchase',
                    AppColors.success),
                const SizedBox(width: AppSpacing.md),
                _stat(Icons.calendar_today_outlined, memberSince,
                    'Member since', AppColors.warning),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Business ----
          const AppSectionHeader(title: '📦  Business'),
          _card(context, [
            _tile(context, Icons.receipt_long_outlined, 'Orders',
                () => context.go('/client/orders')),
            _tile(context, Icons.description_outlined, 'Invoices',
                () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ClientInvoicesScreen()))),
            _tile(context, Icons.percent_outlined, 'Discounts',
                () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ClientDiscountsScreen()))),
          ]),
          if (party != null) ...[
            const SizedBox(height: AppSpacing.md),
            _infoCard(context, 'Business information', {
              'Party ID': party.partyCode,
              if (party.gstNumber?.isNotEmpty == true)
                'GST': party.gstNumber!,
              if (party.paymentTerms?.isNotEmpty == true)
                'Payment terms': party.paymentTerms!,
              if (party.transport?.isNotEmpty == true)
                'Transport': party.transport!,
              if (party.defaultDiscount > 0)
                'Cash discount': '${party.defaultDiscount}%',
              'Registered': Formatters.date(party.createdAt),
            }),
            const SizedBox(height: AppSpacing.md),
            _addressCard(context, party.address, party.city, party.state,
                party.pincode),
          ],
          const SizedBox(height: AppSpacing.xl),

          // ---- Account ----
          const AppSectionHeader(title: '⚙️  Account'),
          _card(context, [
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/client/notifications'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _changePassword(context),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system, label: Text('System')),
                      ButtonSegment(
                          value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(
                          value: ThemeMode.dark, label: Text('Dark')),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) =>
                        ref.read(themeModeProvider.notifier).set(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Support ----
          const AppSectionHeader(title: '🤝  Support'),
          AppSupportCard(
            phone: settings?.supportNumber.isNotEmpty == true
                ? settings!.supportNumber
                : settings?.phone,
            email: settings?.email,
            onTapContact: (v) {
              Clipboard.setData(ClipboardData(text: v));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Copied: $v')));
            },
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- About ----
          const AppSectionHeader(title: 'ℹ️  About'),
          _card(context, [
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _info(context, 'Privacy policy',
                  'Your data is used only to process and manage your orders.'),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Terms & conditions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _info(context, 'Terms & conditions',
                  'Orders are subject to administrator approval and your '
                      'company\'s trading terms.'),
            ),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('App version'),
              trailing: Text('v0.1.0'),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // ---- Logout (danger zone) ----
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
            ),
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('Log out',
                  style: TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w600)),
              onTap: () => _logout(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) =>
      AppDashboardCard(
          width: 130,
          icon: icon,
          value: value,
          subtitle: label,
          color: color);

  Widget _card(BuildContext context, List<Widget> tiles) => Card(
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      );

  Widget _tile(
          BuildContext context, IconData icon, String title, VoidCallback onTap) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  Widget _infoCard(
      BuildContext context, String title, Map<String, String> rows) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final e in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    Flexible(
                      child: Text(e.value,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addressCard(BuildContext context, String? address, String? city,
      String? state, String? pincode) {
    final theme = Theme.of(context);
    final full = [address, city, state, pincode]
        .where((e) => e != null && e.isNotEmpty)
        .join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivery address',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(full.isEmpty ? 'No address on file' : full,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changePassword(BuildContext context) => _info(
        context,
        'Change password',
        'Accounts are managed by your company administrator. Please contact '
            'them to reset your password.',
      );

  void _info(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (!context.mounted) return;
      // Capture the router before the async gap; the profile widget is torn
      // down by the auth redirect during sign-out. Re-asserting /login on the
      // next frame guarantees the login screen even if the reactive redirect is
      // delayed on some platforms.
      final router = GoRouter.of(context);
      await ref.read(authRepositoryProvider).signOut();
      WidgetsBinding.instance.addPostFrameCallback((_) => router.go('/login'));
    }
  }
}
