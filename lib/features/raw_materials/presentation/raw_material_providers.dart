import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';
import '../domain/raw_material_variant.dart';

/// All raw materials (parents) for the signed-in admin's company.
final rawMaterialsProvider = StreamProvider<List<RawMaterial>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(rawMaterialRepositoryProvider).watchAll(user.companyId);
});

/// All raw-material variants for the company (grouped by rawMaterialId in UI).
final rawVariantsProvider = StreamProvider<List<RawMaterialVariant>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(rawMaterialRepositoryProvider).watchVariants(user.companyId);
});

/// Variants for a single raw material.
final variantsOfProvider =
    Provider.family<List<RawMaterialVariant>, String>((ref, rawMaterialId) {
  final all = ref.watch(rawVariantsProvider).valueOrNull ?? const [];
  return all.where((v) => v.rawMaterialId == rawMaterialId).toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
});

/// A material is "simple" (no explicit sizes) when it has exactly one variant
/// with a blank label — its stock lives on that single default variant. A
/// material with named sizes ("1/2", "3/4") is variant-based instead.
bool isSimpleVariantList(List<RawMaterialVariant> vs) =>
    vs.length == 1 && vs.first.label.trim().isEmpty;

/// The 10 most recent raw-material stock entries for the company.
final rawRecentTxnsProvider = StreamProvider<List<RawMaterialTxn>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(rawMaterialRepositoryProvider)
      .watchTxns(user.companyId, limit: 10);
});

/// Every raw-material stock entry for the company (newest first).
final rawAllTxnsProvider = StreamProvider<List<RawMaterialTxn>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(rawMaterialRepositoryProvider).watchTxns(user.companyId);
});
