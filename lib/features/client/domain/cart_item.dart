/// A line in the client's shopping cart (in-memory until the order is submitted).
class CartItem {
  const CartItem({
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.rate,
    required this.quantity,
    this.discountPercent = 0,
  });

  final String variantId;
  final String productName;
  final String variantLabel;
  final double rate;
  final int quantity;
  final double discountPercent;

  double get gross => rate * quantity;
  double get discountAmount => gross * discountPercent / 100;
  double get total => gross - discountAmount;

  CartItem copyWith({int? quantity, double? discountPercent}) => CartItem(
        variantId: variantId,
        productName: productName,
        variantLabel: variantLabel,
        rate: rate,
        quantity: quantity ?? this.quantity,
        discountPercent: discountPercent ?? this.discountPercent,
      );
}
