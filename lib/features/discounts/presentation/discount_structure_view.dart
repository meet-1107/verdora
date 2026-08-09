import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subcategories/presentation/subcategory_providers.dart';
import '../domain/discount.dart';
import 'discount_providers.dart';

/// Shows a dealer's discount structure — the global baseline plus any
/// category / subcategory / product rules (product rules only appear for the
/// products that actually have one). Used on the admin dealer detail and the
/// client profile so both sides see the same picture.
class DiscountStructureView extends ConsumerWidget {
  const DiscountStructureView({
    super.key,
    required this.partyId,
    required this.globalPercent,
    this.showGlobal = true,
  });

  final String partyId;
  final double globalPercent;
  final bool showGlobal;

  static String _num(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = (ref.watch(discountsProvider).valueOrNull ?? const <Discount>[])
        .where((d) => d.partyId == partyId && d.isActive)
        .toList();

    List<Discount> of(DiscountScope s) {
      final list = rules.where((d) => d.scope == s).toList()
        ..sort((a, b) => (a.targetLabel ?? '')
            .toLowerCase()
            .compareTo((b.targetLabel ?? '').toLowerCase()));
      return list;
    }

    // Map each subcategory to its parent category so we can hide a category's
    // discount when one of its subcategories has its own (more specific) rule.
    final subcats = ref.watch(subcategoriesProvider).valueOrNull ?? const [];
    final subToCategory = {for (final s in subcats) s.id: s.categoryId};

    final subs = of(DiscountScope.subcategory);
    final categoriesWithSubRule = subs
        .map((d) => subToCategory[d.targetId])
        .whereType<String>()
        .toSet();
    final cats = of(DiscountScope.category)
        .where((d) => !categoriesWithSubRule.contains(d.targetId))
        .toList();
    final prods = of(DiscountScope.product);

    final hasSpecific = cats.isNotEmpty || subs.isNotEmpty || prods.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showGlobal)
          _group(context, 'Cash discount', [
            _row(context, 'All products', globalPercent),
          ]),
        if (cats.isNotEmpty)
          _group(context, 'Category discounts', [
            for (final d in cats)
              _row(context, d.targetLabel ?? 'Category', d.percent),
          ]),
        if (subs.isNotEmpty)
          _group(context, 'Subcategory discounts', [
            for (final d in subs)
              _row(context, d.targetLabel ?? 'Subcategory', d.percent),
          ]),
        if (prods.isNotEmpty)
          _group(context, 'Product discounts', [
            for (final d in prods)
              _row(context, d.targetLabel ?? 'Product', d.percent),
          ]),
        if (!hasSpecific && !showGlobal)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No category / subcategory / product discounts set.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> rows) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: rows),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String name, double pct) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Text('${_num(pct)}%',
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}
