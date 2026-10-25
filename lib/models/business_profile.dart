import 'dart:convert';

class BusinessProfile {
  final String businessName;
  final String ownerName;
  final String email;
  final String phone;
  final String address;
  final String website;
  final String taxNumber;
  final String bankDetails;
  final String paymentTerms;
  final String currencyCode;
  final String invoicePrefix;
  final String quotePrefix;
  final String logoBase64;
  final String languageCode;

  BusinessProfile({
    this.businessName = 'My Business',
    this.ownerName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.website = '',
    this.taxNumber = '',
    this.bankDetails = '',
    this.paymentTerms = 'Payment due within 30 days.',
    this.currencyCode = 'USD',
    this.invoicePrefix = 'INV-',
    this.quotePrefix = 'QUO-',
    this.logoBase64 = '',
    this.languageCode = 'en',
  });

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'ownerName': ownerName,
        'email': email,
        'phone': phone,
        'address': address,
        'website': website,
        'taxNumber': taxNumber,
        'bankDetails': bankDetails,
        'paymentTerms': paymentTerms,
        'currencyCode': currencyCode,
        'invoicePrefix': invoicePrefix,
        'quotePrefix': quotePrefix,
        'logoBase64': logoBase64,
        'languageCode': languageCode,
      };

  factory BusinessProfile.fromJson(Map<String, dynamic> json) => BusinessProfile(
        businessName: json['businessName'] as String? ?? 'My Business',
        ownerName: json['ownerName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        address: json['address'] as String? ?? '',
        website: json['website'] as String? ?? '',
        taxNumber: json['taxNumber'] as String? ?? '',
        bankDetails: json['bankDetails'] as String? ?? '',
        paymentTerms: json['paymentTerms'] as String? ?? 'Payment due within 30 days.',
        currencyCode: json['currencyCode'] as String? ?? 'USD',
        invoicePrefix: json['invoicePrefix'] as String? ?? 'INV-',
        quotePrefix: json['quotePrefix'] as String? ?? 'QUO-',
        logoBase64: json['logoBase64'] as String? ?? '',
        languageCode: json['languageCode'] as String? ?? 'en',
      );

  BusinessProfile copyWith({
    String? businessName,
    String? ownerName,
    String? email,
    String? phone,
    String? address,
    String? website,
    String? taxNumber,
    String? bankDetails,
    String? paymentTerms,
    String? currencyCode,
    String? invoicePrefix,
    String? quotePrefix,
    String? logoBase64,
    String? languageCode,
  }) {
    return BusinessProfile(
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      website: website ?? this.website,
      taxNumber: taxNumber ?? this.taxNumber,
      bankDetails: bankDetails ?? this.bankDetails,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      currencyCode: currencyCode ?? this.currencyCode,
      invoicePrefix: invoicePrefix ?? this.invoicePrefix,
      quotePrefix: quotePrefix ?? this.quotePrefix,
      logoBase64: logoBase64 ?? this.logoBase64,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  String encode() => jsonEncode(toJson());

  factory BusinessProfile.decode(String source) {
    if (source.trim().isEmpty) return BusinessProfile();
    return BusinessProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }
}
