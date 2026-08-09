/// Roles supported by the platform. Only [admin] and [client] are active now;
/// the others are reserved so routing/permissions can expand without a schema
/// migration.
enum UserRole {
  superAdmin('super_admin'),
  admin('admin'),
  manager('manager'), // future
  client('client'),
  warehouse('warehouse'), // future
  delivery('delivery'); // future

  const UserRole(this.value);
  final String value;

  static UserRole fromValue(String? value) {
    return UserRole.values.firstWhere(
      (r) => r.value == value,
      orElse: () => UserRole.client,
    );
  }

  bool get isAdminSide =>
      this == UserRole.superAdmin ||
      this == UserRole.admin ||
      this == UserRole.manager;

  bool get isClient => this == UserRole.client;
}
