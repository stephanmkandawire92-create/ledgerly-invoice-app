import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledgerly/models/business_document.dart';
import 'package:ledgerly/models/business_profile.dart';
import 'package:ledgerly/models/payment.dart';
import 'package:ledgerly/services/document_store.dart';

BusinessDocument makeInvoice(String id) => BusinessDocument(
      id: id,
      number: 'INV-1',
      kind: DocumentKind.invoice,
      clientName: 'Saved Client',
      clientEmail: '',
      issueDate: DateTime(2026, 1, 1),
      dueDate: DateTime(2026, 1, 31),
      status: 'Sent',
      currencyCode: 'ZAR',
      lines: [
        DocumentLine(
            id: 'line-1', description: 'Service', quantity: 1, unitPrice: 100),
      ],
      taxPercent: 0,
      discount: 0,
      notes: '',
    );

Map<String, dynamic> makeBackup({
  List<BusinessDocument>? documents,
  List<Payment> payments = const [],
  BusinessProfile? profile,
}) =>
    {
      'version': 1,
      'documents': (documents ?? [makeInvoice('backup-invoice')])
          .map((d) => d.toJson())
          .toList(),
      'customers': [],
      'items': [],
      'payments': payments.map((p) => p.toJson()).toList(),
      'profile': (profile ?? BusinessProfile()).toJson(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'corrupt persisted JSON is reported instead of appearing as an empty workspace',
      () async {
    SharedPreferences.setMockInitialValues(
        {'ledgerly.documents.v1': '{not-json'});
    final store = DocumentStore();

    await expectLater(store.load(), throwsA(isA<FormatException>()));
  });

  test('invalid backup is rejected before existing invoices are overwritten',
      () async {
    final store = DocumentStore();
    await store.save([makeInvoice('existing-invoice')]);

    final invalidBackup = jsonEncode({
      'version': 1,
      'documents': [],
      'customers': [],
      'items': [],
      // Required payments/profile sections intentionally missing.
    });

    await expectLater(
      store.importBackup(invalidBackup),
      throwsA(isA<FormatException>()),
    );
    final stored = await store.load();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'existing-invoice');
  });

  test('unsupported backup versions are rejected without writes', () async {
    final store = DocumentStore();
    await store.save([makeInvoice('existing-invoice')]);

    await expectLater(
      store.importBackup(jsonEncode({'version': 99})),
      throwsA(isA<FormatException>()),
    );

    expect((await store.load()).single.id, 'existing-invoice');
  });

  test('missing line price is rejected before changing the workspace',
      () async {
    final store = DocumentStore();
    await store.save([makeInvoice('existing-invoice')]);
    final backup = makeBackup();
    final document =
        (backup['documents'] as List).single as Map<String, dynamic>;
    ((document['lines'] as List).single as Map<String, dynamic>)
        .remove('unitPrice');

    await expectLater(
      store.importBackup(jsonEncode(backup)),
      throwsA(isA<FormatException>()),
    );
    expect((await store.load()).single.id, 'existing-invoice');
  });

  test('invalid serialized dates and unknown document kinds are rejected',
      () async {
    final store = DocumentStore();
    final badDateBackup = makeBackup();
    ((badDateBackup['documents'] as List).single
        as Map<String, dynamic>)['issueDate'] = 'not-a-date';
    await expectLater(
      store.importBackup(jsonEncode(badDateBackup)),
      throwsA(isA<FormatException>()),
    );

    final badKindBackup = makeBackup();
    ((badKindBackup['documents'] as List).single
        as Map<String, dynamic>)['kind'] = 'mystery';
    await expectLater(
      store.importBackup(jsonEncode(badKindBackup)),
      throwsA(isA<FormatException>()),
    );
  });

  test('aggregate payments above the invoice total are rejected', () async {
    final store = DocumentStore();
    final overpayment = Payment(
      id: 'payment-1',
      invoiceId: 'backup-invoice',
      paymentDate: DateTime(2026, 1, 2),
      amount: 100.01,
    );

    await expectLater(
      store.importBackup(jsonEncode(makeBackup(payments: [overpayment]))),
      throwsA(isA<FormatException>()),
    );
    expect(await store.load(), isEmpty);
  });

  test('invoice edits cannot reduce the total below recorded payments',
      () async {
    final store = DocumentStore();
    final invoice = makeInvoice('existing-invoice');
    final payment = Payment(
      id: 'payment-1',
      invoiceId: invoice.id,
      paymentDate: DateTime(2026, 1, 2),
      amount: 80,
    );
    await store.saveDocumentsAndPayments([invoice], [payment]);

    final reducedInvoice = makeInvoice(invoice.id)..lines.first.unitPrice = 50;
    await expectLater(
      store.save([reducedInvoice]),
      throwsA(isA<FormatException>()),
    );

    expect((await store.load()).single.total, 100);
    expect((await store.loadPayments()).single.amount, 80);
  });

  test('backup payments are normalized to cents before storage', () async {
    final store = DocumentStore();
    final backup = makeBackup();
    backup['payments'] = [
      {
        'id': 'payment-1',
        'invoiceId': 'backup-invoice',
        'paymentDate': '2026-01-02T00:00:00.000',
        'createdAt': '2026-01-02T00:00:00.000',
        'amount': 1.234,
      }
    ];

    await store.importBackup(jsonEncode(backup));

    expect((await store.loadPayments()).single.amount, 1.23);
  });

  test('sub-cent backup values that normalize to zero are rejected', () async {
    final store = DocumentStore();
    final backup = makeBackup();
    backup['payments'] = [
      {
        'id': 'payment-1',
        'invoiceId': 'backup-invoice',
        'paymentDate': '2026-01-02T00:00:00.000',
        'createdAt': '2026-01-02T00:00:00.000',
        'amount': 0.004,
      }
    ];

    await expectLater(
      store.importBackup(jsonEncode(backup)),
      throwsA(isA<FormatException>()),
    );
    expect(await store.load(), isEmpty);
  });

  test(
      'backup restore commits one snapshot and later writes preserve other sections',
      () async {
    final store = DocumentStore();
    final restoredProfile = BusinessProfile(businessName: 'Restored Business');
    await store.importBackup(jsonEncode(makeBackup(profile: restoredProfile)));
    final invoice = makeInvoice('edited-invoice');
    final recordedPayment = Payment(
      id: 'payment-1',
      invoiceId: invoice.id,
      paymentDate: DateTime(2026, 1, 2),
      amount: 100,
    );
    await store.saveDocumentsAndPayments([invoice], [recordedPayment]);

    expect((await store.load()).single.id, 'edited-invoice');
    expect((await store.loadPayments()).single.amount, 100);
    expect((await store.loadProfile()).businessName, 'Restored Business');
  });

  test('atomic save migrates legacy keys without dropping the stored profile',
      () async {
    final store = DocumentStore();
    await store.saveProfile(BusinessProfile(businessName: 'Legacy Business'));
    final invoice = makeInvoice('legacy-invoice');
    final payment = Payment(
      id: 'legacy-payment',
      invoiceId: invoice.id,
      paymentDate: DateTime(2026, 1, 2),
      amount: 50,
    );

    await store.saveDocumentsAndPayments([invoice], [payment]);

    expect((await store.load()).single.id, 'legacy-invoice');
    expect((await store.loadPayments()).single.amount, 50);
    expect((await store.loadProfile()).businessName, 'Legacy Business');
  });
  test('normal saves reject duplicate document IDs and numbers', () async {
    final store = DocumentStore();
    final first = makeInvoice('invoice-1');
    final duplicateId = makeInvoice('invoice-1')..number = 'INV-2';
    await expectLater(
      store.save([first, duplicateId]),
      throwsA(isA<FormatException>()),
    );

    final duplicateNumber = makeInvoice('invoice-2');
    await expectLater(
      store.save([first, duplicateNumber]),
      throwsA(isA<FormatException>()),
    );
    expect(await store.load(), isEmpty);
  });

  test('normal saves reject unsupported currency and invalid line values',
      () async {
    final store = DocumentStore();
    final unsupported = makeInvoice('invoice-1')..currencyCode = 'XYZ';
    await expectLater(
      store.save([unsupported]),
      throwsA(isA<FormatException>()),
    );

    final invalidLine = makeInvoice('invoice-2')
      ..lines.first.quantity = double.nan;
    await expectLater(
      store.save([invalidLine]),
      throwsA(isA<FormatException>()),
    );
    expect(await store.load(), isEmpty);
  });

  test('payment-only saves cannot create orphan or duplicate payments',
      () async {
    final store = DocumentStore();
    final invoice = makeInvoice('invoice-1');
    await store.save([invoice]);
    final orphan = Payment(
      id: 'payment-orphan',
      invoiceId: 'missing-invoice',
      paymentDate: DateTime(2026, 1, 2),
      amount: 10,
    );
    await expectLater(
      store.savePayments([orphan]),
      throwsA(isA<FormatException>()),
    );

    final first = Payment(
      id: 'payment-1',
      invoiceId: invoice.id,
      paymentDate: DateTime(2026, 1, 2),
      amount: 10,
    );
    final duplicate = Payment(
      id: 'payment-1',
      invoiceId: invoice.id,
      paymentDate: DateTime(2026, 1, 3),
      amount: 10,
    );
    await expectLater(
      store.savePayments([first, duplicate]),
      throwsA(isA<FormatException>()),
    );
    expect(await store.loadPayments(), isEmpty);
  });

  test('legacy workspace can still be loaded and saved after validation',
      () async {
    final invoice = makeInvoice('legacy-valid');
    SharedPreferences.setMockInitialValues({
      'ledgerly.documents.v1': jsonEncode([invoice.toJson()]),
    });
    final store = DocumentStore();
    expect((await store.load()).single.id, 'legacy-valid');
    await store.save([invoice]);
    expect((await store.load()).single.id, 'legacy-valid');
  });

  test('partial snapshots are rejected without replacing existing bytes',
      () async {
    const partial = '{"version":1,"documents":[],"payments":[]}';
    SharedPreferences.setMockInitialValues({
      'ledgerly.workspace.snapshot.v1': partial,
    });
    final store = DocumentStore();

    await expectLater(store.load(), throwsA(isA<FormatException>()));
    await expectLater(store.save([makeInvoice('new-invoice')]),
        throwsA(isA<FormatException>()));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ledgerly.workspace.snapshot.v1'), partial);
  });

  test('business profile saves reject unsupported currencies', () async {
    final store = DocumentStore();
    await expectLater(
      store.saveProfile(BusinessProfile(currencyCode: 'XYZ')),
      throwsA(isA<FormatException>()),
    );
    expect((await store.loadProfile()).currencyCode, 'ZAR');
  });

}
