import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/business_document.dart';
import '../models/business_profile.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/payment.dart';

class DocumentStore {
  static const _storageKey = 'ledgerly.documents.v1';
  static const _customersKey = 'ledgerly.customers.v1';
  static const _itemsKey = 'ledgerly.items.v1';
  static const _paymentsKey = 'ledgerly.payments.v1';
  static const _profileKey = 'ledgerly.profile.v1';

  static const _allKeys = [
    _storageKey,
    _customersKey,
    _itemsKey,
    _paymentsKey,
    _profileKey,
  ];

  // A decoding error must reach the caller. Returning an empty collection here
  // makes damaged data look like a new workspace and risks overwriting it.
  Future<List<BusinessDocument>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_storageKey);
    if (source == null || source.trim().isEmpty) return [];
    return BusinessDocument.decodeList(source);
  }

  Future<void> save(List<BusinessDocument> documents) async {
    await _write(_storageKey, jsonEncode(documents.map((d) => d.toJson()).toList()));
  }

  Future<List<Customer>> loadCustomers() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_customersKey);
    if (source == null || source.trim().isEmpty) return [];
    return Customer.decodeList(source);
  }

  Future<void> saveCustomers(List<Customer> customers) async {
    await _write(_customersKey, Customer.encodeList(customers));
  }

  Future<List<Item>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_itemsKey);
    if (source == null || source.trim().isEmpty) return [];
    return Item.decodeList(source);
  }

  Future<void> saveItems(List<Item> items) async {
    await _write(_itemsKey, Item.encodeList(items));
  }

  Future<List<Payment>> loadPayments() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_paymentsKey);
    if (source == null || source.trim().isEmpty) return [];
    return Payment.decodeList(source);
  }

  Future<void> savePayments(List<Payment> payments) async {
    await _write(_paymentsKey, Payment.encodeList(payments));
  }

  Future<BusinessProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_profileKey);
    if (source == null || source.trim().isEmpty) return BusinessProfile();
    return BusinessProfile.decode(source);
  }

  Future<void> saveProfile(BusinessProfile profile) async {
    await _write(_profileKey, profile.encode());
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
    for (final key in ['documents', 'customers', 'items', 'payments', 'profile']) {
      if (!data.containsKey(key)) {
        throw FormatException('Backup is missing required section: $key');
      }
    }

    List<T> decodeList<T>(
      Object? value,
      T Function(Map<String, dynamic>) decode,
      String section,
    ) {
      if (value is! List) throw FormatException('Backup section "$section" must be a list.');
      return value.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw FormatException('Backup section "$section" contains an invalid record.');
        }
        return decode(entry);
      }).toList();
    }

    final docs = decodeList(data['documents'], BusinessDocument.fromJson, 'documents');
    final customers = decodeList(data['customers'], Customer.fromJson, 'customers');
    final items = decodeList(data['items'], Item.fromJson, 'items');
    final payments = decodeList(data['payments'], Payment.fromJson, 'payments');
    if (data['profile'] is! Map<String, dynamic>) {
      throw const FormatException('Backup profile section is invalid.');
    }
    final profile = BusinessProfile.fromJson(data['profile'] as Map<String, dynamic>);

    _ensureUniqueIds(docs.map((e) => e.id), 'documents');
    _ensureUniqueIds(customers.map((e) => e.id), 'customers');
    _ensureUniqueIds(items.map((e) => e.id), 'items');
    _ensureUniqueIds(payments.map((e) => e.id), 'payments');
    if (docs.any((d) =>
        !d.taxPercent.isFinite || d.taxPercent < 0 || d.taxPercent > 100 ||
        !d.discount.isFinite || d.discount < 0 ||
        d.lines.any((line) =>
            !line.quantity.isFinite || line.quantity <= 0 || line.quantity > 1e9 ||
            !line.unitPrice.isFinite || line.unitPrice < 0 || line.unitPrice > 1e12))) {
      throw const FormatException('Backup contains invalid invoice or quote amounts.');
    }
    if (items.any((item) =>
        !item.unitPrice.isFinite || item.unitPrice < 0 || item.unitPrice > 1e12 ||
        !item.taxRate.isFinite || item.taxRate < 0 || item.taxRate > 100)) {
      throw const FormatException('Backup contains invalid catalogue prices or tax rates.');
    }
    if (payments.any((payment) => !payment.amount.isFinite || payment.amount <= 0)) {
      throw const FormatException('Backup contains invalid payment amounts.');
    }
    final invoiceIds = docs.where((d) => d.kind == DocumentKind.invoice).map((d) => d.id).toSet();
    if (payments.any((p) => !invoiceIds.contains(p.invoiceId))) {
      throw const FormatException('Backup contains a payment linked to a missing invoice.');
    }

    final values = <String, String>{
      _storageKey: BusinessDocument.encodeList(docs),
      _customersKey: Customer.encodeList(customers),
      _itemsKey: Item.encodeList(items),
      _paymentsKey: Payment.encodeList(payments),
      _profileKey: profile.encode(),
    };

    final prefs = await SharedPreferences.getInstance();
    final oldValues = <String, String?>{
      for (final key in _allKeys) key: prefs.getString(key),
    };
    try {
      for (final entry in values.entries) {
        if (!await prefs.setString(entry.key, entry.value)) {
          throw StateError('Could not restore backup section: ${entry.key}');
        }
      }
    } catch (_) {
      // Best-effort rollback to the previous stored values if any write fails.
      for (final key in _allKeys) {
        final previous = oldValues[key];
        if (previous == null) {
          await prefs.remove(key);
        } else {
          await prefs.setString(key, previous);
        }
      }
      rethrow;
    }
  }

  void _ensureUniqueIds(Iterable<String> ids, String section) {
    final values = ids.toList();
    if (values.any((id) => id.trim().isEmpty) || values.toSet().length != values.length) {
      throw FormatException('Backup contains missing or duplicate IDs in "$section".');
    }
  }
}
