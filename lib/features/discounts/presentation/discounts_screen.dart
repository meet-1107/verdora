import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../parties/data/party_repository.dart';
import '../../parties/domain/party.dart';
import '../../parties/presentation/party_providers.dart';
import '../../products/presentation/product_providers.dart';
import '../../subcategories/domain/subcategory.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../data/discount_repository.dart';
import '../domain/discount.dart';
import 'discount_providers.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Formats a percent value without a trailing `.0` for whole numbers.
String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// Chip label for a percent value.
String _pctLabel(double v) => '${_num(v)}%';

/// Finds this party's rule (if any) for the given scope + target.
Discount? _partyRule(
  List<Discount> all,
  String partyId,
  DiscountScope scope,
  String targetId,
) {
  for (final d in all) {
    if (d.partyId == partyId && d.scope == scope && d.targetId == targetId) {
      return d;
    }
  }
  return null;
}

/// Trailing widget: a discount chip (or `—`) plus an edit button.
Widget _discountTrailing(
  BuildContext context, {
  required String label,
  required VoidCallback onEdit,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Set discount',
        icon: const Icon(Icons.edit_outlined),
        onPressed: onEdit,
      ),
    ],
  );
}

/// Shared "Set discount" dialog for a category / subcategory / product rule.
///
/// CRITICAL: buttons pop with the dialog builder's OWN [dialogContext] (a known
/// blank-screen bug otherwise).
Future<void> _showDiscountDialog(
  BuildContext context,
  WidgetRef ref, {
  required Party party,
  required DiscountScope scope,
  required String targetId,
  required String targetLabel,
  required Discount? existing,
}) {
  final controller =
      TextEditingController(text: existing != null ? _num(existing.percent) : '');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Discount · $targetLabel'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Discount for ${party.name}',
          suffixText: '%',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        if (existing != null)
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () {
              ref.read(discountRepositoryProvider).delete(existing.id);
              Navigator.pop(dialogContext);
            },
            child: const Text('Remove'),
          ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(controller.text.trim()) ?? 0;
            final repo = ref.read(discountRepositoryProvider);
            if (existing != null) {
              repo.update(Discount(
                id: existing.id,
                companyId: existing.companyId,
                scope: scope,
                percent: value,
                targetId: targetId,
                targetLabel: targetLabel,
                partyId: party.id,
              ));
            } else {
              final companyId =
                  ref.read(currentUserProvider).valueOrNull?.companyId ??
                      AppConstants.defaultCompanyId;
              repo.create(Discount(
                id: '',
                companyId: companyId,
                scope: scope,
                percent: value,
                targetId: targetId,
                targetLabel: targetLabel,
                partyId: party.id,
              ));
            }
            Navigator.pop(dialogContext);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// "Set global discount" dialog for a party's baseline percent.
Future<void> _showGlobalDialog(
  BuildContext context,
  WidgetRef ref,
  Party party,
) {
  final controller = TextEditingController(text: _num(party.defaultDiscount));
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Set cash discount · ${party.name}'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Cash discount',
          suffixText: '%',
          helperText: 'Baseline applied unless a more specific rule overrides.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(controller.text.trim()) ?? 0;
            ref.read(partyRepositoryProvider).setDefaultDiscount(party.id, value);
            Navigator.pop(dialogContext);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Level 1 — Parties
// ---------------------------------------------------------------------------

class DiscountsScreen extends ConsumerStatefulWidget {
  const DiscountsScreen({super.key});

  @override
  ConsumerState<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends ConsumerState<DiscountsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(partiesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Discounts'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text(
              'Set discounts per dealer: Cash → Category → Subcategory → '
              'Product (more specific wins).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppSearchBar(
              controller: _search,
              hint: 'Search dealers…',
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: parties.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.invalidate(partiesProvider)),
              data: (list) {
                final filtered = [
                  for (final p in list)
                    if (_query.isEmpty ||
                        p.name.toLowerCase().contains(_query) ||
                        p.partyCode.toLowerCase().contains(_query))
                      p,
                ]..sort((a, b) =>
                    a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                if (filtered.isEmpty) {
                  return EmptyView(
                    message: list.isEmpty
                        ? 'No dealers yet.'
                        : 'No dealers match "$_query".',
                    icon: Icons.groups_outlined,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final party = filtered[i];
                    return Card(
                      child: ListTile(
                        title: Text(party.name),
                        subtitle: Text(party.partyCode),
                        trailing: _discountTrailing(
                          context,
                          label: _pctLabel(party.defaultDiscount),
                          onEdit: () => _showGlobalDialog(context, ref, party),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _PartyCategoriesScreen(party: party),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 2 — Categories for a party
// ---------------------------------------------------------------------------

class _PartyCategoriesScreen extends ConsumerWidget {
  const _PartyCategoriesScreen({required this.party});
  final Party party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final rules = ref.watch(discountsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(party.name),
        bottom: const _SubtitleBar(text: 'Category discounts'),
      ),
      body: categories.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(categoriesProvider)),
        data: (list) {
          final sorted = [...list]..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          if (sorted.isEmpty) {
            return const EmptyView(
                message: 'No categories yet.', icon: Icons.folder_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final category = sorted[i];
              final rule = _partyRule(
                  rules, party.id, DiscountScope.category, category.id);
              return Card(
                child: ListTile(
                  title: Text(category.name),
                  trailing: _discountTrailing(
                    context,
                    label: rule != null ? _pctLabel(rule.percent) : '—',
                    onEdit: () => _showDiscountDialog(
                      context,
                      ref,
                      party: party,
                      scope: DiscountScope.category,
                      targetId: category.id,
                      targetLabel: category.name,
                      existing: rule,
                    ),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _CategorySubcategoriesScreen(
                          party: party, category: category),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 3 — Subcategories for a party + category
// ---------------------------------------------------------------------------

class _CategorySubcategoriesScreen extends ConsumerWidget {
  const _CategorySubcategoriesScreen({
    required this.party,
    required this.category,
  });
  final Party party;
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subcategoriesByCategoryProvider(category.id));
    final rules = ref.watch(discountsProvider).valueOrNull ?? const [];

    final sorted = [...subs]..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: Text(category.name),
        bottom: _SubtitleBar(text: '${party.name} · subcategory discounts'),
      ),
      body: sorted.isEmpty
          ? const EmptyView(
              message: 'No subcategories in this category.',
              icon: Icons.folder_outlined,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final sub = sorted[i];
                final rule = _partyRule(
                    rules, party.id, DiscountScope.subcategory, sub.id);
                return Card(
                  child: ListTile(
                    title: Text(sub.name),
                    trailing: _discountTrailing(
                      context,
                      label: rule != null ? _pctLabel(rule.percent) : '—',
                      onEdit: () => _showDiscountDialog(
                        context,
                        ref,
                        party: party,
                        scope: DiscountScope.subcategory,
                        targetId: sub.id,
                        targetLabel: sub.name,
                        existing: rule,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _SubcategoryProductsScreen(
                          party: party,
                          category: category,
                          subcategory: sub,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 4 — Products for a party + subcategory
// ---------------------------------------------------------------------------

class _SubcategoryProductsScreen extends ConsumerWidget {
  const _SubcategoryProductsScreen({
    required this.party,
    required this.category,
    required this.subcategory,
  });
  final Party party;
  final Category category;
  final Subcategory subcategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final rules = ref.watch(discountsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(subcategory.name),
        bottom: _SubtitleBar(text: '${party.name} · product discounts'),
      ),
      body: products.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(productsProvider)),
        data: (list) {
          final filtered = [
            for (final p in list)
              if (p.subcategoryId == subcategory.id) p,
          ]..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          if (filtered.isEmpty) {
            return const EmptyView(
              message: 'No products in this subcategory.',
              icon: Icons.category_outlined,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final product = filtered[i];
              final rule = _partyRule(
                  rules, party.id, DiscountScope.product, product.id);
              return Card(
                child: ListTile(
                  title: Text(product.name),
                  trailing: _discountTrailing(
                    context,
                    label: rule != null ? _pctLabel(rule.percent) : '—',
                    onEdit: () => _showDiscountDialog(
                      context,
                      ref,
                      party: party,
                      scope: DiscountScope.product,
                      targetId: product.id,
                      targetLabel: product.name,
                      existing: rule,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared AppBar subtitle
// ---------------------------------------------------------------------------

class _SubtitleBar extends StatelessWidget implements PreferredSizeWidget {
  const _SubtitleBar({required this.text});
  final String text;

  @override
  Size get preferredSize => const Size.fromHeight(28);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
        child: Text(
          text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
