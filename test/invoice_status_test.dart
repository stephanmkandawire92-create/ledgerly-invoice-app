import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly/models/business_document.dart';
import 'package:ledgerly/models/payment.dart';

BusinessDocument invoice({required DateTime dueDate, String status = 'Sent'}) =>
    BusinessDocument(
      id: 'invoice-1',
      number: 'INV-1',
      kind: DocumentKind.invoice,
      clientName: 'Test client',
      clientEmail: '',
      issueDate: DateTime(2026, 10, 1),
      dueDate: dueDate,
      status: status,
      currencyCode: 'USD',
      lines: [
        DocumentLine(
            id: 'line-1', description: 'Service', quantity: 1, unitPrice: 100),
      ],
      taxPercent: 0,
      discount: 0,
      notes: '',
    );

Payment payment(double amount) => Payment(
      id: 'payment-1',
      invoiceId: 'invoice-1',
      paymentDate: DateTime(2026, 10, 28),
      amount: amount,
    );

void main() {
  group('effective invoice status', () {
    final now = DateTime(2026, 10, 28, 15);

    test('due today is not overdue after midnight', () {
      expect(
        effectiveInvoiceStatus(
            invoice(dueDate: DateTime(2026, 10, 28)), const [],
            now: now),
        'Sent',
      );
    });

    test('unpaid invoice due yesterday is overdue', () {
      expect(
        effectiveInvoiceStatus(
            invoice(dueDate: DateTime(2026, 10, 27)), const [],
            now: now),
        'Overdue',
      );
    });

    test('partial payment does not clear an overdue balance', () {
      expect(
        effectiveInvoiceStatus(
          invoice(dueDate: DateTime(2026, 10, 27), status: 'Pending'),
          [payment(20)],
          now: now,
        ),
        'Overdue',
      );
    });

    test(
        'partial future-due balance is pending and a fully paid invoice is paid',
        () {
      expect(
        effectiveInvoiceStatus(
            invoice(dueDate: DateTime(2026, 10, 30)), [payment(20)],
            now: now),
        'Pending',
      );
      expect(
        effectiveInvoiceStatus(
            invoice(dueDate: DateTime(2026, 10, 30)), [payment(100)],
            now: now),
        'Paid',
      );
    });

    test('deleting the final payment clears a derived Paid status', () {
      expect(
        effectiveInvoiceStatus(
          invoice(dueDate: DateTime(2026, 10, 30), status: 'Paid'),
          const [],
          now: now,
          clearPaidWhenNoPayments: true,
        ),
        'Sent',
      );
      expect(
        effectiveInvoiceStatus(
          invoice(dueDate: DateTime(2026, 10, 27), status: 'Paid'),
          const [],
          now: now,
          clearPaidWhenNoPayments: true,
        ),
        'Overdue',
      );
    });
  });

  test('money rounding is shared to cents', () {
    expect(roundMoney(100.005), 100.01);
    expect(roundMoney(double.infinity), 0);
  });
}
