import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/image_upload_field.dart';
import '../../../core/widgets/key_value_editor.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categories/presentation/category_providers.dart';
import '../../raw_materials/domain/raw_material.dart';
import '../../raw_materials/domain/raw_material_variant.dart';
import '../../raw_materials/presentation/raw_material_providers.dart';
import '../../subcategories/presentation/subcategory_providers.dart';
import '../data/product_repository.dart';
import '../data/variant_repository.dart';
import '../domain/product.dart';
import '../domain/variant.dart';
import 'product_providers.dart';

/// Full-page editor for a product's core fields + dynamic attributes, plus its
/// variants. Variants can be managed once the product exists (has an id).
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existing});
  final Product? existing;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  String? _categoryId;
  String? _subcategoryId;
  List<MapEntry<String, String>> _attributes = const [];
  List<String> _imageUrls = const [];
  String? _productId; // null until first save
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _productId = e?.id;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _categoryId = e?.categoryId;
    _subcategoryId = e?.subcategoryId;
    _attributes =
        e?.attributes.map((a) => MapEntry(a.key, a.value)).toList() ?? const [];
    _imageUrls = [...?e?.imageUrls];
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _categoryId == null) {
      if (_categoryId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a category.')));
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
          AppConstants.defaultCompanyId;
      final product = Product(
        id: _productId ?? '',
        companyId: companyId,
        categoryId: _categoryId!,
        subcategoryId: _subcategoryId,
        name: _name.text.trim(),
        description: _description.text.trim(),
        imageUrls: _imageUrls,
        attributes: _attributes
            .map((e) => ProductAttribute(key: e.key, value: e.value))
            .toList(),
      );
      if (_productId == null) {
        final id = await repo.create(product);
        setState(() => _productId = id); // reveal variants section
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Product created. Now add its sizes.')));
        }
      } else {
        await repo.update(product);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Product saved.')));
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final subs = _categoryId == null
        ? const []
        : ref.watch(subcategoriesByCategoryProvider(_categoryId!));

    // Guard against a selected id that hasn't streamed into its list yet
    // (DropdownButtonFormField asserts value ∈ items).
    final catValue = cats.any((c) => c.id == _categoryId) ? _categoryId : null;
    final subValue =
        subs.any((s) => s.id == _subcategoryId) ? _subcategoryId : null;
    final companyId = ref.watch(currentUserProvider).valueOrNull?.companyId ??
        AppConstants.defaultCompanyId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New Product' : 'Edit Product'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Product name'),
                    validator: (v) => Validators.required(v, field: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: catValue,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in cats)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _categoryId = v;
                      _subcategoryId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: subValue,
                    decoration: const InputDecoration(
                        labelText: 'Subcategory (optional)'),
                    items: [
                      for (final s in subs)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => setState(() => _subcategoryId = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(
                        labelText: 'Description (optional)'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  ImageUploadField(
                    title: 'Product images',
                    folder: 'products',
                    companyId: companyId,
                    initial: _imageUrls,
                    onChanged: (urls) => _imageUrls = urls,
                  ),
                  const SizedBox(height: 20),
                  KeyValueEditor(
                    title: 'Product attributes',
                    initial: _attributes,
                    onChanged: (v) => _attributes = v,
                  ),
                  const Divider(height: 40),
                  _VariantsSection(productId: _productId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- variant-card palette (semantic foreground colours; backgrounds come from
// the theme so they adapt to dark mode) -------------------------------------
const _kVPrimary = Color(0xFF1565C0);
const _kVSuccess = Color(0xFF16A34A);
const _kVWarning = Color(0xFFF59E0B);
const _kVDanger = Color(0xFFDC2626);

String _variantTitle(Variant v) {
  final size = (v.attributes['Size'] ?? '').trim();
  final unit = (v.attributes['Size Unit'] ?? '').trim();
  final t = [size, unit].where((s) => s.isNotEmpty).join(' ');
  return t.isEmpty ? 'Size' : 'Size : $t';
}

/// Weight + its unit shown together, e.g. "9 gm" (a single card, no separate
/// Weight Unit cell).
String _weightValue(Map<String, String> a) {
  final w = (a['Weight'] ?? '').trim();
  final wu = (a['Weight Unit'] ?? '').trim();
  if (w.isEmpty) return '-';
  return wu.isEmpty ? w : '$w $wu';
}

String _lengthValue(Map<String, String> a) {
  final l = (a['Length'] ?? '').trim();
  final lu = (a['Length Unit'] ?? '').trim();
  if (l.isEmpty) return '-';
  return lu.isEmpty ? l : '$l $lu';
}

class _VariantsSection extends ConsumerStatefulWidget {
  const _VariantsSection({required this.productId});
  final String? productId;

  @override
  ConsumerState<_VariantsSection> createState() => _VariantsSectionState();
}

class _VariantsSectionState extends ConsumerState<_VariantsSection> {
  String? get productId => widget.productId;

  @override
  Widget build(BuildContext context) {
    if (productId == null) {
      return const _Hint(
          'Save the product first, then add its sizes (packs, rates).');
    }
    final variants = ref.watch(variantsByProductProvider(productId!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Sizes',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () => _openVariantForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add size'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        variants.when(
          loading: () =>
              const Padding(padding: EdgeInsets.all(16), child: LoadingView()),
          error: (e, _) => ErrorView(error: e),
          data: (items) {
            if (items.isEmpty) {
              return const _Hint('No sizes yet.');
            }
            return Column(
              children: [
                for (final v in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _VariantCard(
                      variant: v,
                      onEdit: () => _openVariantForm(existing: v),
                      onUpdateStock: () => _updateStock(v),
                      onDuplicate: () => _duplicate(v),
                      onDelete: () => _deleteVariant(v),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _openVariantForm({Variant? existing}) {
    showDialog(
      context: context,
      builder: (_) =>
          _VariantFormDialog(productId: productId!, existing: existing),
    );
  }

  void _updateStock(Variant v) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _UpdateStockSheet(variant: v),
    );
  }

  Future<void> _duplicate(Variant v) async {
    final copy = Variant(
      id: '',
      companyId: v.companyId,
      productId: v.productId,
      attributes: Map<String, String>.from(v.attributes),
      rate: v.rate,
      pack: v.pack,
      boxPack: v.boxPack,
      sku: v.sku == null ? null : '${v.sku}-copy',
      minStock: v.minStock,
      currentStock: 0,
      bom: v.bom,
    );
    await ref.read(variantRepositoryProvider).create(copy, openingStock: 0);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Size duplicated.')));
    }
  }

  Future<void> _deleteVariant(Variant v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete size'),
        content: Text(
            'Delete the “${_variantTitle(v)}” size? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kVDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(variantRepositoryProvider).delete(v.id);
  }
}

/// Modern variant (size) card: header + detail grid + a prominent blue stock
/// bar, and a ⋮ action sheet. Missing values render as "-".
class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.onEdit,
    required this.onUpdateStock,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Variant variant;
  final VoidCallback onEdit;
  final VoidCallback onUpdateStock;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final v = variant;
    final a = v.attributes;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.straighten, color: _kVPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _variantTitle(v),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showMenu(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Full-width detail cards (Size Unit is already in the header;
              // Weight/Length show their unit inline). Two cells per row keeps
              // each card wide enough to show the whole value, then the stock
              // bar spans below.
              _grid(
                context,
                ['Weight', 'Length'],
                [_weightValue(a), _lengthValue(a)],
              ),
              const SizedBox(height: 8),
              _grid(
                context,
                ['Price', 'Pack', 'Box'],
                [
                  v.rate > 0 ? Formatters.money(v.rate) : '-',
                  v.pack > 0 ? '${v.pack}' : '-',
                  v.boxPack > 0 ? '${v.boxPack}' : '-',
                ],
              ),
              const SizedBox(height: 12),
              _StockBar(variant: v),
            ],
          ),
        ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Variant'),
              onTap: () {
                Navigator.pop(sheet);
                onEdit();
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Update Stock'),
              onTap: () {
                Navigator.pop(sheet);
                onUpdateStock();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate Variant'),
              onTap: () {
                Navigator.pop(sheet);
                onDuplicate();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _kVDanger),
              title: const Text('Delete Variant',
                  style: TextStyle(color: _kVDanger)),
              onTap: () {
                Navigator.pop(sheet);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, List<String> labels, List<String> values) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(child: _cell(context, labels[i], values[i])),
          if (i < labels.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _cell(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          // Scale the value down to fit the card width so the whole number
          // shows (e.g. ₹200.00) instead of being clipped to "2…".
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockBar extends StatelessWidget {
  const _StockBar({required this.variant});
  final Variant variant;

  @override
  Widget build(BuildContext context) {
    final v = variant;
    final scheme = Theme.of(context).colorScheme;
    final (label, fg) = v.currentStock <= 0
        ? ('Out of Stock', _kVDanger)
        : v.currentStock <= v.minStock
            ? ('Low Stock', _kVWarning)
            : ('In Stock', _kVSuccess);
    final bg = fg.withValues(alpha: 0.15);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text('Stock',
              style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 14),
          Text(Formatters.qty(v.currentStock),
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Compact bottom sheet to set a size's stock on hand (records an adjustment).
class _UpdateStockSheet extends ConsumerStatefulWidget {
  const _UpdateStockSheet({required this.variant});
  final Variant variant;

  @override
  ConsumerState<_UpdateStockSheet> createState() => _UpdateStockSheetState();
}

class _UpdateStockSheetState extends ConsumerState<_UpdateStockSheet> {
  late final TextEditingController _stock =
      TextEditingController(text: '${widget.variant.currentStock}');
  bool _saving = false;

  @override
  void dispose() {
    _stock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newStock = int.tryParse(_stock.text.trim());
    if (newStock == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(variantRepositoryProvider).updateWithStock(
            widget.variant,
            previousStock: widget.variant.currentStock,
            newStock: newStock,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Update stock · ${_variantTitle(widget.variant)}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Current: ${Formatters.qty(widget.variant.currentStock)}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _stock,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'New total stock',
              helperText: 'Records a stock adjustment for the difference',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _kVPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _VariantFormDialog extends ConsumerStatefulWidget {
  const _VariantFormDialog({required this.productId, this.existing});
  final String productId;
  final Variant? existing;

  @override
  ConsumerState<_VariantFormDialog> createState() => _VariantFormState();
}

class _VariantFormState extends ConsumerState<_VariantFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rate;
  late final TextEditingController _pack;
  late final TextEditingController _boxPack;
  late final TextEditingController _minStock;
  late final TextEditingController _openingStock;
  late final TextEditingController _length;
  late final TextEditingController _size;
  late final TextEditingController _weight;
  List<MapEntry<String, String>> _attributes = const [];
  String? _sizeUnit;
  String? _lengthUnit;
  String? _weightUnit;
  // Bill of materials: raw-material variants consumed per unit produced.
  late List<BomLine> _bom;
  bool _saving = false;

  // Preset unit options for the structured Size / Length / Weight inputs.
  static const List<String> _sizeUnitOptions = ['inch', 'mm'];
  static const List<String> _lengthUnitOptions = ['mtr', 'ft'];
  static const List<String> _weightUnitOptions = ['gm', 'kg'];

  // Attribute keys handled by the structured inputs below (kept out of the
  // free-form KeyValueEditor so they are not edited/saved twice).
  static const Set<String> _managedKeys = {
    'Size',
    'Size Unit',
    'Length',
    'Length Unit',
    'Weight',
    'Weight Unit',
  };

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    _rate = TextEditingController(text: v?.rate.toString() ?? '');
    // Pack / Box default to empty (null) — the admin fills them in.
    _pack = TextEditingController(
        text: (v != null && v.pack > 0) ? '${v.pack}' : '');
    _boxPack = TextEditingController(
        text: (v != null && v.boxPack > 0) ? '${v.boxPack}' : '');
    _minStock = TextEditingController(text: (v?.minStock ?? 0).toString());
    // On create this is the opening stock; on edit it is the current stock on
    // hand (editable — changing it records a stock adjustment).
    _openingStock =
        TextEditingController(text: (v?.currentStock ?? 0).toString());

    // Pre-fill the structured Size + Length inputs from existing attributes.
    final map = v?.attributes ?? const <String, String>{};
    _size = TextEditingController(text: map['Size'] ?? '');
    _sizeUnit = (map['Size Unit']?.isNotEmpty ?? false) ? map['Size Unit'] : null;
    _lengthUnit =
        (map['Length Unit']?.isNotEmpty ?? false) ? map['Length Unit'] : null;
    _length = TextEditingController(text: map['Length'] ?? '');
    _weightUnit =
        (map['Weight Unit']?.isNotEmpty ?? false) ? map['Weight Unit'] : null;
    _weight = TextEditingController(text: map['Weight'] ?? '');

    // Remaining (non-managed) attributes stay in the free-form editor.
    _attributes = map.entries
        .where((e) => !_managedKeys.contains(e.key))
        .map((e) => MapEntry(e.key, e.value))
        .toList();

    _bom = [...?v?.bom];
  }

  @override
  void dispose() {
    _rate.dispose();
    _pack.dispose();
    _boxPack.dispose();
    _minStock.dispose();
    _openingStock.dispose();
    _length.dispose();
    _size.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Builds dropdown items from [options], appending [current] when it is a
  /// saved value that isn't one of the presets (so editing never asserts).
  List<DropdownMenuItem<String>> _optionItems(
      List<String> options, String? current) {
    final values = [
      ...options,
      if (current != null && current.isNotEmpty && !options.contains(current))
        current,
    ];
    return [
      for (final o in values) DropdownMenuItem(value: o, child: Text(o)),
    ];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(variantRepositoryProvider);
      final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
          AppConstants.defaultCompanyId;
      final attrs = {for (final e in _attributes) e.key: e.value};
      // Merge the structured Size + Length inputs. Only include a key when it
      // has a value so empty fields don't write blank attributes.
      final sizeText = _size.text.trim();
      if (sizeText.isNotEmpty) attrs['Size'] = sizeText;
      if (_sizeUnit != null && _sizeUnit!.isNotEmpty) {
        attrs['Size Unit'] = _sizeUnit!;
      }
      final lengthText = _length.text.trim();
      if (lengthText.isNotEmpty) attrs['Length'] = lengthText;
      if (_lengthUnit != null && _lengthUnit!.isNotEmpty) {
        attrs['Length Unit'] = _lengthUnit!;
      }
      final weightText = _weight.text.trim();
      if (weightText.isNotEmpty) attrs['Weight'] = weightText;
      if (_weightUnit != null && _weightUnit!.isNotEmpty) {
        attrs['Weight Unit'] = _weightUnit!;
      }
      final enteredStock = int.tryParse(_openingStock.text.trim()) ??
          (widget.existing?.currentStock ?? 0);
      final variant = Variant(
        id: widget.existing?.id ?? '',
        companyId: companyId,
        productId: widget.productId,
        attributes: attrs,
        rate: double.tryParse(_rate.text.trim()) ?? 0,
        pack: int.tryParse(_pack.text.trim()) ?? 0,
        boxPack: int.tryParse(_boxPack.text.trim()) ?? 0,
        minStock: int.tryParse(_minStock.text.trim()) ?? 0,
        currentStock: enteredStock,
        bom: _bom.where((b) => b.rawVariantId.isNotEmpty && b.qty > 0).toList(),
      );
      if (_isEdit) {
        // Persist attribute/rate edits and, if the stock changed, record an
        // adjustment so the ledger + cached stock stay in sync.
        await repo.updateWithStock(
          variant,
          previousStock: widget.existing!.currentStock,
          newStock: enteredStock,
        );
      } else {
        await repo.create(variant, openingStock: enteredStock);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Raw materials consumed per unit produced. Each line picks a raw-material
  /// variant and a quantity in that variant's own unit.
  Widget _buildBomSection(BuildContext context) {
    final theme = Theme.of(context);
    final rawVariants = ref.watch(rawVariantsProvider).valueOrNull ?? const [];
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? const [];
    final names = {for (final m in materials) m.id: m.name};

    String labelFor(RawMaterialVariant v) {
      final mat = names[v.rawMaterialId] ?? 'Material';
      return '$mat · ${v.label} (${v.unit})';
    }

    final sorted = [...rawVariants]
      ..sort((a, b) => labelFor(a).toLowerCase().compareTo(
            labelFor(b).toLowerCase(),
          ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Raw materials used',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              onPressed: rawVariants.isEmpty
                  ? null
                  : () => setState(
                      () => _bom.add(const BomLine(rawVariantId: '', qty: 0))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        Text(
          rawVariants.isEmpty
              ? 'Add raw materials (with variants) first to link them here.'
              : 'Consumed from raw-material stock when this size is dispatched.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        for (var i = 0; i < _bom.length; i++) ...[
          const SizedBox(height: AppSpacing.sm),
          Builder(builder: (_) {
            final line = _bom[i];
            // The selected raw variant (if it still exists) → drives the unit.
            final selected = sorted
                .where((v) => v.id == line.rawVariantId)
                .cast<RawMaterialVariant?>()
                .firstOrNull;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        line.rawVariantId.isEmpty ? null : line.rawVariantId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'Raw material'),
                    items: [
                      for (final v in sorted)
                        DropdownMenuItem(
                            value: v.id,
                            child: Text(labelFor(v),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (id) => setState(() {
                      _bom[i] =
                          BomLine(rawVariantId: id ?? '', qty: _bom[i].qty);
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('bomqty_$i'),
                    initialValue: line.qty > 0 ? fmtQty(line.qty) : '',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Qty / unit',
                      suffixText: selected?.unit,
                    ),
                    onChanged: (t) => _bom[i] = BomLine(
                        rawVariantId: _bom[i].rawVariantId,
                        qty: double.tryParse(t.trim()) ?? 0),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _bom.removeAt(i)),
                ),
              ],
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Size' : 'Add Size'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 96).clamp(260.0, 460.0).toDouble(),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Size & Length',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _size,
                      decoration: const InputDecoration(
                          labelText: 'Size', hintText: 'e.g. 1/2'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sizeUnit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Size unit'),
                      items: _optionItems(_sizeUnitOptions, _sizeUnit),
                      onChanged: (v) => setState(() => _sizeUnit = v),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _length,
                      decoration: const InputDecoration(labelText: 'Length'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _lengthUnit,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Length unit'),
                      items: _optionItems(_lengthUnitOptions, _lengthUnit),
                      onChanged: (v) => setState(() => _lengthUnit = v),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weight,
                      decoration: const InputDecoration(labelText: 'Weight'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _weightUnit,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Weight unit'),
                      items: _optionItems(_weightUnitOptions, _weightUnit),
                      onChanged: (v) => setState(() => _weightUnit = v),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                KeyValueEditor(
                  title: 'Other attributes',
                  keyHint: 'e.g. Color',
                  valueHint: 'e.g. Red',
                  initial: _attributes,
                  onChanged: (v) => _attributes = v,
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildBomSection(context),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rate,
                      decoration: const InputDecoration(labelText: 'Rate'),
                      keyboardType: TextInputType.number,
                      validator: (v) => Validators.number(v, field: 'Rate'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _pack,
                      decoration: const InputDecoration(labelText: 'Pack'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _boxPack,
                      decoration: const InputDecoration(labelText: 'Box pack'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minStock,
                      decoration: const InputDecoration(labelText: 'Min stock'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _openingStock,
                  decoration: InputDecoration(
                    labelText: _isEdit ? 'Current stock' : 'Opening stock',
                    helperText: _isEdit
                        ? 'Changing this records a stock adjustment'
                        : 'Records an opening inventory transaction',
                  ),
                  keyboardType: TextInputType.number,
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
