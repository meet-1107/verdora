import '../domain/import_models.dart';

/// The application fields a product spreadsheet can be mapped onto, with rich
/// synonyms so headers from any supplier auto-detect. Only [productName] is
/// mandatory; everything else is optional and defaults sensibly.
class ProductImportConfig {
  ProductImportConfig._();

  static const productName = 'productName';
  static const category = 'category';
  static const subcategory = 'subcategory';
  static const variant = 'variant';
  static const pack = 'pack';
  static const boxPack = 'boxPack';
  static const rate = 'rate';
  static const sku = 'sku';
  static const barcode = 'barcode';
  static const openingStock = 'openingStock';
  static const minStock = 'minStock';

  static const fields = <ImportField>[
    ImportField(
      key: productName,
      label: 'Product Name',
      required: true,
      synonyms: ['item name', 'item', 'material', 'description', 'product'],
    ),
    ImportField(
      key: category,
      label: 'Category',
      synonyms: ['group', 'category name', 'product category'],
    ),
    ImportField(
      key: subcategory,
      label: 'Subcategory',
      synonyms: ['sub category', 'sub-category', 'type'],
    ),
    ImportField(
      key: variant,
      label: 'Size',
      hint: 'Stored as a variant attribute',
      synonyms: [
        'variant',
        'diameter',
        'dimension',
        'colour',
        'color',
        'model'
      ],
    ),
    ImportField(
      key: pack,
      label: 'Pack',
      synonyms: ['pieces', 'qty', 'pack size', 'bundle', 'inner'],
    ),
    ImportField(
      key: boxPack,
      label: 'Box Pack',
      synonyms: ['box qty', 'box', 'carton', 'master pack', 'outer'],
    ),
    ImportField(
      key: rate,
      label: 'Rate',
      synonyms: [
        'price',
        'dealer price',
        'dealer rate',
        'mrp',
        'amount',
        'cost'
      ],
    ),
    ImportField(
      key: sku,
      label: 'SKU',
      synonyms: ['code', 'item code', 'product code', 'article'],
    ),
    ImportField(
      key: barcode,
      label: 'Barcode',
      synonyms: ['ean', 'upc', 'bar code'],
    ),
    ImportField(
      key: openingStock,
      label: 'Opening Stock',
      synonyms: ['stock', 'qty on hand', 'inventory', 'opening'],
    ),
    ImportField(
      key: minStock,
      label: 'Min Stock',
      synonyms: ['minimum stock', 'reorder', 'reorder level'],
    ),
  ];
}
