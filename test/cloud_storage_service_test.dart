import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly/models/business_profile.dart';
import 'package:ledgerly/services/cloud_storage_service.dart';

void main() {
  group('CloudStorageService backup validation', () {
    test('decodes all expected workspace sections', () {
      final backup = jsonEncode(<String, dynamic>{
        'version': 1,
        'exportedAt': '2026-10-27T00:00:00.000Z',
        'documents': <dynamic>[],
        'customers': <dynamic>[],
        'items': <dynamic>[],
        'payments': <dynamic>[],
        'profile': BusinessProfile().toJson(),
      });

      final sections = CloudStorageService.decodeBackup(backup);

      expect(sections.keys.toSet(), containsAll(CloudStorageService.sectionNames));
      expect(sections['documents'], isEmpty);
      expect(sections['profile'], isA<Map<String, dynamic>>());
    });

    test('rejects an unsupported backup version', () {
      expect(
        () => CloudStorageService.decodeBackup(jsonEncode(<String, dynamic>{
          'version': 99,
          'documents': <dynamic>[],
          'customers': <dynamic>[],
          'items': <dynamic>[],
          'payments': <dynamic>[],
          'profile': BusinessProfile().toJson(),
        })),
        throwsFormatException,
      );
    });

    test('rejects missing or malformed sections before upload', () {
      expect(
        () => CloudStorageService.decodeBackup(jsonEncode(<String, dynamic>{
          'version': 1,
          'documents': <dynamic>[],
          'customers': <dynamic>[],
          'items': <dynamic>[],
          'payments': <dynamic>[],
        })),
        throwsFormatException,
      );
      expect(
        () => CloudStorageService.decodeBackup(jsonEncode(<String, dynamic>{
          'version': 1,
          'documents': <dynamic>[],
          'customers': <dynamic>[],
          'items': <dynamic>[],
          'payments': <dynamic>[],
          'profile': <dynamic>[],
        })),
        throwsFormatException,
      );
    });

    test('encodes then decodes a complete backup', () {
      final sections = <String, dynamic>{
        'documents': <dynamic>[<String, dynamic>{'id': 'invoice-1'}],
        'customers': <dynamic>[],
        'items': <dynamic>[],
        'payments': <dynamic>[],
        'profile': BusinessProfile().toJson(),
      };

      final encoded = CloudStorageService.encodeBackup(sections);
      final decoded = CloudStorageService.decodeBackup(encoded);

      expect(decoded['documents'], hasLength(1));
      expect(decoded['documents'].first['id'], 'invoice-1');
    });

    test('detects whether a backup contains business data', () {
      final empty = CloudStorageService.encodeBackup(<String, dynamic>{
        'documents': <dynamic>[],
        'customers': <dynamic>[],
        'items': <dynamic>[],
        'payments': <dynamic>[],
        'profile': BusinessProfile().toJson(),
      });
      final withInvoice = CloudStorageService.encodeBackup(<String, dynamic>{
        'documents': <dynamic>[<String, dynamic>{'id': 'invoice-1'}],
        'customers': <dynamic>[],
        'items': <dynamic>[],
        'payments': <dynamic>[],
        'profile': BusinessProfile().toJson(),
      });

      expect(CloudStorageService.backupHasData(empty), isFalse);
      expect(CloudStorageService.backupHasData(withInvoice), isTrue);
    });
  });
}
