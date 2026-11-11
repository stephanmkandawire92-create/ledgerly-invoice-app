import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/business_document.dart';
import '../models/currency_helper.dart';
import '../models/business_profile.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/payment.dart';

class DocumentStore {
  static const _snapshotKey = 'ledgerly.workspace.snapshot.v1';
  static const _storageKey = 'ledgerly.documents.v1';
  static const _customersKey = 'ledgerly.customers.v1';
  static const _itemsKey = 'ledgerly.items.v1';
  static const _paymentsKey = 'ledgerly.payments.v1';
  static const _profileKey = 'ledgerly.profile.v1';

  // A decoding error must reach the caller. Returning an empty collection here
  // makes damaged data look like a new workspace and risks overwriting it.
  Future<List<BusinessDocument>> load() async {
    final source = await _readValue(_storageKey, 'documents');
    if (source == null || source.trim().isEmpty) return [];
    return BusinessDocument.decodeList(source);
  }

  Future<void> save(List<BusinessDocument> documents) async {
    final payments = await loadPayments();
    await saveDocumentsAndPayments(documents, payments);
  }

  Future<List<Customer>> loadCustomers() async {
    final source = await _readValue(_customersKey, 'customers');
    if (source == null || source.trim().isEmpty) return [];
    return Customer.decodeList(source);
  }

  Future<void> saveCustomers(List<Customer> customers) async {
    _ensureUniqueIds(customers.map((customer) => customer.id), 'customers');
    await _saveValue(
        _customersKey, 'customers', Customer.encodeList(customers));
  }

  Future<List<Item>> loadItems() async {
    final source = await _readValue(_itemsKey, 'items');
    if (source == null || source.trim().isEmpty) return [];
    return Item.decodeList(source);
  }

  Future<void> saveItems(List<Item> items) async {
    _ensureUniqueIds(items.map((item) => item.id), 'items');
    if (items.any((item) =>
        !item.unitPrice.isFinite ||
        item.unitPrice < 0 ||
        item.unitPrice > 1e12 ||
        !item.taxRate.isFinite ||
        item.taxRate < 0 ||
        item.taxRate > 100)) {
      throw const FormatException('Items must have valid prices and tax rates.');
    }
    await _saveValue(_itemsKey, 'items', Item.encodeList(items));
  }

  Future<List<Payment>> loadPayments() async {
    final source = await _readValue(_paymentsKey, 'payments');
    if (source == null || source.trim().isEmpty) return [];
    return Payment.decodeList(source);
  }

  Future<void> savePayments(List<Payment> payments) async {
    // Payments and invoice totals must be committed in one workspace snapshot.
    await saveDocumentsAndPayments(await load(), payments);
  }

  Future<void> saveDocumentsAndPayments(
    List<BusinessDocument> documents,
    List<Payment> payments,
  ) async {
    _validateDocuments(documents);
    _ensureUniqueIds(payments.map((payment) => payment.id), 'payments');
    final invoiceTotals = {
      for (final invoice in documents
          .where((document) => document.kind == DocumentKind.invoice))
        invoice.id: invoice.total,
    };
    final paidByInvoice = <String, double>{};
    for (final payment in payments) {
      if (!payment.amount.isFinite ||
          payment.amount <= 0 ||
          roundMoney(payment.amount) != payment.amount ||
          !invoiceTotals.containsKey(payment.invoiceId)) {
        throw const FormatException(
            'Payment must be positive, cent-rounded, and linked to an invoice.');
      }
      paidByInvoice.update(
          payment.invoiceId, (amount) => roundMoney(amount + payment.amount),
          ifAbsent: () => roundMoney(payment.amount));
    }
    if (paidByInvoice.entries.any(
        (entry) => entry.value > (invoiceTotals[entry.key] ?? 0) + 0.004)) {
      throw const FormatException('Payments cannot exceed an invoice total.');
    }

    final prefs = await SharedPreferences.getInstance();
    final snapshotSource = prefs.getString(_snapshotKey);
    late final Map<String, dynamic> snapshot;
    if (snapshotSource == null) {
      Object readLegacy(String key, Object fallback) {
        final source = prefs.getString(key);
        return source == null || source.trim().isEmpty
            ? fallback
            : jsonDecode(source);
      }

      snapshot = {
        'version': 1,
        'documents': readLegacy(_storageKey, <dynamic>[]),
        'customers': readLegacy(_customersKey, <dynamic>[]),
        'items': readLegacy(_itemsKey, <dynamic>[]),
        'payments': readLegacy(_paymentsKey, <dynamic>[]),
        'profile': readLegacy(_profileKey, BusinessProfile().toJson()),
      };
    } else {
      final decoded = jsonDecode(snapshotSource);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Saved workspace snapshot is invalid.');
      }
      snapshot = Map<String, dynamic>.from(decoded);
      _validateSnapshot(snapshot);
    }
    _validateSnapshot(snapshot);
    snapshot['documents'] =
        documents.map((document) => document.toJson()).toList();
    snapshot['payments'] = payments.map((payment) => payment.toJson()).toList();
    if (!await prefs.setString(_snapshotKey, jsonEncode(snapshot))) {
      throw StateError(
          'Could not persist invoice and payment changes atomically.');
    }
  }

  Future<BusinessProfile> loadProfile() async {
    final source = await _readValue(_profileKey, 'profile');
    if (source == null || source.trim().isEmpty) return BusinessProfile();
    return BusinessProfile.decode(source);
  }

  Future<void> saveProfile(BusinessProfile profile) async {
    if (!CurrencyHelper.currencies.any(
        (currency) => currency.code == profile.currencyCode.toUpperCase())) {
      throw FormatException(
          'Unsupported business profile currency: ' + profile.currencyCode + '.');
    }
    await _saveValue(_profileKey, 'profile', profile.encode());
  }

  Future<String?> _readValue(String legacyKey, String section) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshotSource = prefs.getString(_snapshotKey);
    if (snapshotSource == null) return prefs.getString(legacyKey);
    final decoded = jsonDecode(snapshotSource);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Saved workspace snapshot is invalid.');
    }
    _validateSnapshot(decoded);
    if (!decoded.containsKey(section)) {
      throw FormatException('Saved workspace snapshot is missing "$section".');
    }
    return jsonEncode(decoded[section]);
  }

  Future<void> _saveValue(
      String legacyKey, String section, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshotSource = prefs.getString(_snapshotKey);
    if (snapshotSource == null) {
      await _write(legacyKey, value);
      return;
    }
    final decoded = jsonDecode(snapshotSource);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Saved workspace snapshot is invalid.');
    }
    _validateSnapshot(decoded);
    decoded[section] = jsonDecode(value);
    if (!await prefs.setString(_snapshotKey, jsonEncode(decoded))) {
      throw StateError(
          'Could not persist Ledgerly workspace section: $section');
    }
  }

  Future<void> _write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, value)) {
      throw StateError('Could not persist Ledgerly data for key: $key');
    }
  }

  Future<String> exportBackup() async {
    final docs = await load();
    final customers = await loadCustomers();
    final items = await loadItems();
    final payments = await loadPayments();
    final profile = await loadProfile();

    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'documents': docs.map((d) => d.toJson()).toList(),
      'customers': customers.map((c) => c.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'profile': profile.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> importBackup(String jsonSource) async {
    // Parse and validate every section before writing any live data.
    final decoded = jsonDecode(jsonSource);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup must be a JSON object.');
    }
    final data = decoded;
    if (data['version'] != 1) {
      throw const FormatException('Unsupported or missing backup version.');
    }
    for (final key in [
      'documents',
      'customers',
      'items',
      'payments',
      'profile'
    ]) {
      if (!data.containsKey(key)) {
        throw FormatException('Backup is missing required section: $key');
      }
    }
    _validateBackupShape(data);

    List<T> decodeList<T>(
      Object? value,
      T Function(Map<String, dynamic>) decode,
      String section,
    ) {
      if (value is! List) {
        throw FormatException('Backup section "$section" must be a list.');
      }
      return value.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw FormatException(
              'Backup section "$section" contains an invalid record.');
        }
        return decode(entry);
      }).toList();
    }

    final docs =
        decodeList(data['documents'], BusinessDocument.fromJson, 'documents');
    final customers =
        decodeList(data['customers'], Customer.fromJson, 'customers');
    final items = decodeList(data['items'], Item.fromJson, 'items');
    final payments = decodeList(data['payments'], Payment.fromJson, 'payments');
    if (data['profile'] is! Map<String, dynamic>) {
      throw const FormatException('Backup profile section is invalid.');
    }
    final profile =
        BusinessProfile.fromJson(data['profile'] as Map<String, dynamic>);
    if (!CurrencyHelper.currencies.any(
        (currency) => currency.code == profile.currencyCode.toUpperCase())) {
      throw const FormatException(
          'Backup contains an unsupported business profile currency.');
    }

    _ensureUniqueIds(docs.map((e) => e.id), 'documents');
    _ensureUniqueIds(customers.map((e) => e.id), 'customers');
    _ensureUniqueIds(items.map((e) => e.id), 'items');
    _ensureUniqueIds(payments.map((e) => e.id), 'payments');
    if (docs.any((d) =>
        !d.taxPercent.isFinite ||
        d.taxPercent < 0 ||
        d.taxPercent > 100 ||
        !d.discount.isFinite ||
        d.discount < 0 ||
        d.lines.any((line) =>
            !line.quantity.isFinite ||
            line.quantity <= 0 ||
            line.quantity > 1e9 ||
            !line.unitPrice.isFinite ||
            line.unitPrice < 0 ||
            line.unitPrice > 1e12))) {
      throw const FormatException(
          'Backup contains invalid invoice or quote amounts.');
    }
    if (items.any((item) =>
        !item.unitPrice.isFinite ||
        item.unitPrice < 0 ||
        item.unitPrice > 1e12 ||
        !item.taxRate.isFinite ||
        item.taxRate < 0 ||
        item.taxRate > 100)) {
      throw const FormatException(
          'Backup contains invalid catalogue prices or tax rates.');
    }
    if (payments.any((payment) =>
        !payment.amount.isFinite ||
        payment.amount <= 0 ||
        roundMoney(payment.amount) != payment.amount)) {
      throw const FormatException('Backup contains invalid payment amounts.');
    }
    final invoiceIds = docs
        .where((d) => d.kind == DocumentKind.invoice)
        .map((d) => d.id)
        .toSet();
    if (payments.any((p) => !invoiceIds.contains(p.invoiceId))) {
      throw const FormatException(
          'Backup contains a payment linked to a missing invoice.');
    }
    final invoiceTotals = {
      for (final invoice in docs.where((d) => d.kind == DocumentKind.invoice))
        invoice.id: invoice.total
    };
    final paidByInvoice = <String, double>{};
    for (final payment in payments) {
      paidByInvoice.update(
          payment.invoiceId, (amount) => roundMoney(amount + payment.amount),
          ifAbsent: () => roundMoney(payment.amount));
    }
    if (paidByInvoice.entries.any(
        (entry) => entry.value > (invoiceTotals[entry.key] ?? 0) + 0.004)) {
      throw const FormatException(
          'Backup contains payments greater than an invoice total.');
    }

    final snapshot = <String, dynamic>{
      'version': 1,
      'documents': docs.map((d) => d.toJson()).toList(),
      'customers': customers.map((c) => c.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'profile': profile.toJson(),
    };

    _validateSnapshot(snapshot);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_snapshotKey, jsonEncode(snapshot))) {
      throw StateError('Could not atomically restore Ledgerly workspace data.');
    }
  }

  void _validateSnapshot(Map<String, dynamic> snapshot) {
    if (snapshot['version'] != 1) {
      throw const FormatException(
          'Saved workspace snapshot has an unsupported version.');
    }
    const requiredSections = [
      'documents',
      'customers',
      'items',
      'payments',
      'profile',
    ];
    for (final section in requiredSections) {
      if (!snapshot.containsKey(section)) {
        throw FormatException(
            'Saved workspace snapshot is missing "$section".');
      }
    }
    if (snapshot['documents'] is! List ||
        snapshot['customers'] is! List ||
        snapshot['items'] is! List ||
        snapshot['payments'] is! List ||
        snapshot['profile'] is! Map<String, dynamic>) {
      throw const FormatException(
          'Saved workspace snapshot contains an invalid section.');
    }
  }

  void _validateDocuments(List<BusinessDocument> documents) {
    _ensureUniqueIds(documents.map((document) => document.id), 'documents');
    final numbers = <String>{};
    for (final document in documents) {
      final number = document.number.trim().toLowerCase();
      final numberKey = document.kind.name + ':' + number;
      if (number.isEmpty || !numbers.add(numberKey)) {
        throw const FormatException(
            'Documents must have unique, non-empty numbers within each type.');
      }
      if (!CurrencyHelper.currencies.any(
          (currency) => currency.code == document.currencyCode.toUpperCase())) {
        throw FormatException('Unsupported document currency: ' + document.currencyCode + '.');
      }
      if (!document.taxPercent.isFinite ||
          document.taxPercent < 0 ||
          document.taxPercent > 100 ||
          !document.discount.isFinite ||
          document.discount < 0) {
        throw const FormatException(
            'Documents must have valid non-negative discounts and tax rates.');
      }
      if (document.dueDate.isBefore(document.issueDate)) {
        throw const FormatException(
            'A document due date cannot be earlier than its issue date.');
      }
      _ensureUniqueIds(document.lines.map((line) => line.id), 'document line items');
      if (document.lines.any((line) =>
          !line.quantity.isFinite ||
          line.quantity <= 0 ||
          line.quantity > 1e9 ||
          !line.unitPrice.isFinite ||
          line.unitPrice < 0 ||
          line.unitPrice > 1e12)) {
        throw const FormatException(
            'Document line items must have valid quantities and prices.');
      }
      if (!document.total.isFinite) {
        throw const FormatException('Document total must be a finite amount.');
      }
    }
  }

  void _validateBackupShape(Map<String, dynamic> data) {
    final documents = data['documents'];
    final customers = data['customers'];
    final items = data['items'];
    final payments = data['payments'];
    if (documents is! List ||
        customers is! List ||
        items is! List ||
        payments is! List) {
      throw const FormatException('Backup contains an invalid section.');
    }

    void requireDate(Map<String, dynamic> record, String key, String section) {
      final raw = record[key];
      if (raw is! String || DateTime.tryParse(raw) == null) {
        throw FormatException('Backup contains an invalid $section.$key date.');
      }
    }

    final documentNumbers = <String>{};
    for (final entry in documents) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Backup contains an invalid document.');
      }
      if (entry['kind'] != 'invoice' && entry['kind'] != 'quote') {
        throw const FormatException(
            'Backup contains a document with an unknown kind.');
      }
      requireDate(entry, 'issueDate', 'document');
      requireDate(entry, 'dueDate', 'document');
      final currencyCode = entry['currencyCode'];
      if (currencyCode is! String ||
          !CurrencyHelper.currencies.any(
              (currency) => currency.code == currencyCode.toUpperCase())) {
        throw const FormatException(
            'Backup contains a document with an unsupported currency.');
      }
      final issueDate = DateTime.parse(entry['issueDate'] as String);
      final dueDate = DateTime.parse(entry['dueDate'] as String);
      if (dueDate.isBefore(issueDate)) {
        throw const FormatException(
            'Backup contains a due date earlier than its issue date.');
      }
      final number = entry['number'];
      if (number is! String || number.trim().isEmpty) {
        throw const FormatException(
            'Backup contains a document without a number.');
      }
      final key = '${entry['kind']}:${number.trim().toLowerCase()}';
      if (!documentNumbers.add(key)) {
        throw const FormatException(
            'Backup contains duplicate document numbers.');
      }
      final lines = entry['lines'];
      if (lines is! List) {
        throw const FormatException(
            'Backup contains an invalid document line list.');
      }
      final lineIds = <String>{};
      for (final line in lines) {
        if (line is! Map<String, dynamic> ||
            line['id'] is! String ||
            (line['id'] as String).trim().isEmpty ||
            !lineIds.add((line['id'] as String).trim()) ||
            line['quantity'] is! num ||
            line['unitPrice'] is! num) {
          throw const FormatException(
              'Backup contains a line without a unique ID, quantity or unit price.');
        }
        final quantity = (line['quantity'] as num).toDouble();
        final unitPrice = (line['unitPrice'] as num).toDouble();
        if (!quantity.isFinite || quantity <= 0 || quantity > 1e9 ||
            !unitPrice.isFinite || unitPrice < 0 || unitPrice > 1e12) {
          throw const FormatException(
              'Backup contains an invalid line quantity or unit price.');
        }
      }
    }
    for (final entry in customers) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Backup contains an invalid customer.');
      }
      requireDate(entry, 'createdAt', 'customer');
    }
    for (final entry in items) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Backup contains an invalid item.');
      }
      requireDate(entry, 'createdAt', 'item');
    }
    for (final entry in payments) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Backup contains an invalid payment.');
      }
      requireDate(entry, 'paymentDate', 'payment');
      requireDate(entry, 'createdAt', 'payment');
    }
  }

  void _ensureUniqueIds(Iterable<String> ids, String section) {
    final values = ids.toList();
    if (values.any((id) => id.trim().isEmpty) ||
        values.toSet().length != values.length) {
      throw FormatException(
          'Backup contains missing or duplicate IDs in "$section".');
    }
  }
}
