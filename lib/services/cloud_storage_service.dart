import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_profile.dart';

/// Auth and per-user cloud workspace persistence for optional Ledgerly sync.
///
/// Local mode remains the default. This service never enables cloud mode until
/// the user has signed in and explicitly completes a migration choice.
class CloudStorageService {
  CloudStorageService._();

  static final CloudStorageService instance = CloudStorageService._();

  static const String tableName = 'ledgerly_cloud_data';
  static const String _modeKey = 'ledgerly.cloud_storage_enabled.v1';
  final Map<String, String?> _revisions = <String, String?>{};

  static const List<String> sectionNames = <String>[
    'documents',
    'customers',
    'items',
    'payments',
    'profile',
  ];

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _client != null;

  User? get currentUser => _client?.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  Future<bool> get isCloudMode async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_modeKey) == true && isSignedIn;
  }

  Future<void> setCloudMode(bool enabled) async {
    if (enabled && !isSignedIn) {
      throw StateError('Sign in before enabling cloud storage.');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_modeKey, enabled)) {
      throw StateError('Could not save the storage preference.');
    }
  }

  Future<AuthResponse> signUp(String email, String password) {
    final client = _client;
    if (client == null) throw StateError('Cloud storage is not configured in this build.');
    return client.auth.signUp(email: email.trim(), password: password);
  }

  Future<AuthResponse> signIn(String email, String password) {
    final client = _client;
    if (client == null) throw StateError('Cloud storage is not configured in this build.');
    return client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    final client = _client;
    if (client == null) throw StateError('Cloud storage is not configured in this build.');
    await client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await setCloudMode(false);
    final client = _client;
    if (client == null) return;
    await client.auth.signOut();
  }

  Future<bool> hasCloudData() async {
    final client = _requireSignedInClient();
    final rows = await client.from(tableName).select('data_type').limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<Object?> loadSection(String section) async {
    _validateSection(section);
    final client = _requireSignedInClient();
    final row = await client
        .from(tableName)
        .select('payload,updated_at')
        .eq('data_type', section)
        .maybeSingle();
    _revisions[section] = row == null ? null : row['updated_at']?.toString();
    return row == null ? null : row['payload'];
  }

  Future<void> saveSection(String section, Object payload) async {
    _validateSection(section);
    _validatePayload(section, payload);
    final client = _requireSignedInClient();
    if (!_revisions.containsKey(section)) {
      throw StateError('Load the cloud section before saving it.');
    }
    final updatedAt = await client.rpc(
      'ledgerly_save_cloud_section',
      params: <String, dynamic>{
        'p_data_type': section,
        'p_payload': payload,
        'p_expected_updated_at': _revisions[section],
      },
    );
    if (updatedAt == null) {
      throw StateError('Cloud save did not return a revision. Reload before trying again.');
    }
    _revisions[section] = updatedAt.toString();
  }

  /// Uploads a validated local backup. Replacing a non-empty cloud workspace
  /// requires an explicit confirmation from the calling UI.
  Future<void> uploadBackup(
    String backupJson, {
    required bool allowOverwrite,
  }) async {
    final sections = decodeBackup(backupJson);
    final hasExistingCloudData = await hasCloudData();
    if (hasExistingCloudData && !allowOverwrite) {
      throw StateError('Cloud workspace already contains records.');
    }

    final client = _requireSignedInClient();
    // A single database function replaces all five sections in one transaction.
    // This prevents a network failure from leaving a half-migrated workspace.
    final revisions = await client.rpc(
      'ledgerly_replace_cloud_workspace',
      params: <String, dynamic>{
        'p_documents': sections['documents'],
        'p_customers': sections['customers'],
        'p_items': sections['items'],
        'p_payments': sections['payments'],
        'p_profile': sections['profile'],
        'p_allow_overwrite': allowOverwrite,
      },
    );
    if (revisions is! Map) {
      throw StateError('Cloud migration completed without returning revision data.');
    }
    _revisions.clear();
    for (final section in sectionNames) {
      final revision = revisions[section];
      if (revision == null) {
        throw StateError('Cloud migration did not return a revision for "$section".');
      }
      _revisions[section] = revision.toString();
    }
  }

  Future<String> exportCloudBackup() async {
    final client = _requireSignedInClient();
    final rows = await client.from(tableName).select('data_type,payload');
    final sections = <String, dynamic>{};
    for (final row in rows as List) {
      final type = row['data_type'];
      if (type is String && sectionNames.contains(type)) {
        sections[type] = row['payload'];
      }
    }

    return encodeBackup(<String, dynamic>{
      'documents': sections['documents'] ?? <dynamic>[],
      'customers': sections['customers'] ?? <dynamic>[],
      'items': sections['items'] ?? <dynamic>[],
      'payments': sections['payments'] ?? <dynamic>[],
      'profile': sections['profile'] ?? BusinessProfile().toJson(),
    });
  }

  static Map<String, dynamic> decodeBackup(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Unsupported or invalid Ledgerly backup.');
    }

    for (final section in sectionNames) {
      final value = decoded[section];
      if (section == 'profile') {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Backup profile section is invalid.');
        }
      } else if (value is! List) {
        throw FormatException('Backup section "$section" must be a list.');
      }
    }
    return <String, dynamic>{
      for (final section in sectionNames) section: decoded[section],
    };
  }

  static String encodeBackup(Map<String, dynamic> sections) {
    for (final section in sectionNames) {
      final value = sections[section];
      if (section == 'profile') {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Cloud profile section is invalid.');
        }
      } else if (value is! List) {
        throw FormatException('Cloud section "$section" must be a list.');
      }
    }
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      for (final section in sectionNames) section: sections[section],
    });
  }

  static bool backupHasData(String backupJson) {
    final sections = decodeBackup(backupJson);
    for (final section in const ['documents', 'customers', 'items', 'payments']) {
      if ((sections[section] as List).isNotEmpty) return true;
    }
    final profile = sections['profile'] as Map<String, dynamic>;
    return jsonEncode(profile) != jsonEncode(BusinessProfile().toJson());
  }

  SupabaseClient _requireSignedInClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Cloud storage is not configured in this build.');
    }
    if (client.auth.currentUser == null) {
      throw StateError('Sign in to use cloud storage.');
    }
    return client;
  }

  static void _validateSection(String section) {
    if (!sectionNames.contains(section)) {
      throw ArgumentError.value(section, 'section', 'Unknown Ledgerly workspace section.');
    }
  }

  static void _validatePayload(String section, Object payload) {
    if (section == 'profile') {
      if (payload is! Map) throw const FormatException('Profile payload must be an object.');
    } else if (payload is! List) {
      throw FormatException('Payload for "$section" must be a list.');
    }
  }
}
