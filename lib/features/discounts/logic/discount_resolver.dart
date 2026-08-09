import '../domain/discount.dart';

/// The context of a single line for which a discount is being resolved.
class DiscountContext {
  const DiscountContext({
    required this.variantId,
    required this.productId,
    required this.categoryId,
    required this.partyId,
    this.subcategoryId = '',
    this.partyDefaultDiscount = 0,
  });

  final String variantId;
  final String productId;
  final String categoryId;
  final String subcategoryId;
  final String partyId;
  final double partyDefaultDiscount;
}

/// Resolves the effective discount percent by priority
/// (Variant → Product → Subcategory → Category → Party → Global). If no rule
/// matches, the party's default discount is used as a baseline.
class DiscountResolver {
  const DiscountResolver(this.discounts);
  final List<Discount> discounts;

  double resolve(DiscountContext ctx) {
    Discount? best;
    var bestScore = -1;
    for (final d in discounts) {
      if (!d.isActive) continue;
      // A party-specific rule for a DIFFERENT party never applies.
      if (d.partyId != null && d.partyId != ctx.partyId) continue;
      if (!_targetMatches(d, ctx)) continue;
      // Party-specific rules always outrank general ones; within each tier the
      // more specific scope wins (variant > product > subcategory > category).
      final score = (d.partyId == ctx.partyId ? 100 : 0) + d.scope.priority;
      if (score > bestScore) {
        best = d;
        bestScore = score;
      }
    }
    // No matching rule → the party's global default discount is the baseline.
    if (best != null) return best.percent;
    return ctx.partyDefaultDiscount;
  }

  /// The most specific PRODUCT-level rule discount (variant/product/subcategory/
  /// category) for this party — WITHOUT the party's global default. Returns 0 if
  /// none. Used for the per-line deduction that happens BEFORE the global
  /// discount is applied to the order total (two-stage discounting).
  double resolveSpecific(DiscountContext ctx) {
    Discount? best;
    var bestScore = -1;
    for (final d in discounts) {
      if (!d.isActive) continue;
      if (d.partyId != null && d.partyId != ctx.partyId) continue;
      // Global / party-wide scopes are applied on the total, not per line.
      if (d.scope == DiscountScope.global || d.scope == DiscountScope.party) {
        continue;
      }
      if (!_targetMatches(d, ctx)) continue;
      final score = (d.partyId == ctx.partyId ? 100 : 0) + d.scope.priority;
      if (score > bestScore) {
        best = d;
        bestScore = score;
      }
    }
    return best?.percent ?? 0;
  }

  bool _targetMatches(Discount d, DiscountContext ctx) {
    return switch (d.scope) {
      DiscountScope.variant => d.targetId == ctx.variantId,
      DiscountScope.product => d.targetId == ctx.productId,
      DiscountScope.subcategory =>
        ctx.subcategoryId.isNotEmpty && d.targetId == ctx.subcategoryId,
      DiscountScope.category => d.targetId == ctx.categoryId,
      DiscountScope.party => d.targetId == ctx.partyId,
      DiscountScope.global => true,
    };
  }
}
