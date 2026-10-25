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

  // Documents
  Future<List<BusinessDocument>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_storageKey);
    if (source == null || source.trim().isEmpty) return [];
    try {
      return BusinessDocument.decodeList(source);
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<BusinessDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(documents.map((document) => document.toJson()).toList()),
    );
  }

  // Customers
  Future<List<Customer>> loadCustomers() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_customersKey);
    if (source == null || source.trim().isEmpty) return [];
    try {
      return Customer.decodeList(source);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCustomers(List<Customer> customers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customersKey, Customer.encodeList(customers));
  }

  // Items / Inventory
  Future<List<Item>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_itemsKey);
    if (source == null || source.trim().isEmpty) return [];
    try {
      return Item.decodeList(source);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<Item> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_itemsKey, Item.encodeList(items));
  }

  // Payments
  Future<List<Payment>> loadPayments() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_paymentsKey);
    if (source == null || source.trim().isEmpty) return [];
    try {
      return Payment.decodeList(source);
    } catch (_) {
      return [];
    }
  }

  Future<void> savePayments(List<Payment> payments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paymentsKey, Payment.encodeList(payments));
  }

  // Business Profile
  Future<BusinessProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_profileKey);
    if (source == null || source.trim().isEmpty) return BusinessProfile();
    try {
      return BusinessProfile.decode(source);
    } catch (_) {
      return BusinessProfile();
    }
  }

  Future<void> saveProfile(BusinessProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, profile.encode());
  }

  // Backup & Export / Import
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
    final Map<String, dynamic> data = jsonDecode(jsonSource) as Map<String, dynamic>;
    if (data.containsKey('documents')) {
      final List<dynamic> docList = data['documents'] as List<dynamic>;
      final docs = docList.map((e) => BusinessDocument.fromJson(e as Map<String, dynamic>)).toList();
      await save(docs);
    }
    if (data.containsKey('customers')) {
      final List<dynamic> list = data['customers'] as List<dynamic>;
      final customers = list.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
      await saveCustomers(customers);
    }
    if (data.containsKey('items')) {
      final List<dynamic> list = data['items'] as List<dynamic>;
      final items = list.map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
      await saveItems(items);
    }
    if (data.containsKey('payments')) {
      final List<dynamic> list = data['payments'] as List<dynamic>;
      final payments = list.map((e) => Payment.fromJson(e as Map<String, dynamic>)).toList();
      await savePayments(payments);
    }
    if (data.containsKey('profile')) {
      final profile = BusinessProfile.fromJson(data['profile'] as Map<String, dynamic>);
      await saveProfile(profile);
    }
  }
}
