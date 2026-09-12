import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import 'raw_material_providers.dart';

/// Bottom sheet to manage a raw material's stock: add more, set an exact amount,
/// and review recent movements.
class RawMaterialStockSheet extends ConsumerStatefulWidget {
  const RawMaterialStockSheet({super.key, required this.material});
  final RawMaterial material;

  @override
  ConsumerState<RawMaterialStockSheet> createState() =>
      _RawMaterialStockSheetState();
}

class _RawMaterialStockSheetState extends ConsumerState<RawMaterialStockSheet> {
  final _add = TextEditingController();
  final _set = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _add.dispose();
    _set.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _add.clear();
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
    final rm = ref.watch(rawMaterialsProvider).maybeWhen(
          data: (list) => list.firstWhere((m) => m.id == widget.material.id,
              orElse: () => widget.material),
          orElse: () => widget.material,
        );
    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    final repo = ref.read(rawMaterialRepositoryProvider);
    final txns = ref.watch(rawMaterialTxnsProvider(rm.id)).valueOrNull ?? const [];
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
            Text(rm.name,
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
                  Text('Current stock',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  Text('${RawMaterial.fmt(rm.currentStock)} ${rm.unit}',
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: rm.isLowStock
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Add stock
            _row(
              controller: _add,
              label: 'Add stock',
              unit: rm.unit,
              actionLabel: 'Add',
              onAction: () {
                final v = double.tryParse(_add.text.trim());
                if (v == null || v <= 0) return;
                _run(() => repo.addStock(rm, v, createdBy: uid));
              },
            ),
            const SizedBox(height: AppSpacing.md),
            // Set exact stock
            _row(
              controller: _set,
              label: 'Set exact stock',
              unit: rm.unit,
              actionLabel: 'Set',
              filled: false,
              onAction: () {
                final v = double.tryParse(_set.text.trim());
                if (v == null) return;
                _run(() => repo.setStock(rm, v, createdBy: uid));
              },
            ),

            const SizedBox(height: AppSpacing.lg),
            Text('Recent movements', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            if (txns.isEmpty)
              Text('No stock movements yet.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              ...txns.take(12).map((t) {
                final up = t.quantity >= 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 16,
                          color: up
                              ? const Color(0xFF16A34A)
                              : theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_typeLabel(t.type)} · ${Formatters.dateTime(t.createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text('${up ? '+' : ''}${RawMaterial.fmt(t.quantity)} ${rm.unit}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: up
                                  ? const Color(0xFF16A34A)
                                  : theme.colorScheme.error)),
                    ],
                  ),
                );
              }),
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

  String _typeLabel(String t) => switch (t) {
        'opening' => 'Opening stock',
        'add' => 'Stock added',
        'adjust' => 'Stock adjusted',
        _ => t,
      };

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
            ? FilledButton(onPressed: _busy ? null : onAction, child: Text(actionLabel))
            : OutlinedButton(
                onPressed: _busy ? null : onAction, child: Text(actionLabel)),
      ],
    );
  }
}
