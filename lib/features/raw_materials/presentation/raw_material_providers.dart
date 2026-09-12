import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/raw_material_repository.dart';
import '../domain/raw_material.dart';

/// All raw materials for the signed-in admin's company.
final rawMaterialsProvider = StreamProvider<List<RawMaterial>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(rawMaterialRepositoryProvider).watchAll(user.companyId);
});

/// Stock movements for a single raw material.
final rawMaterialTxnsProvider =
    StreamProvider.family<List<RawMaterialTxn>, String>((ref, id) {
  return ref.watch(rawMaterialRepositoryProvider).watchTxns(id);
});
