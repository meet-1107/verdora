import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import '../domain/raw_material_variant.dart';
import 'raw_material_providers.dart';

/// Add / edit a single variant of a raw material (e.g. Nut Bolt → "1/2 inch").
/// The unit is inherited from the material, so only the size label, its stock
/// and optional attributes are set here.
class RawMaterialVariantFormScreen extends ConsumerStatefulWidget {
  const RawMaterialVariantFormScreen({
    super.key,
    required this.rawMaterialId,
    this.existing,
  });

  final String rawMaterialId;
  final RawMaterialVariant? existing;

  @override
  ConsumerState<RawMaterialVariantFormScreen> createState() =>
      _RawMaterialVariantFormScreenState();
}

class _RawMaterialVariantFormScreenState
    extends ConsumerState<RawMaterialVariantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _opening;
  late final TextEditingController _minStock;
  final List<_Attr> _attrs = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? '');
    _opening = TextEditingController();
    _minStock =
        TextEditingController(text: e == null ? '' : fmtQty(e.minStock));
    if (e != null) {
      for (final entry in e.attributes.entries) {
        _attrs.add(_Attr(entry.key, entry.value));
      }
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _opening.dispose();
    _minStock.dispose();
    for (final a in _attrs) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _save(RawMaterial? material) async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    // Inherit the unit from the parent material.
    final unitType = material?.unitType ?? widget.existing?.unitType ?? 'Pieces';
    final unit = material?.unit ?? widget.existing?.unit ?? 'pcs';
    setState(() => _saving = true);
    try {
      final repo = ref.read(rawMaterialRepositoryProvider);
      final attrs = <String, String>{};
      for (final a in _attrs) {
        final k = a.key.text.trim();
        final val = a.value.text.trim();
        if (k.isNotEmpty && val.isNotEmpty) attrs[k] = val;
      }

      if (_isEdit) {
        final e = widget.existing!;
        await repo.updateVariant(RawMaterialVariant(
          id: e.id,
          companyId: e.companyId,
          rawMaterialId: e.rawMaterialId,
          label: _label.text.trim(),
          attributes: attrs,
          unitType: unitType,
          unit: unit,
          currentStock: e.currentStock,
          minStock: double.tryParse(_minStock.text.trim()) ?? 0,
          status: e.status,
        ));
      } else {
        await repo.addVariant(
          RawMaterialVariant(
            id: '',
            companyId: user.companyId,
            rawMaterialId: widget.rawMaterialId,
            label: _label.text.trim(),
            attributes: attrs,
            unitType: unitType,
            unit: unit,
            currentStock: double.tryParse(_opening.text.trim()) ?? 0,
            minStock: double.tryParse(_minStock.text.trim()) ?? 0,
          ),
          createdBy: user.uid,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEdit ? 'Variant updated.' : 'Variant added.')));
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
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? const [];
    final material =
        materials.where((m) => m.id == widget.rawMaterialId).firstOrNull;
    final unit = material?.unit ?? widget.existing?.unit ?? 'pcs';

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit variant' : 'Add variant')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextFormField(
              controller: _label,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Variant / size',
                hintText: 'e.g. 1/2 inch',
                helperText: 'Measured in ${material?.unit ?? unit}'
                    ' (from the material)',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter a variant name / size'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            if (!_isEdit) ...[
              TextFormField(
                controller: _opening,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: InputDecoration(
                  labelText: 'Opening stock (optional)',
                  suffixText: unit,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            TextFormField(
              controller: _minStock,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: InputDecoration(
                labelText: 'Low-stock alert at (optional)',
                suffixText: unit,
                helperText: 'Flagged "Low" when stock falls to this level.',
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Row(
              children: [
                Text('Attributes',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _attrs.add(_Attr('', ''))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_attrs.isEmpty)
              Text('Optional details like Grade, Colour, Thread…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ..._attrs.asMap().entries.map((e) {
              final i = e.key;
              final a = e.value;
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: a.key,
                        decoration: const InputDecoration(
                            isDense: true, labelText: 'Name'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: a.value,
                        decoration: const InputDecoration(
                            isDense: true, labelText: 'Value'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _attrs.removeAt(i).dispose();
                        });
                      },
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(material),
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isEdit ? 'Save changes' : 'Add variant'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attr {
  _Attr(String k, String v)
      : key = TextEditingController(text: k),
        value = TextEditingController(text: v);
  final TextEditingController key;
  final TextEditingController value;
  void dispose() {
    key.dispose();
    value.dispose();
  }
}
