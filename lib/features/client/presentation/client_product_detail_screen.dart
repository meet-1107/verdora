import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_bottom_order_bar.dart';
import '../../../core/widgets/app_favorite_button.dart';
import '../../../core/widgets/app_pricing_card.dart';
import '../../../core/widgets/app_product_header.dart';
import '../../../core/widgets/app_quantity_stepper.dart';
import '../../../core/widgets/app_quick_quantity_buttons.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_skeleton_loader.dart';
import '../../../core/widgets/app_stock_badge.dart';
import '../../../core/widgets/state_views.dart';
import '../../categories/presentation/category_providers.dart';
import '../../discounts/logic/discount_resolver.dart';
import '../../discounts/presentation/discount_providers.dart';
import '../../parties/presentation/party_providers.dart';
import '../../products/domain/product.dart';
import '../../products/domain/variant.dart';
import '../../products/presentation/product_providers.dart';
import '../application/cart_provider.dart';
import 'client_cart_screen.dart';

/// Order Configuration workspace (not an e-commerce detail page):
/// select variant → see price/discount → enter quantity → live total → add.
/// UI redesign only; pricing/discount/cart logic unchanged.
class ClientProductDetailScreen extends ConsumerStatefulWidget {
  const ClientProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<ClientProductDetailScreen> createState() =>
      _ClientProductDetailScreenState();
}

class _ClientProductDetailScreenState
    extends ConsumerState<ClientProductDetailScreen> {
  String? _variantId;
  int _qty = 1;
  bool _favorite = false;
  final _qtyController = TextEditingController(text: '1');

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  static StockStatus _statusFor(List<Variant> vs) {
    final active = vs.where((v) => v.status == 'active').toList();
    if (active.isEmpty) return StockStatus.comingSoon;
    if (!active.any((v) => v.currentStock > 0)) return StockStatus.outOfStock;
    if (!active.any((v) => v.currentStock > 0 && v.currentStock > v.minStock)) {
      return StockStatus.lowStock;
    }
    return StockStatus.inStock;
  }

  String _variantLabel(Variant v) => v.attributes.isEmpty
      ? 'Size'
      : v.attributes.entries.map((e) => '${e.key}: ${e.value}').join(', ');

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final variantsAsync = ref.watch(variantsByProductProvider(product.id));
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final party = ref.watch(currentPartyProvider).valueOrNull;
    final resolver =
        DiscountResolver(ref.watch(discountsProvider).valueOrNull ?? const []);

    final categoryName = () {
      for (final c in categories) {
        if (c.id == product.categoryId) return c.name;
      }
      return null;
    }();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          AppFavoriteButton(
            isFavorite: _favorite,
            onTap: () => setState(() => _favorite = !_favorite),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: variantsAsync.when(
        loading: () => const AppSkeletonList(rowHeight: 80),
        error: (e, _) => ErrorView(
            error: e,
            onRetry: () =>
                ref.invalidate(variantsByProductProvider(product.id))),
        data: (allVariants) {
          final variants =
              allVariants.where((v) => v.status == 'active').toList();

          if (variants.isEmpty) {
            return const EmptyView(
              message: 'No sizes available.\n'
                  'Please contact your administrator.',
              icon: Icons.inventory_2_outlined,
            );
          }

          // Default selection = first variant.
          final selected = variants.firstWhere(
            (v) => v.id == _variantId,
            orElse: () => variants.first,
          );
          final discount = resolver.resolve(DiscountContext(
            variantId: selected.id,
            productId: product.id,
            categoryId: product.categoryId,
            subcategoryId: product.subcategoryId ?? '',
            partyId: party?.id ?? '',
            partyDefaultDiscount: party?.defaultDiscount ?? 0,
          ));
          final finalRate = selected.rate * (1 - discount / 100);
          final total = finalRate * _qty;
          final outOfStock = selected.currentStock <= 0;
          final exceedsStock =
              !outOfStock && _qty > selected.currentStock;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  children: [
                    AppProductHeader(
                      name: product.name,
                      imageUrl: product.imageUrls.isNotEmpty
                          ? product.imageUrls.first
                          : null,
                      categoryPath: categoryName,
                      sku: selected.sku,
                      stock: _statusFor(allVariants),
                      variantCount: variants.length,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppSectionHeader(title: 'Select size'),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final v in variants)
                                ChoiceChip(
                                  label: Text(_variantLabel(v)),
                                  selected: v.id == selected.id,
                                  showCheckmark: false,
                                  selectedColor:
                                      Theme.of(context).colorScheme.primary,
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: v.id == selected.id
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _variantId = v.id),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          AppPricingCard(
                            rate: Formatters.money(selected.rate),
                            discount: discount > 0 ? '$discount%' : null,
                            finalPrice: Formatters.money(finalRate),
                            pack: '${selected.pack}',
                            boxPack: '${selected.boxPack}',
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const AppSectionHeader(title: 'Order quantity'),
                          AppQuantityStepper(
                            controller: _qtyController,
                            onChanged: (v) => setState(() => _qty = v),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppQuickQuantityButtons(
                            onSelected: (v) => setState(() {
                              _qty = v;
                              _qtyController.text = '$v';
                            }),
                          ),
                          if (outOfStock || exceedsStock) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _warning(
                              context,
                              outOfStock
                                  ? 'This size is currently out of stock.'
                                  : 'Requested quantity may exceed available '
                                      'stock. It can still be ordered (backorder).',
                              isError: outOfStock,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AppBottomOrderBar(
                totalLabel: 'Total',
                totalValue: Formatters.money(total),
                actionLabel: 'Add to Cart',
                enabled: !outOfStock && _qty > 0,
                onAction: () => _addToCart(selected, discount),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _warning(BuildContext context, String text, {required bool isError}) {
    final color = isError ? AppColors.error : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.textField),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.warning_amber_rounded,
              size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _addToCart(Variant v, double discount) {
    ref.read(cartProvider.notifier).addVariant(
          variantId: v.id,
          productName: widget.product.name,
          variantLabel: _variantLabel(v),
          rate: v.rate,
          qty: _qty,
          discountPercent: discount,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Added to cart'),
        action: SnackBarAction(
          label: 'View Cart',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ClientCartScreen()),
          ),
        ),
      ),
    );
  }
}
