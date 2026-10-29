import 'dart:convert';
import 'payment.dart';

enum DocumentKind { invoice, quote }

double roundMoney(double value) {
  if (!value.isFinite) return 0.0;
  return (value * 100).roundToDouble() / 100;
}

bool isPastDueDate(DateTime dueDate, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  return dueDay.isBefore(today);
}

String effectiveInvoiceStatus(
  BusinessDocument document,
  Iterable<Payment> payments, {
  DateTime? now,
  bool clearPaidWhenNoPayments = false,
}) {
  if (document.kind != DocumentKind.invoice ||
      document.status == 'Draft' ||
      document.status == 'Void') {
    return document.status;
  }

  final paid = payments
      .where((payment) =>
          payment.invoiceId == document.id &&
          payment.amount.isFinite &&
          payment.amount > 0)
      .fold<double>(0, (sum, payment) => sum + payment.amount);
  if (paid > 0) {
    if (paid + 0.004 >= document.total) return 'Paid';
    return isPastDueDate(document.dueDate, now: now) ? 'Overdue' : 'Pending';
  }

  if (document.status == 'Paid') {
    if (!clearPaidWhenNoPayments) return 'Paid';
    return isPastDueDate(document.dueDate, now: now) ? 'Overdue' : 'Sent';
  }
  if (isPastDueDate(document.dueDate, now: now)) return 'Overdue';
  if (document.status == 'Pending' || document.status == 'Overdue') {
    return 'Sent';
  }
  return document.status;
}

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

  double get amount {
    final safeQuantity =
        quantity.isFinite ? quantity.clamp(0.0, 1e9).toDouble() : 0.0;
    final safePrice =
        unitPrice.isFinite ? unitPrice.clamp(0.0, 1e12).toDouble() : 0.0;
    return roundMoney(safeQuantity * safePrice);
  }

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

  // Keep the same safe line amount for the editor, invoice totals, and PDF.
  // Monetary totals are rounded to cents at each documented calculation stage.
  double get subtotal =>
      roundMoney(lines.fold<double>(0, (sum, line) => sum + line.amount));

  double get safeDiscount {
    if (!discount.isFinite || discount <= 0) return 0;
    return roundMoney(discount.clamp(0.0, subtotal).toDouble());
  }

  double get safeTaxPercent =>
      taxPercent.isFinite ? taxPercent.clamp(0.0, 100.0).toDouble() : 0.0;

  double get taxableAmount => roundMoney(
      (subtotal - safeDiscount).clamp(0.0, double.infinity).toDouble());
  double get taxAmount => roundMoney(taxableAmount * safeTaxPercent / 100);
  double get total => roundMoney(taxableAmount + taxAmount);

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
        'taxPercent': safeTaxPercent,
        'discount': safeDiscount,
        'notes': notes,
        'customerId': customerId,
      };

  factory BusinessDocument.fromJson(Map<String, dynamic> json) =>
      BusinessDocument(
        id: json['id'] as String? ?? '',
        number: json['number'] as String? ?? '',
        kind: DocumentKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => DocumentKind.invoice,
        ),
        clientName: json['clientName'] as String? ?? '',
        clientEmail: json['clientEmail'] as String? ?? '',
        issueDate: DateTime.tryParse(json['issueDate'] as String? ?? '') ??
            DateTime.now(),
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? '') ??
            DateTime.now(),
        status: json['status'] as String? ?? 'Draft',
        currencyCode: json['currencyCode'] as String? ?? 'ZAR',
        lines: _decodeLines(json['lines']),
        taxPercent: (json['taxPercent'] as num?)?.toDouble() ?? 0,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String? ?? '',
        customerId: json['customerId'] as String? ?? '',
      );

  static List<DocumentLine> _decodeLines(Object? value) {
    if (value == null) return [];
    if (value is! List) {
      throw const FormatException('Document lines must be a list.');
    }
    return value.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Document contains an invalid line item.');
      }
      return DocumentLine.fromJson(entry);
    }).toList();
  }

  static String encodeList(List<BusinessDocument> documents) =>
      jsonEncode(documents.map((document) => document.toJson()).toList());

  static List<BusinessDocument> decodeList(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Saved documents must be a JSON list.');
    }
    return decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException(
            'Saved documents contain an invalid record.');
      }
      return BusinessDocument.fromJson(entry);
    }).toList();
  }
}
