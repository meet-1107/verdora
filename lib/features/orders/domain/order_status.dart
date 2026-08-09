/// The full order lifecycle. Terminal states: completed, rejected, cancelled.
enum OrderStatus {
  draft('draft'),
  pending('pending'),
  approved('approved'),
  modifiedApproved('modified_approved'),
  packing('packing'),
  packed('packed'),
  dispatched('dispatched'),
  delivered('delivered'),
  completed('completed'),
  rejected('rejected'),
  cancelled('cancelled'),
  returned('returned');

  const OrderStatus(this.value);
  final String value;

  static OrderStatus fromValue(String? v) => OrderStatus.values.firstWhere(
        (s) => s.value == v,
        orElse: () => OrderStatus.pending,
      );

  String get label => switch (this) {
        OrderStatus.draft => 'Draft',
        OrderStatus.pending => 'Pending',
        OrderStatus.approved => 'Approved',
        OrderStatus.modifiedApproved => 'Modified & Approved',
        OrderStatus.packing => 'Packing',
        OrderStatus.packed => 'Packed',
        OrderStatus.dispatched => 'Dispatched',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.completed => 'Completed',
        OrderStatus.rejected => 'Rejected',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.returned => 'Returned',
      };

  // NOTE: `delivered` and `completed` are retained only so historical orders
  // parse correctly; they are no longer part of the live workflow. Dispatched is
  // the final fulfilment state.
  bool get isTerminal =>
      this == OrderStatus.dispatched ||
      this == OrderStatus.delivered ||
      this == OrderStatus.completed ||
      this == OrderStatus.rejected ||
      this == OrderStatus.cancelled ||
      this == OrderStatus.returned;

  /// Valid next states, used to render admin action buttons and validate
  /// transitions server-side. The flow ends at `dispatched`.
  List<OrderStatus> get nextStates => switch (this) {
        OrderStatus.pending => [OrderStatus.approved, OrderStatus.rejected],
        OrderStatus.approved => [OrderStatus.packing, OrderStatus.cancelled],
        OrderStatus.modifiedApproved => [
            OrderStatus.packing,
            OrderStatus.cancelled
          ],
        OrderStatus.packing => [OrderStatus.packed],
        OrderStatus.packed => [OrderStatus.dispatched],
        _ => const [],
      };
}
