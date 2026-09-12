import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import '../domain/raw_material_variant.dart';
import 'raw_material_providers.dart';

/// Bottom sheet to manage a raw-material variant's stock: add more, return, or
/// set an exact amount. No movement history is stored (kept out of the database).
class RawMaterialStockSheet extends ConsumerStatefulWidget {
  const RawMaterialStockSheet({super.key, required this.variant});
  final RawMaterialVariant variant;

  @override
  ConsumerState<RawMaterialStockSheet> createState() =>
      _RawMaterialStockSheetState();
}

class _RawMaterialStockSheetState extends ConsumerState<RawMaterialStockSheet> {
  final _add = TextEditingController();
  final _return = TextEditingController();
  final _set = TextEditingController();
  String _source = 'production'; // production | purchase
  bool _busy = false;

  @override
  void dispose() {
    _add.dispose();
    _return.dispose();
    _set.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _add.clear();
      _return.clear();
      _set.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Keep the sheet live as stock changes.
    final all = ref.watch(rawVariantsProvider).valueOrNull ?? const [];
    final v = all.firstWhere((x) => x.id == widget.variant.id,
        orElse: () => widget.variant);
    // A default variant (blank label) belongs to a "single" material — show the
    // material's name as the title instead of an empty label.
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? const [];
    final title = v.label.trim().isNotEmpty
        ? v.label
        : (materials.where((m) => m.id == v.rawMaterialId).firstOrNull?.name ??
            'Stock');
    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    final repo = ref.read(rawMaterialRepositoryProvider);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage stock',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(title,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current stock',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      if (v.isOutOfStock)
                        Text('Out of stock',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w700))
                      else if (v.isLowStock)
                        Text('Low stock',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFB45309),
                                fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const Spacer(),
                  Text('${fmtQty(v.currentStock)} ${v.unit}',
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: v.isOutOfStock || v.isLowStock
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Add stock — from production or purchase.
            Text('Add stock',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'production',
                    label: Text('Production'),
                    icon: Icon(Icons.precision_manufacturing_outlined)),
                ButtonSegment(
                    value: 'purchase',
                    label: Text('Purchase'),
                    icon: Icon(Icons.shopping_cart_outlined)),
              ],
              selected: {_source},
              onSelectionChanged: (s) => setState(() => _source = s.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            _row(
              controller: _add,
              label: _source == 'production'
                  ? 'Quantity produced'
                  : 'Quantity purchased',
              unit: v.unit,
              actionLabel: 'Add',
              onAction: () {
                final n = double.tryParse(_add.text.trim());
                if (n == null || n <= 0) return;
                _run(() =>
                    repo.addVariantStock(v, n, type: _source, createdBy: uid));
              },
            ),

            const SizedBox(height: AppSpacing.lg),
            // Return / reduce stock — subtracts.
            Text('Return stock',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            _row(
              controller: _return,
              label: 'Quantity returned',
              unit: v.unit,
              actionLabel: 'Return',
              filled: false,
              onAction: () {
                final n = double.tryParse(_return.text.trim());
                if (n == null || n <= 0) return;
                _run(() => repo.addVariantStock(v, -n,
                    type: 'return', createdBy: uid));
              },
            ),

            const SizedBox(height: AppSpacing.lg),
            // Set exact stock — a manual correction.
            _row(
              controller: _set,
              label: 'Set exact stock',
              unit: v.unit,
              actionLabel: 'Set',
              filled: false,
              onAction: () {
                final n = double.tryParse(_set.text.trim());
                if (n == null) return;
                _run(() => repo.setVariantStock(v, n, createdBy: uid));
              },
            ),

            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required TextEditingController controller,
    required String label,
    required String unit,
    required String actionLabel,
    required VoidCallback onAction,
    bool filled = true,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: label,
              suffixText: unit,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        filled
            ? FilledButton(
                onPressed: _busy ? null : onAction, child: Text(actionLabel))
            : OutlinedButton(
                onPressed: _busy ? null : onAction, child: Text(actionLabel)),
      ],
    );
  }
}
