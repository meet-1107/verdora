import '../domain/import_models.dart';

/// Application fields a party/customer spreadsheet can map onto. Party ID and
/// Name are mandatory; a Password column is optional (a default is generated
/// when absent).
class PartyImportConfig {
  PartyImportConfig._();

  static const partyCode = 'partyCode';
  static const name = 'name';
  static const ownerName = 'ownerName';
  static const phone = 'phone';
  static const whatsapp = 'whatsapp';
  static const email = 'email';
  static const gstNumber = 'gstNumber';
  static const address = 'address';
  static const city = 'city';
  static const state = 'state';
  static const pincode = 'pincode';
  static const transport = 'transport';
  static const paymentTerms = 'paymentTerms';
  static const creditLimit = 'creditLimit';
  static const defaultDiscount = 'defaultDiscount';
  static const password = 'password';

  static const fields = <ImportField>[
    ImportField(
      key: partyCode,
      label: 'Party ID',
      required: true,
      synonyms: ['party code', 'code', 'dealer id', 'customer id', 'account'],
    ),
    ImportField(
      key: name,
      label: 'Party Name',
      required: true,
      synonyms: ['name', 'firm', 'shop name', 'customer', 'dealer name'],
    ),
    ImportField(
        key: ownerName,
        label: 'Owner Name',
        synonyms: ['contact', 'proprietor']),
    ImportField(
        key: phone,
        label: 'Phone',
        synonyms: ['mobile', 'contact number', 'phone number']),
    ImportField(
        key: whatsapp, label: 'WhatsApp', synonyms: ['whatsapp number']),
    ImportField(key: email, label: 'Email', synonyms: ['email id', 'e-mail']),
    ImportField(
        key: gstNumber, label: 'GST Number', synonyms: ['gst', 'gstin']),
    ImportField(key: address, label: 'Address', synonyms: ['addr', 'street']),
    ImportField(key: city, label: 'City', synonyms: ['town']),
    ImportField(key: state, label: 'State', synonyms: ['province']),
    ImportField(
        key: pincode,
        label: 'Pincode',
        synonyms: ['pin', 'zip', 'postal code']),
    ImportField(
        key: transport,
        label: 'Transport',
        synonyms: ['transporter', 'courier']),
    ImportField(
        key: paymentTerms,
        label: 'Payment Terms',
        synonyms: ['terms', 'credit days']),
    ImportField(key: creditLimit, label: 'Credit Limit', synonyms: ['limit']),
    ImportField(
      key: defaultDiscount,
      label: 'Default Discount',
      synonyms: ['discount', 'disc %', 'discount percent'],
    ),
    ImportField(
      key: password,
      label: 'Password',
      hint: 'Login password; a default is generated if empty',
      synonyms: ['pass', 'pwd', 'login password'],
    ),
  ];
}
