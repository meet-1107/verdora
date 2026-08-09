import 'package:b2b_saas/features/orders/domain/order_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderStatus', () {
    test('fromValue round-trips', () {
      for (final s in OrderStatus.values) {
        expect(OrderStatus.fromValue(s.value), s);
      }
    });

    test('pending can be approved or rejected', () {
      expect(OrderStatus.pending.nextStates,
          containsAll([OrderStatus.approved, OrderStatus.rejected]));
    });

    test('lifecycle advances approved -> packing -> ... -> completed', () {
      expect(OrderStatus.approved.nextStates, contains(OrderStatus.packing));
      expect(OrderStatus.packing.nextStates, contains(OrderStatus.packed));
      expect(OrderStatus.packed.nextStates, contains(OrderStatus.dispatched));
      expect(
          OrderStatus.dispatched.nextStates, contains(OrderStatus.delivered));
      expect(OrderStatus.delivered.nextStates, contains(OrderStatus.completed));
    });

    test('terminal states have no transitions', () {
      expect(OrderStatus.completed.isTerminal, isTrue);
      expect(OrderStatus.completed.nextStates, isEmpty);
      expect(OrderStatus.rejected.isTerminal, isTrue);
      expect(OrderStatus.cancelled.isTerminal, isTrue);
    });
  });
}
