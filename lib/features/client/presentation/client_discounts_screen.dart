import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/state_views.dart';
import '../../discounts/presentation/discount_structure_view.dart';
import '../../parties/presentation/party_providers.dart';

/// The dealer's own discount structure — cash (global) + category / subcategory
/// / product discounts. Opened from the Profile → Business → Discounts tile.
class ClientDiscountsScreen extends ConsumerWidget {
  const ClientDiscountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(orderPartyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your Discounts'),
            Text('Applied to your orders',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: party == null
          ? const EmptyView(
              message: 'No discounts available yet.',
              icon: Icons.percent_outlined,
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                DiscountStructureView(
                  partyId: party.id,
                  globalPercent: party.defaultDiscount,
                ),
              ],
            ),
    );
  }
}
