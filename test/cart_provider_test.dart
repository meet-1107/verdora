import 'package:b2b_saas/features/client/application/cart_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CartNotifier', () {
    late ProviderContainer c;
    setUp(() {
      c = ProviderContainer();
    });
    tearDown(() => c.dispose());

    void add(String id, {int qty = 1, double rate = 100, double disc = 0}) {
      c.read(cartProvider.notifier).addVariant(
            variantId: id,
            productName: 'P',
            variantLabel: 'L',
            rate: rate,
            qty: qty,
            discountPercent: disc,
          );
    }

    test('adding the same variant merges quantities', () {
      add('v1', qty: 2);
      add('v1', qty: 3);
      expect(c.read(cartProvider).length, 1);
      expect(c.read(cartProvider).single.quantity, 5);
    });

    test('totals reflect quantity and discount', () {
      add('v1', qty: 2, rate: 100, disc: 10); // 200 gross, 20 disc, 180 total
      add('v2', qty: 1, rate: 50); // 50
      expect(c.read(cartSubtotalProvider), 250);
      expect(c.read(cartDiscountProvider), 20);
      expect(c.read(cartTotalProvider), 230);
      expect(c.read(cartCountProvider), 3);
    });

    test('setQuantity to zero removes the line', () {
      add('v1', qty: 2);
      c.read(cartProvider.notifier).setQuantity('v1', 0);
      expect(c.read(cartProvider), isEmpty);
    });

    test('clear empties the cart', () {
      add('v1');
      add('v2');
      c.read(cartProvider.notifier).clear();
      expect(c.read(cartProvider), isEmpty);
    });
  });
}
