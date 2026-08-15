import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_reorder_card.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../parties/presentation/party_providers.dart';
import '../application/cart_provider.dart';
import '../application/reorder_provider.dart';

/// "Recently ordered" one-tap reorder strip. Self-contained: reads the client's
/// frequently-ordered variants and adds them straight to the cart. Renders
/// nothing when there is no order history (so screens can include it freely).
class QuickReorderSection extends ConsumerWidget {
  const QuickReorderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(frequentlyOrderedProvider).valueOrNull ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();

    final discount =
        ref.watch(orderPartyProvider)?.defaultDiscount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'Recently ordered'),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) {
              final it = items[i];
              return AppReorderCard(
                productName: it.productName,
                variantLabel: it.variantLabel,
                price: Formatters.money(it.rate),
                onAdd: () {
                  ref.read(cartProvider.notifier).addVariant(
                        variantId: it.variantId,
                        productName: it.productName,
                        variantLabel: it.variantLabel,
                        rate: it.rate,
                        qty: 1,
                        discountPercent: discount,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added ${it.productName}')),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}
