import 'dart:convert';

class Customer {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String billingAddress;
  final String shippingAddress;
  final String taxNumber;
  final String notes;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.billingAddress = '',
    this.shippingAddress = '',
    this.taxNumber = '',
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'billingAddress': billingAddress,
        'shippingAddress': shippingAddress,
        'taxNumber': taxNumber,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        billingAddress: json['billingAddress'] as String? ?? '',
        shippingAddress: json['shippingAddress'] as String? ?? '',
        taxNumber: json['taxNumber'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  Customer copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? billingAddress,
    String? shippingAddress,
    String? taxNumber,
    String? notes,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      billingAddress: billingAddress ?? this.billingAddress,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      taxNumber: taxNumber ?? this.taxNumber,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static String encodeList(List<Customer> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<Customer> decodeList(String source) {
    if (source.trim().isEmpty) return [];
    final List<dynamic> jsonList = jsonDecode(source) as List<dynamic>;
    return jsonList
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
