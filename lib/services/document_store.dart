import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_storage_service.dart';
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
    final source = await _loadSource(_storageKey, 'documents');
    if (source == null || source.trim().isEmpty) return [];
    return BusinessDocument.decodeList(source);
  }

  Future<void> save(List<BusinessDocument> documents) async {
    final payload = documents.map((d) => d.toJson()).toList();
    await _saveSource(_storageKey, 'documents', jsonEncode(payload), payload);
  }

  Future<List<Customer>> loadCustomers() async {
    final source = await _loadSource(_customersKey, 'customers');
    if (source == null || source.trim().isEmpty) return [];
    return Customer.decodeList(source);
  }

  Future<void> saveCustomers(List<Customer> customers) async {
    final payload = customers.map((customer) => customer.toJson()).toList();
    await _saveSource(_customersKey, 'customers', jsonEncode(payload), payload);
  }

  Future<List<Item>> loadItems() async {
    final source = await _loadSource(_itemsKey, 'items');
    if (source == null || source.trim().isEmpty) return [];
    return Item.decodeList(source);
  }

  Future<void> saveItems(List<Item> items) async {
    final payload = items.map((item) => item.toJson()).toList();
    await _saveSource(_itemsKey, 'items', jsonEncode(payload), payload);
  }

  Future<List<Payment>> loadPayments() async {
    final source = await _loadSource(_paymentsKey, 'payments');
    if (source == null || source.trim().isEmpty) return [];
    return Payment.decodeList(source);
  }

  Future<void> savePayments(List<Payment> payments) async {
    final payload = payments.map((payment) => payment.toJson()).toList();
    await _saveSource(_paymentsKey, 'payments', jsonEncode(payload), payload);
  }

  Future<BusinessProfile> loadProfile() async {
    final source = await _loadSource(_profileKey, 'profile');
    if (source == null || source.trim().isEmpty) return BusinessProfile();
    return BusinessProfile.decode(source);
  }

  Future<void> saveProfile(BusinessProfile profile) async {
    await _saveSource(_profileKey, 'profile', profile.encode(), profile.toJson());
  }

  Future<String?> _loadSource(String key, String section) async {
    final prefs = await SharedPreferences.getInstance();
    final localSource = prefs.getString(key);
    if (!await CloudStorageService.instance.isCloudMode) return localSource;

    // In cloud mode, never silently substitute a stale local cache after a
    // network error or missing cloud section. The caller shows a load error;
    // the user can explicitly switch to local mode instead.
    final payload = await CloudStorageService.instance.loadSection(section);
    if (payload == null) {
      throw StateError(
        'The cloud workspace is missing the "$section" section. Choose a migration option before continuing.',
      );
    }
    final source = jsonEncode(payload);
    try {
      // Cache only the last successfully fetched cloud copy.
      await prefs.setString(key, source);
    } catch (_) {
      // The cloud response is still authoritative if local caching fails.
    }
    return source;
  }

  Future<void> _saveSource(
    String key,
    String section,
    String source,
    Object payload,
  ) async {
    if (await CloudStorageService.instance.isCloudMode) {
      // Write to the server first so failed cloud writes are never reported as
      // synced. Local mode remains available separately from cloud mode.
      await CloudStorageService.instance.saveSection(section, payload);
      try {
        await _write(key, source);
      } catch (_) {
        // The server is authoritative in cloud mode; the cache is best effort.
      }
      return;
    }
    await _write(key, source);
  }

  Future<void> _write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, value)) {
      throw StateError('Could not persist Ledgerly data for key: $key');
    }
  }

  /// Exports the current device copy specifically, regardless of whether
  /// cloud mode is enabled. Used to show a safe migration choice.
  Future<String> exportLocalBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final docsSource = prefs.getString(_storageKey);
    final customersSource = prefs.getString(_customersKey);
    final itemsSource = prefs.getString(_itemsKey);
    final paymentsSource = prefs.getString(_paymentsKey);
    final profileSource = prefs.getString(_profileKey);
    final docs = docsSource == null || docsSource.trim().isEmpty
        ? <BusinessDocument>[]
        : BusinessDocument.decodeList(docsSource);
    final customers = customersSource == null || customersSource.trim().isEmpty
        ? <Customer>[]
        : Customer.decodeList(customersSource);
    final items = itemsSource == null || itemsSource.trim().isEmpty
        ? <Item>[]
        : Item.decodeList(itemsSource);
    final payments = paymentsSource == null || paymentsSource.trim().isEmpty
        ? <Payment>[]
        : Payment.decodeList(paymentsSource);
    final profile = profileSource == null || profileSource.trim().isEmpty
        ? BusinessProfile()
        : BusinessProfile.decode(profileSource);
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'documents': docs.map((d) => d.toJson()).toList(),
      'customers': customers.map((c) => c.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'profile': profile.toJson(),
    });
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
