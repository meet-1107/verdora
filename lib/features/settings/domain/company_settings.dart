/// Company profile & invoice configuration (`settings/{companyId}`).
class CompanySettings {
  const CompanySettings({
    required this.companyId,
    this.name = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.gstNumber = '',
    this.invoicePrefix = 'INV',
    this.currency = '₹',
    this.supportNumber = '',
    this.terms = '',
    this.logoUrl = '',
  });

  final String companyId;
  final String name;
  final String address;
  final String phone;
  final String email;
  final String gstNumber;
  final String invoicePrefix;
  final String currency;
  final String supportNumber;
  final String terms;

  /// Company logo (Storage download URL or inline data: URI). Shown on the
  /// login screen and the client home header.
  final String logoUrl;

  CompanySettings copyWith({String? logoUrl}) => CompanySettings(
        companyId: companyId,
        name: name,
        address: address,
        phone: phone,
        email: email,
        gstNumber: gstNumber,
        invoicePrefix: invoicePrefix,
        currency: currency,
        supportNumber: supportNumber,
        terms: terms,
        logoUrl: logoUrl ?? this.logoUrl,
      );

  factory CompanySettings.fromMap(String companyId, Map<String, dynamic> map) {
    return CompanySettings(
      companyId: companyId,
      name: map['name'] as String? ?? '',
      address: map['address'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      gstNumber: map['gstNumber'] as String? ?? '',
      invoicePrefix: map['invoicePrefix'] as String? ?? 'INV',
      currency: map['currency'] as String? ?? '₹',
      supportNumber: map['supportNumber'] as String? ?? '',
      terms: map['terms'] as String? ?? '',
      logoUrl: map['logoUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        'gstNumber': gstNumber,
        'invoicePrefix': invoicePrefix,
        'currency': currency,
        'supportNumber': supportNumber,
        'terms': terms,
        'logoUrl': logoUrl,
      };
}
