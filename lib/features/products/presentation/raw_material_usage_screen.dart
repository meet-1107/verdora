import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../raw_materials/domain/raw_material.dart';
import '../../raw_materials/domain/raw_material_variant.dart';
import '../../raw_materials/domain/unit_convert.dart';
import '../../raw_materials/presentation/raw_material_providers.dart';
import '../domain/variant.dart';

/// Full-screen editor for a product variant's bill of materials — the raw
/// materials it consumes. For each line you pick a raw material, enter how much
/// is used, and choose the unit (including a smaller unit than the raw
/// material's — e.g. raw material in kg, usage entered in grams). The entered
/// amount is converted to the raw material's unit for stock consumption.
class RawMaterialUsageScreen extends ConsumerStatefulWidget {
  const RawMaterialUsageScreen({super.key, required this.initial});
  final List<BomLine> initial;

  @override
  ConsumerState<RawMaterialUsageScreen> createState() =>
      _RawMaterialUsageScreenState();
}

class _UsageRow {
  _UsageRow({this.rawVariantId = '', double amount = 0, this.unit = ''})
      : amountCtrl =
            TextEditingController(text: amount > 0 ? fmtQty(amount) : '');
  String rawVariantId;
  final TextEditingController amountCtrl;
  String unit; // the unit the amount is entered in
  void dispose() => amountCtrl.dispose();
}

class _RawMaterialUsageScreenState
    extends ConsumerState<RawMaterialUsageScreen> {
  final List<_UsageRow> _rows = [];

  @override
  void initState() {
    super.initState();
    for (final b in widget.initial) {
      _rows.add(_UsageRow(
        rawVariantId: b.rawVariantId,
        amount: b.amount,
        unit: b.unit,
      ));
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _save(List<RawMaterialVariant> rawVariants) {
    final byId = {for (final v in rawVariants) v.id: v};
    final out = <BomLine>[];
    for (final r in _rows) {
      final rv = byId[r.rawVariantId];
      final amount = double.tryParse(r.amountCtrl.text.trim()) ?? 0;
      if (rv == null || amount <= 0) continue;
      final unit = r.unit.isEmpty ? rv.unit : r.unit;
      // Convert the entered amount into the raw material's own unit for
      // consumption; fall back to the amount if units can't be converted.
      final qty = convertUnit(amount, unit, rv.unit) ?? amount;
      out.add(BomLine(
          rawVariantId: rv.id, qty: qty, amount: amount, unit: unit));
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawVariants = ref.watch(rawVariantsProvider).valueOrNull ?? const [];
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? const [];
    final names = {for (final m in materials) m.id: m.name};

    String labelFor(RawMaterialVariant v) {
      final mat = names[v.rawMaterialId] ?? 'Material';
      return v.label.trim().isEmpty
          ? '$mat (${v.unit})'
          : '$mat · ${v.label} (${v.unit})';
    }

    final sorted = [...rawVariants]
      ..sort((a, b) =>
          labelFor(a).toLowerCase().compareTo(labelFor(b).toLowerCase()));
    final byId = {for (final v in rawVariants) v.id: v};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raw materials used'),
        actions: [
          TextButton(
            onPressed: () => _save(rawVariants),
            child: const Text('Save'),
          ),
        ],
      ),
      body: rawVariants.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No raw materials yet.\nAdd raw materials (with their units) '
                  'first, then link them here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  'Add each raw material this size consumes, how much, and in '
                  'which unit. Deducted from raw-material stock on dispatch.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < _rows.length; i++)
                  _rowCard(theme, i, sorted, byId, labelFor),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _rows.add(_UsageRow())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add raw material'),
                ),
              ],
            ),
      bottomNavigationBar: rawVariants.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => _save(rawVariants),
                    icon: const Icon(Icons.check),
                    label: const Text('Save raw materials'),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _rowCard(
    ThemeData theme,
    int i,
    List<RawMaterialVariant> sorted,
    Map<String, RawMaterialVariant> byId,
    String Function(RawMaterialVariant) labelFor,
  ) {
    final row = _rows[i];
    final rv = byId[row.rawVariantId];
    // Unit options: units in the same dimension as the raw material's unit.
    final unitOptions = rv == null ? const <String>[] : unitsLike(rv.unit);
    final selectedUnit = row.unit.isNotEmpty
        ? row.unit
        : (rv?.unit ?? '');
    // Live preview of the converted amount in the raw material's unit.
    String? preview;
    if (rv != null) {
      final amount = double.tryParse(row.amountCtrl.text.trim()) ?? 0;
      if (amount > 0 && selectedUnit != rv.unit) {
        final q = convertUnit(amount, selectedUnit, rv.unit);
        if (q != null) preview = '= ${fmtQty(q)} ${rv.unit}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue:
                      row.rawVariantId.isEmpty ? null : row.rawVariantId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      isDense: true, labelText: 'Raw material'),
                  items: [
                    for (final v in sorted)
                      DropdownMenuItem(
                          value: v.id,
                          child: Text(labelFor(v),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (id) => setState(() {
                    row.rawVariantId = id ?? '';
                    // Reset the entry unit to the newly picked material's unit.
                    row.unit = byId[row.rawVariantId]?.unit ?? '';
                  }),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _rows.removeAt(i).dispose()),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: row.amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      isDense: true, labelText: 'Used per unit'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue:
                      unitOptions.contains(selectedUnit) ? selectedUnit : null,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(isDense: true, labelText: 'Unit'),
                  items: [
                    for (final u in unitOptions)
                      DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: rv == null
                      ? null
                      : (u) => setState(() => row.unit = u ?? row.unit),
                ),
              ),
            ],
          ),
          if (preview != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(preview,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
