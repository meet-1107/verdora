import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/admin_shell.dart';
import '../../../core/widgets/app_thumb.dart';
import '../../../core/widgets/image_upload_field.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../subcategories/presentation/subcategories_screen.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';
import 'category_providers.dart';

/// Reference CRUD screen. New admin modules (subcategories, parties, products,
/// discounts…) should mirror this structure: a `StreamProvider` list + a form
/// dialog that calls the repository.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AdminMenuButton(),
        title: const Text('Categories'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SubcategoriesScreen(),
            )),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Subcategories'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
      body: categories.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(categoriesProvider)),
        data: (items) {
          if (items.isEmpty) {
            return EmptyView(
              message: 'No categories yet.\nCreate your first category.',
              icon: Icons.folder_outlined,
              action: FilledButton.icon(
                onPressed: () => _openForm(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add Category'),
              ),
            );
          }
          final sorted = [...items]
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _CategoryTile(category: sorted[i]),
          );
        },
      ),
    );
  }

  static void _openForm(BuildContext context, WidgetRef ref,
      {Category? existing}) {
    showDialog(
      context: context,
      builder: (_) => _CategoryFormDialog(existing: existing),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading:
            AppThumb(url: category.imageUrl, icon: Icons.folder_outlined),
        title: Text(category.name),
        subtitle: category.description.isEmpty
            ? null
            : Text(category.description,
                maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onAction(context, ref, v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () =>
            CategoriesScreen._openForm(context, ref, existing: category),
      ),
    );
  }

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(categoryRepositoryProvider);
    switch (action) {
      case 'edit':
        CategoriesScreen._openForm(context, ref, existing: category);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete category?'),
            content: Text('Delete "${category.name}"? This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) await repo.delete(category.id);
    }
  }
}

class _CategoryFormDialog extends ConsumerStatefulWidget {
  const _CategoryFormDialog({this.existing});
  final Category? existing;

  @override
  ConsumerState<_CategoryFormDialog> createState() =>
      _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _sortOrder;
  String? _imageUrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _sortOrder = TextEditingController(text: (e?.sortOrder ?? 0).toString());
    _imageUrl = e?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(categoryRepositoryProvider);
      final user = ref.read(currentUserProvider).valueOrNull;
      final companyId = user?.companyId ?? AppConstants.defaultCompanyId;
      final sort = int.tryParse(_sortOrder.text.trim()) ?? 0;

      if (_isEdit) {
        await repo.update(widget.existing!.copyWith(
          name: _name.text.trim(),
          description: _description.text.trim(),
          sortOrder: sort,
          imageUrl: _imageUrl,
          status: 'active', // saving always keeps a category active
        ));
      } else {
        await repo.create(Category(
          id: '',
          companyId: companyId,
          name: _name.text.trim(),
          description: _description.text.trim(),
          sortOrder: sort,
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
    final companyId = ref.watch(currentUserProvider).valueOrNull?.companyId ??
        AppConstants.defaultCompanyId;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(_isEdit ? 'Edit Category' : 'Add Category'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 80).clamp(280.0, 420.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => Validators.required(v, field: 'Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration:
                      const InputDecoration(labelText: 'Description (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sortOrder,
                  decoration: const InputDecoration(labelText: 'Sort order'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                ImageUploadField(
                  initial: _imageUrl == null ? const [] : [_imageUrl!],
                  companyId: companyId,
                  folder: 'categories',
                  title: 'Image',
                  onChanged: (urls) =>
                      setState(() => _imageUrl = urls.isEmpty ? null : urls.first),
                ),
              ],
            ),
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
