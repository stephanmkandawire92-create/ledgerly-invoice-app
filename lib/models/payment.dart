import 'dart:convert';

class Payment {
  final String id;
  final String invoiceId;
  final DateTime paymentDate;
  final double amount;
  final String method; // Bank Transfer, Cash, Credit Card, EFT, Cheque, Other
  final String reference;
  final String notes;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.invoiceId,
    required this.paymentDate,
    required this.amount,
    this.method = 'Bank Transfer',
    this.reference = '',
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceId': invoiceId,
        'paymentDate': paymentDate.toIso8601String(),
        'amount': amount,
        'method': method,
        'reference': reference,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        invoiceId: json['invoiceId'] as String? ?? '',
        paymentDate: json['paymentDate'] != null
            ? DateTime.tryParse(json['paymentDate'] as String) ?? DateTime.now()
            : DateTime.now(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        method: json['method'] as String? ?? 'Bank Transfer',
        reference: json['reference'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  Payment copyWith({
    String? id,
    String? invoiceId,
    DateTime? paymentDate,
    double? amount,
    String? method,
    String? reference,
    String? notes,
    DateTime? createdAt,
  }) {
    return Payment(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      paymentDate: paymentDate ?? this.paymentDate,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static String encodeList(List<Payment> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<Payment> decodeList(String source) {
    if (source.trim().isEmpty) return [];
    final List<dynamic> jsonList = jsonDecode(source) as List<dynamic>;
    return jsonList
        .map((e) => Payment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
