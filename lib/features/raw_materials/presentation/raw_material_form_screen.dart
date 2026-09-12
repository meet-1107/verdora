import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/image_upload_field.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';

/// Add / edit a raw material: photo, name, unit type + specific unit, custom
/// attributes, opening stock (add only) and minimum stock.
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
  late final TextEditingController _minStock;
  late final TextEditingController _openingStock;
  late final TextEditingController _note;

  late String _unitType;
  late String _unit;
  String _imageUrl = '';
  final List<_AttrRow> _attrs = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _minStock =
        TextEditingController(text: e == null ? '' : RawMaterial.fmt(e.minStock));
    _openingStock = TextEditingController();
    _note = TextEditingController(text: e?.note ?? '');
    _unitType = e?.unitType ?? rawMaterialUnitTypes.keys.first;
    if (!rawMaterialUnitTypes.containsKey(_unitType)) {
      _unitType = rawMaterialUnitTypes.keys.first;
    }
    final units = rawMaterialUnitTypes[_unitType]!;
    _unit = (e != null && units.contains(e.unit)) ? e.unit : units.first;
    _imageUrl = e?.imageUrl ?? '';
    if (e != null) {
      e.attributes.forEach((k, v) => _attrs.add(_AttrRow(k, v)));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _minStock.dispose();
    _openingStock.dispose();
    _note.dispose();
    for (final a in _attrs) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(rawMaterialRepositoryProvider);
      final attributes = <String, String>{
        for (final a in _attrs)
          if (a.key.text.trim().isNotEmpty)
            a.key.text.trim(): a.value.text.trim(),
      };
      final base = RawMaterial(
        id: widget.existing?.id ?? '',
        companyId: user.companyId,
        name: _name.text.trim(),
        imageUrl: _imageUrl,
        attributes: attributes,
        unitType: _unitType,
        unit: _unit,
        minStock: double.tryParse(_minStock.text.trim()) ?? 0,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        currentStock: widget.existing?.currentStock ??
            (double.tryParse(_openingStock.text.trim()) ?? 0),
        status: widget.existing?.status ?? 'active',
      );
      if (_isEdit) {
        await repo.update(base);
      } else {
        await repo.add(base, createdBy: user.uid);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEdit ? 'Raw material updated.' : 'Raw material added.')));
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
                hintText: 'e.g. Virgin PVC Resin',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            // ---- unit type + specific unit ----
            Text('Unit', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unitType,
                    decoration: const InputDecoration(labelText: 'Unit type'),
                    items: [
                      for (final t in rawMaterialUnitTypes.keys)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _unitType = v;
                        _unit = rawMaterialUnitTypes[v]!.first;
                      });
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Measured in'),
                    items: [
                      for (final u in units)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (v) => setState(() => _unit = v ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ---- stock ----
            Row(
              children: [
                if (!_isEdit)
                  Expanded(
                    child: TextFormField(
                      controller: _openingStock,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                      decoration: InputDecoration(
                        labelText: 'Opening stock',
                        suffixText: _unit,
                      ),
                    ),
                  ),
                if (!_isEdit) const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _minStock,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Min stock (low alert)',
                      suffixText: _unit,
                    ),
                  ),
                ),
              ],
            ),
            if (_isEdit)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Current stock: ${RawMaterial.fmt(widget.existing!.currentStock)} $_unit '
                    '— change it from “Update stock”.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            const SizedBox(height: AppSpacing.lg),

            // ---- attributes ----
            Row(
              children: [
                Text('Attributes', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _attrs.add(_AttrRow('', ''))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_attrs.isEmpty)
              Text('Optional details like Grade, Colour, HSN…',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            for (var i = 0; i < _attrs.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _attrs[i].key,
                        decoration: const InputDecoration(
                            isDense: true, labelText: 'Name'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _attrs[i].value,
                        decoration: const InputDecoration(
                            isDense: true, labelText: 'Value'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: Icon(Icons.close,
                          size: 18, color: theme.colorScheme.error),
                      onPressed: () => setState(() {
                        _attrs[i].dispose();
                        _attrs.removeAt(i);
                      }),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
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
}

class _AttrRow {
  _AttrRow(String k, String v)
      : key = TextEditingController(text: k),
        value = TextEditingController(text: v);
  final TextEditingController key;
  final TextEditingController value;
  void dispose() {
    key.dispose();
    value.dispose();
  }
}
