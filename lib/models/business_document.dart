import 'dart:convert';

enum DocumentKind { invoice, quote }

class DocumentLine {
  DocumentLine({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String id;
  String description;
  double quantity;
  double unitPrice;

  double get amount => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory DocumentLine.fromJson(Map<String, dynamic> json) => DocumentLine(
        id: json['id'] as String? ?? '',
        description: json['description'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      );
}

class BusinessDocument {
  BusinessDocument({
    required this.id,
    required this.number,
    required this.kind,
    required this.clientName,
    required this.clientEmail,
    required this.issueDate,
    required this.dueDate,
    required this.status,
    required this.currencyCode,
    required this.lines,
    required this.taxPercent,
    required this.discount,
    required this.notes,
    this.customerId = '',
  });

  final String id;
  String number;
  DocumentKind kind;
  String clientName;
  String clientEmail;
  DateTime issueDate;
  DateTime dueDate;
  String status;
  String currencyCode;
  List<DocumentLine> lines;
  double taxPercent;
  double discount;
  String notes;
  String customerId;

  double get subtotal => lines.fold<double>(0, (sum, line) {
        final quantity = line.quantity.isFinite ? line.quantity.clamp(0, 1e9).toDouble() : 0.0;
        final price = line.unitPrice.isFinite ? line.unitPrice.clamp(0, 1e12).toDouble() : 0.0;
        return sum + quantity * price;
      });

  double get taxableAmount => (subtotal - discount).clamp(0, double.infinity).toDouble();
  double get taxAmount => taxableAmount * taxPercent.clamp(0, 100).toDouble() / 100;
  double get total => taxableAmount + taxAmount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'kind': kind.name,
        'clientName': clientName,
        'clientEmail': clientEmail,
        'issueDate': issueDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'status': status,
        'currencyCode': currencyCode,
        'lines': lines.map((line) => line.toJson()).toList(),
        'taxPercent': taxPercent,
        'discount': discount,
        'notes': notes,
        'customerId': customerId,
      };

  factory BusinessDocument.fromJson(Map<String, dynamic> json) => BusinessDocument(
        id: json['id'] as String? ?? '',
        number: json['number'] as String? ?? '',
        kind: DocumentKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => DocumentKind.invoice,
        ),
        clientName: json['clientName'] as String? ?? '',
        clientEmail: json['clientEmail'] as String? ?? '',
        issueDate: DateTime.tryParse(json['issueDate'] as String? ?? '') ?? DateTime.now(),
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? '') ?? DateTime.now(),
        status: json['status'] as String? ?? 'Draft',
        currencyCode: json['currencyCode'] as String? ?? 'ZAR',
        lines: (json['lines'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(DocumentLine.fromJson)
            .toList(),
        taxPercent: (json['taxPercent'] as num?)?.toDouble() ?? 0,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String? ?? '',
        customerId: json['customerId'] as String? ?? '',
      );

  static String encodeList(List<BusinessDocument> documents) =>
      jsonEncode(documents.map((document) => document.toJson()).toList());

  static List<BusinessDocument> decodeList(String source) =>
      (jsonDecode(source) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(BusinessDocument.fromJson)
          .toList();
}
