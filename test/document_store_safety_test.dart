import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledgerly/models/business_document.dart';
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
        DocumentLine(id: 'line-1', description: 'Service', quantity: 1, unitPrice: 100),
      ],
      taxPercent: 0,
      discount: 0,
      notes: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('corrupt persisted JSON is reported instead of appearing as an empty workspace', () async {
    SharedPreferences.setMockInitialValues({'ledgerly.documents.v1': '{not-json'});
    final store = DocumentStore();

    await expectLater(store.load(), throwsA(isA<FormatException>()));
  });

  test('invalid backup is rejected before existing invoices are overwritten', () async {
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
}
