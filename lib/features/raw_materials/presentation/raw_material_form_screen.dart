import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/image_upload_field.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import '../domain/raw_material_variant.dart';
import 'raw_material_providers.dart';

/// Add / edit a raw material. On create you choose the unit, then either enter a
/// single opening stock + low-stock alert, or add named variants (sizes) — each
/// with its own stock. Some materials have variants, some don't.
class RawMaterialFormScreen extends ConsumerStatefulWidget {
  const RawMaterialFormScreen({super.key, this.existing});
  final RawMaterial? existing;

  @override
  ConsumerState<RawMaterialFormScreen> createState() =>
      _RawMaterialFormScreenState();
}

class _RawMaterialFormScreenState extends ConsumerState<RawMaterialFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _opening; // single-stock opening
  late final TextEditingController _minStock; // single-stock low alert
  String _imageUrl = '';

  late String _unitType;
  late String _unit;
  bool _hasVariants = false;
  final List<_VariantRow> _variants = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _opening = TextEditingController();
    _minStock = TextEditingController();
    _imageUrl = e?.imageUrl ?? '';
    _unitType = e?.unitType ?? rawMaterialUnitTypes.keys.first;
    final units = rawMaterialUnitTypes[_unitType]!;
    _unit = (e != null && units.contains(e.unit)) ? e.unit : units.first;

    // On edit, reflect the current shape (single vs variants) read-only-ish.
    if (_isEdit) {
      final vs = ref.read(variantsOfProvider(e!.id));
      _hasVariants = !isSimpleVariantList(vs);
      if (!_hasVariants && vs.isNotEmpty) {
        _minStock.text = fmtQty(vs.first.minStock);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _opening.dispose();
    _minStock.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _hasVariants) {
      final valid = _variants.where((v) => v.label.text.trim().isNotEmpty);
      if (valid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Add at least one variant, or switch to single '
                'stock.')));
        return;
      }
    }
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(rawMaterialRepositoryProvider);
      final rm = RawMaterial(
        id: widget.existing?.id ?? '',
        companyId: user.companyId,
        name: _name.text.trim(),
        imageUrl: _imageUrl,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        unitType: _unitType,
        unit: _unit,
        status: widget.existing?.status ?? 'active',
      );

      if (_isEdit) {
        // For a "single" material, keep its default variant's unit in sync with
        // the material-level unit. Variant materials keep each variant's own
        // unit untouched.
        await repo.updateMaterial(rm);
        final vs = ref.read(variantsOfProvider(rm.id));
        if (isSimpleVariantList(vs)) {
          final v = vs.first;
          if (v.unitType != _unitType || v.unit != _unit) {
            await repo.updateVariant(RawMaterialVariant(
              id: v.id,
              companyId: v.companyId,
              rawMaterialId: v.rawMaterialId,
              label: v.label,
              attributes: v.attributes,
              unitType: _unitType,
              unit: _unit,
              currentStock: v.currentStock,
              minStock: v.minStock,
              status: v.status,
            ));
          }
        }
      } else {
        final id = await repo.addMaterial(rm);
        if (_hasVariants) {
          for (final row in _variants) {
            final label = row.label.text.trim();
            if (label.isEmpty) continue;
            await repo.addVariant(
              RawMaterialVariant(
                id: '',
                companyId: user.companyId,
                rawMaterialId: id,
                label: label,
                unitType: row.unitType,
                unit: row.unit,
                currentStock: double.tryParse(row.opening.text.trim()) ?? 0,
                minStock: double.tryParse(row.min.text.trim()) ?? 0,
              ),
              createdBy: user.uid,
            );
          }
        } else {
          // Single default variant (blank label) holds the material's stock.
          await repo.addVariant(
            RawMaterialVariant(
              id: '',
              companyId: user.companyId,
              rawMaterialId: id,
              label: '',
              unitType: _unitType,
              unit: _unit,
              currentStock: double.tryParse(_opening.text.trim()) ?? 0,
              minStock: double.tryParse(_minStock.text.trim()) ?? 0,
            ),
            createdBy: user.uid,
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                _isEdit ? 'Raw material updated.' : 'Raw material added.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final units = rawMaterialUnitTypes[_unitType]!;

    return Scaffold(
      appBar: AppBar(
          title: Text(_isEdit ? 'Edit raw material' : 'Add raw material')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (user != null)
              ImageUploadField(
                title: 'Photo',
                initial: _imageUrl.isEmpty ? const [] : [_imageUrl],
                companyId: user.companyId,
                folder: 'raw_materials',
                onChanged: (urls) =>
                    setState(() => _imageUrl = urls.isEmpty ? '' : urls.last),
              ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Raw material name',
                hintText: 'e.g. Nut Bolt',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Unit type → unit (dependent).
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unitType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unit type'),
                    items: rawMaterialUnitTypes.keys
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (t) {
                      if (t == null) return;
                      setState(() {
                        _unitType = t;
                        _unit = rawMaterialUnitTypes[t]!.first;
                      });
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: units
                        .map((u) =>
                            DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (u) =>
                        setState(() => _unit = u ?? units.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (_isEdit)
              _EditHint(theme: theme)
            else ...[
              // Stock shape: single vs variants.
              Text('Stock',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Single'),
                      icon: Icon(Icons.inventory_2_outlined)),
                  ButtonSegment(
                      value: true,
                      label: Text('Has variants'),
                      icon: Icon(Icons.straighten)),
                ],
                selected: {_hasVariants},
                onSelectionChanged: (s) =>
                    setState(() => _hasVariants = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_hasVariants) _variantsEditor(theme) else _singleEditor(),
            ],

            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isEdit ? 'Save changes' : 'Add raw material'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _singleEditor() {
    return Column(
      children: [
        TextFormField(
          controller: _opening,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
          ],
          decoration: InputDecoration(
            labelText: 'Opening stock (optional)',
            suffixText: _unit,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _minStock,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
          ],
          decoration: InputDecoration(
            labelText: 'Low-stock alert at (optional)',
            suffixText: _unit,
            helperText: 'Flagged "Low" when stock falls to this level.',
          ),
        ),
      ],
    );
  }

  Widget _variantsEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Variants (sizes)',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _variants
                  .add(_VariantRow(unitType: _unitType, unit: _unit))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add variant'),
            ),
          ],
        ),
        if (_variants.isEmpty)
          Text('Add sizes like 1/2, 3/4 — each with its own stock.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        for (var i = 0; i < _variants.length; i++) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _variants[i].label,
                        decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Variant / size',
                            hintText: 'e.g. 1/2 inch'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          setState(() => _variants.removeAt(i).dispose()),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                // Per-variant unit type → unit.
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _variants[i].unitType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            isDense: true, labelText: 'Unit type'),
                        items: rawMaterialUnitTypes.keys
                            .map((t) =>
                                DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (t) {
                          if (t == null) return;
                          setState(() {
                            _variants[i].unitType = t;
                            _variants[i].unit =
                                rawMaterialUnitTypes[t]!.first;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _variants[i].unit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            isDense: true, labelText: 'Unit'),
                        items: (rawMaterialUnitTypes[_variants[i].unitType] ??
                                const [])
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (u) => setState(() =>
                            _variants[i].unit = u ?? _variants[i].unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _variants[i].opening,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                        ],
                        decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Opening',
                            suffixText: _variants[i].unit),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _variants[i].min,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                        ],
                        decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Low at',
                            suffixText: _variants[i].unit),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EditHint extends StatelessWidget {
  const _EditHint({required this.theme});
  final ThemeData theme;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
                'Manage stock and variants from the raw material list '
                '(tap the item or its ⋮ menu).',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _VariantRow {
  _VariantRow({required this.unitType, required this.unit});
  final TextEditingController label = TextEditingController();
  final TextEditingController opening = TextEditingController();
  final TextEditingController min = TextEditingController();
  String unitType;
  String unit;
  void dispose() {
    label.dispose();
    opening.dispose();
    min.dispose();
  }
}
