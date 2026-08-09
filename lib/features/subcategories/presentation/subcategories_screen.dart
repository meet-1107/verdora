import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_thumb.dart';
import '../../../core/widgets/image_upload_field.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../data/subcategory_repository.dart';
import '../domain/subcategory.dart';
import 'subcategory_providers.dart';

class SubcategoriesScreen extends ConsumerWidget {
  const SubcategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subcategoriesProvider);
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catName = {for (final c in cats) c.id: c.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Subcategories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: cats.isEmpty
            ? null
            : () => _openForm(context, ref, categories: cats),
        icon: const Icon(Icons.add),
        label: const Text('Add Subcategory'),
      ),
      body: subs.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(subcategoriesProvider)),
        data: (unsorted) {
          final items = [...unsorted]
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          if (cats.isEmpty) {
            return const EmptyView(
              message: 'Create a category first,\nthen add subcategories.',
              icon: Icons.folder_outlined,
            );
          }
          if (items.isEmpty) {
            return EmptyView(
              message: 'No subcategories yet.',
              icon: Icons.account_tree_outlined,
              action: FilledButton.icon(
                onPressed: () => _openForm(context, ref, categories: cats),
                icon: const Icon(Icons.add),
                label: const Text('Add Subcategory'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = items[i];
              return Card(
                child: ListTile(
                  leading: AppThumb(
                      url: s.imageUrl, icon: Icons.account_tree_outlined),
                  title: Text(s.name),
                  subtitle: Text(catName[s.categoryId] ?? 'Unknown category'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => _onAction(context, ref, v, s, cats),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () =>
                      _openForm(context, ref, categories: cats, existing: s),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, String action,
      Subcategory s, List<Category> cats) async {
    final repo = ref.read(subcategoryRepositoryProvider);
    if (action == 'edit') {
      _openForm(context, ref, categories: cats, existing: s);
    } else if (action == 'delete') {
      await repo.delete(s.id);
    }
  }

  void _openForm(BuildContext context, WidgetRef ref,
      {required List<Category> categories, Subcategory? existing}) {
    showDialog(
      context: context,
      builder: (_) =>
          _SubcategoryForm(categories: categories, existing: existing),
    );
  }
}

class _SubcategoryForm extends ConsumerStatefulWidget {
  const _SubcategoryForm({required this.categories, this.existing});
  final List<Category> categories;
  final Subcategory? existing;

  @override
  ConsumerState<_SubcategoryForm> createState() => _SubcategoryFormState();
}

class _SubcategoryFormState extends ConsumerState<_SubcategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  String? _categoryId;
  String? _imageUrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _categoryId = widget.existing?.categoryId ??
        (widget.categories.isNotEmpty ? widget.categories.first.id : null);
    _imageUrl = widget.existing?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(subcategoryRepositoryProvider);
      final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
          AppConstants.defaultCompanyId;
      if (_isEdit) {
        await repo.update(widget.existing!.copyWith(
          name: _name.text.trim(),
          categoryId: _categoryId,
          imageUrl: _imageUrl,
        ));
      } else {
        await repo.create(Subcategory(
          id: '',
          companyId: companyId,
          categoryId: _categoryId!,
          name: _name.text.trim(),
          imageUrl: _imageUrl,
        ));
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Subcategory' : 'Add Subcategory'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 96).clamp(260.0, 400.0).toDouble(),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in widget.categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Select a category' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => Validators.required(v, field: 'Name'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: ImageUploadField(
                  initial: _imageUrl == null ? const [] : [_imageUrl!],
                  companyId:
                      ref.read(currentUserProvider).valueOrNull?.companyId ??
                          AppConstants.defaultCompanyId,
                  folder: 'subcategories',
                  title: 'Image',
                  onChanged: (list) =>
                      setState(() => _imageUrl = list.isEmpty ? null : list.first),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
