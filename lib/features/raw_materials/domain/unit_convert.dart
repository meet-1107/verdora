import 'raw_material.dart' show rawMaterialUnitTypes;

/// Factor of each unit relative to its dimension's base unit. Used to convert a
/// bill-of-materials quantity entered in one unit (e.g. grams) into the raw
/// material's own unit (e.g. kg) so stock is consumed correctly.
///
/// Bases: Weight → gram, Length → mm, Size(area) → sq cm, Volume → ml,
/// Pieces → piece (box/pack aren't linearly convertible, treated as 1).
const Map<String, double> _unitFactors = {
  // Weight (base: gram)
  'kg': 1000, 'gram': 1, 'mg': 0.001, 'ton': 1000000, 'quintal': 100000,
  // Length (base: mm)
  'meter': 1000, 'cm': 10, 'mm': 1, 'feet': 304.8, 'inch': 25.4,
  // Size / area (base: sq cm)
  'sq meter': 10000, 'sq cm': 1, 'sq inch': 6.4516, 'sq feet': 929.0304,
  // Volume (base: ml)
  'litre': 1000, 'ml': 1, 'gallon': 3785.41, 'cubic meter': 1000000,
  // Pieces (base: piece)
  'pcs': 1, 'nos': 1, 'dozen': 12, 'box': 1, 'pack': 1,
};

/// The unit type (Weight/Length/…) a [unit] belongs to, or null if unknown.
String? dimensionOfUnit(String unit) {
  for (final entry in rawMaterialUnitTypes.entries) {
    if (entry.value.contains(unit)) return entry.key;
  }
  return null;
}

/// Units in the same dimension as [unit] (for a "sub-unit" dropdown). Falls back
/// to just [unit] when it isn't a known unit.
List<String> unitsLike(String unit) {
  final dim = dimensionOfUnit(unit);
  if (dim == null) return [unit];
  return rawMaterialUnitTypes[dim]!;
}

/// Converts [value] from [from] to [to] when both are known units of the same
/// dimension; returns null if they can't be converted (unknown or different
/// dimensions), so callers can fall back to the raw value.
double? convertUnit(double value, String from, String to) {
  if (from == to) return value;
  final f = _unitFactors[from];
  final t = _unitFactors[to];
  if (f == null || t == null) return null;
  if (dimensionOfUnit(from) != dimensionOfUnit(to)) return null;
  return value * f / t;
}
