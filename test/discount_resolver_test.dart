import 'package:b2b_saas/features/discounts/domain/discount.dart';
import 'package:b2b_saas/features/discounts/logic/discount_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

Discount d(DiscountScope scope, double percent, {String? targetId}) => Discount(
    id: 'x',
    companyId: 'c',
    scope: scope,
    percent: percent,
    targetId: targetId);

const ctx = DiscountContext(
  variantId: 'v1',
  productId: 'p1',
  categoryId: 'cat1',
  partyId: 'party1',
  partyDefaultDiscount: 5,
);

void main() {
  group('DiscountResolver', () {
    test('falls back to party default when nothing matches', () {
      expect(const DiscountResolver([]).resolve(ctx), 5);
    });

    test('global applies when present', () {
      final r = DiscountResolver([d(DiscountScope.global, 8)]);
      expect(r.resolve(ctx), 8);
    });

    test('higher-priority scope wins over lower', () {
      final r = DiscountResolver([
        d(DiscountScope.global, 8),
        d(DiscountScope.party, 10, targetId: 'party1'),
        d(DiscountScope.variant, 20, targetId: 'v1'),
        d(DiscountScope.category, 12, targetId: 'cat1'),
      ]);
      expect(r.resolve(ctx), 20); // variant beats all
    });

    test('non-matching targets are ignored', () {
      final r = DiscountResolver([
        d(DiscountScope.variant, 30, targetId: 'other'),
        d(DiscountScope.product, 15, targetId: 'p1'),
      ]);
      expect(r.resolve(ctx), 15);
    });

    test('inactive discounts are skipped', () {
      final r = DiscountResolver([
        Discount(
            id: 'x',
            companyId: 'c',
            scope: DiscountScope.variant,
            percent: 50,
            targetId: 'v1',
            status: 'archived'),
      ]);
      expect(r.resolve(ctx), 5); // back to party default
    });
  });
}
