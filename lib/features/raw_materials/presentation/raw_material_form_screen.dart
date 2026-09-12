import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/image_upload_field.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';

/// Add / edit a raw material (the parent). Its sizes/specs are added as variants
/// afterwards.
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
  String _imageUrl = '';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _note = TextEditingController(text: widget.existing?.note ?? '');
    _imageUrl = widget.existing?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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
        status: widget.existing?.status ?? 'active',
      );
      if (_isEdit) {
        await repo.updateMaterial(rm);
      } else {
        await repo.addMaterial(rm);
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
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
                'After saving, open this material and add its sizes/specs as '
                'variants (e.g. 1/2 inch, 3/4 inch) — each with its own unit and '
                'stock.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
