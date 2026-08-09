import 'package:cloud_firestore/cloud_firestore.dart';

/// What a discount applies to. Higher [priority] wins when several match the
/// same line: Variant → Product → Subcategory → Category → Party → Global.
enum DiscountScope {
  variant('variant', 5),
  product('product', 4),
  subcategory('subcategory', 3),
  category('category', 2),
  party('party', 1),
  global('global', 0);

  const DiscountScope(this.value, this.priority);
  final String value;
  final int priority;

  static DiscountScope fromValue(String? v) => DiscountScope.values.firstWhere(
        (s) => s.value == v,
        orElse: () => DiscountScope.global,
      );

  String get label => switch (this) {
        DiscountScope.variant => 'Size',
        DiscountScope.product => 'Product',
        DiscountScope.subcategory => 'Subcategory',
        DiscountScope.category => 'Category',
        DiscountScope.party => 'Party',
        DiscountScope.global => 'Global',
      };

  bool get needsTarget => this != DiscountScope.global;
}

/// A discount rule (`discounts/{id}`).
class Discount {
  const Discount({
    required this.id,
    required this.companyId,
    required this.scope,
    required this.percent,
    this.targetId,
    this.targetLabel,
    this.partyId,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String companyId;
  final DiscountScope scope;
  final double percent;

  /// Id of the variant/product/subcategory/category this applies to
  /// (null = global).
  final String? targetId;
  final String? targetLabel; // human-readable, for the list UI

  /// When set, this rule applies ONLY to that party (dealer). When null it is a
  /// general rule that applies to everyone.
  final String? partyId;
  final String status;
  final DateTime? createdAt;

  bool get isActive => status == 'active';

  factory Discount.fromMap(String id, Map<String, dynamic> map) {
    return Discount(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      scope: DiscountScope.fromValue(map['scope'] as String?),
      percent: (map['percent'] as num?)?.toDouble() ?? 0,
      targetId: map['targetId'] as String?,
      targetLabel: map['targetLabel'] as String?,
      partyId: map['partyId'] as String?,
      status: map['status'] as String? ?? 'active',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'scope': scope.value,
        'percent': percent,
        'targetId': targetId,
        'targetLabel': targetLabel,
        'partyId': partyId,
        'status': status,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };
}
