import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer / dealer (`parties/{id}`). Each party has a login (a `users` doc
/// with role `client` linked via `partyId`) provisioned by the admin.
class Party {
  const Party({
    required this.id,
    required this.companyId,
    required this.partyCode,
    required this.name,
    this.ownerName,
    this.phone,
    this.whatsapp,
    this.email,
    this.gstNumber,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.transport,
    this.paymentTerms,
    this.creditLimit = 0,
    this.defaultDiscount = 0,
    this.status = 'active',
    this.loginPassword,
    this.createdAt,
  });

  final String id;
  final String companyId;

  /// Human-facing party id used for login, e.g. "P00102".
  final String partyCode;
  final String name;
  final String? ownerName;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? gstNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? transport;
  final String? paymentTerms;
  final double creditLimit;
  final double defaultDiscount;
  final String status;

  /// The login password the admin set for this dealer. Stored so the admin can
  /// view/share it later. Only present for parties created after login storage
  /// was enabled. (Kept out of [toMap] so ordinary edits never overwrite it.)
  final String? loginPassword;
  final DateTime? createdAt;

  factory Party.fromMap(String id, Map<String, dynamic> map) {
    return Party(
      id: id,
      companyId: map['companyId'] as String? ?? 'default',
      partyCode: map['partyCode'] as String? ?? '',
      name: map['name'] as String? ?? '',
      ownerName: map['ownerName'] as String?,
      phone: map['phone'] as String?,
      whatsapp: map['whatsapp'] as String?,
      email: map['email'] as String?,
      gstNumber: map['gstNumber'] as String?,
      address: map['address'] as String?,
      city: map['city'] as String?,
      state: map['state'] as String?,
      pincode: map['pincode'] as String?,
      transport: map['transport'] as String?,
      paymentTerms: map['paymentTerms'] as String?,
      creditLimit: (map['creditLimit'] as num?)?.toDouble() ?? 0,
      defaultDiscount: (map['defaultDiscount'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'active',
      loginPassword: map['loginPassword'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'partyCode': partyCode,
        'name': name,
        'ownerName': ownerName,
        'phone': phone,
        'whatsapp': whatsapp,
        'email': email,
        'gstNumber': gstNumber,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'transport': transport,
        'paymentTerms': paymentTerms,
        'creditLimit': creditLimit,
        'defaultDiscount': defaultDiscount,
        'status': status,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };
}
