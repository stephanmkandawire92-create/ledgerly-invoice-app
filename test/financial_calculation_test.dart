import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly/models/business_document.dart';

BusinessDocument makeDocument({
  required List<DocumentLine> lines,
  double taxPercent = 15,
  double discount = 0,
}) =>
    BusinessDocument(
      id: 'invoice-1',
      number: 'INV-1',
      kind: DocumentKind.invoice,
      clientName: 'Test Client',
      clientEmail: '',
      issueDate: DateTime(2026, 1, 1),
      dueDate: DateTime(2026, 1, 31),
      status: 'Sent',
      currencyCode: 'ZAR',
      lines: lines,
      taxPercent: taxPercent,
      discount: discount,
      notes: '',
    );

void main() {
  group('Invoice financial calculations', () {
    test('line amount and subtotal use the same capped, rounded value', () {
      final line = DocumentLine(
        id: 'line-1',
        description: 'Fractional service',
        quantity: 1.5,
        unitPrice: 19.99,
      );
      final document = makeDocument(lines: [line], taxPercent: 0);

      expect(line.amount, 29.99);
      expect(document.subtotal, line.amount);
      expect(document.total, line.amount);
    });

    test('discount cannot make taxable amount or total negative', () {
      final document = makeDocument(
        lines: [
          DocumentLine(id: 'line-1', description: 'Service', quantity: 1, unitPrice: 100),
        ],
        taxPercent: 15,
        discount: 500,
      );

      expect(document.safeDiscount, 100);
      expect(document.taxableAmount, 0);
      expect(document.taxAmount, 0);
      expect(document.total, 0);
    });

    test('invalid tax and discount values are handled safely', () {
      final document = makeDocument(
        lines: [
          DocumentLine(id: 'line-1', description: 'Service', quantity: 1, unitPrice: 100),
        ],
        taxPercent: double.nan,
        discount: double.infinity,
      );

      expect(document.safeTaxPercent, 0);
      expect(document.safeDiscount, 0);
      expect(document.total, 100);
      expect(document.total.isFinite, isTrue);
    });

    test('negative and non-finite line values cannot create negative totals', () {
      final document = makeDocument(lines: [
        DocumentLine(id: 'line-1', description: 'Invalid', quantity: -10, unitPrice: 500),
        DocumentLine(id: 'line-2', description: 'Non-finite', quantity: double.infinity, unitPrice: 10),
      ]);

      expect(document.subtotal, 0);
      expect(document.total, 0);
      expect(document.total.isFinite, isTrue);
    });

    test('tax calculation rounds to cents', () {
      final document = makeDocument(
        lines: [
          DocumentLine(id: 'line-1', description: 'Service', quantity: 3, unitPrice: 0.10),
        ],
        taxPercent: 15,
      );

      expect(document.subtotal, 0.30);
      expect(document.taxAmount, 0.05);
      expect(document.total, 0.35);
    });
  });
}
