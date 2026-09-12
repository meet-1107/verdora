/// Central registry of Firestore collection names.
/// Keeping these in one place avoids typo bugs and eases refactors.
class Collections {
  Collections._();

  static const users = 'users';
  static const roles = 'roles';
  static const companies = 'companies';
  static const parties = 'parties';
  static const categories = 'categories';
  static const subcategories = 'subcategories';
  static const products = 'products';
  static const variants = 'variants';
  static const inventoryTransactions = 'inventory_transactions';
  static const orders = 'orders';
  static const orderItems = 'order_items';
  static const discounts = 'discounts';
  static const notifications = 'notifications';
  static const settings = 'settings';
  static const logs = 'logs';
  static const invoiceCounter = 'invoice_counter';
  static const orderCounters = 'order_counters';
  static const importTemplates = 'import_templates';
  static const rawMaterials = 'raw_materials';
  static const rawMaterialVariants = 'raw_material_variants';
  static const rawMaterialTransactions = 'raw_material_transactions';
}
