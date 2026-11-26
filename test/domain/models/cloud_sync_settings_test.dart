import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';

void main() {
  group('normalizeCloudSyncBaseUrl', () {
    test('trims whitespace and trailing slashes for valid http/https URLs', () {
      expect(
        normalizeCloudSyncBaseUrl('  https://lexiloop.vercel.app///  '),
        'https://lexiloop.vercel.app',
      );
      expect(
        normalizeCloudSyncBaseUrl('http://192.168.1.5:3000/sub/'),
        'http://192.168.1.5:3000/sub',
      );
    });

    test('rejects empty, non-http, or hostless strings', () {
      expect(normalizeCloudSyncBaseUrl(''), isNull);
      expect(normalizeCloudSyncBaseUrl('ftp://example.com'), isNull);
      expect(normalizeCloudSyncBaseUrl('example.com'), isNull);
      expect(normalizeCloudSyncBaseUrl('https://'), isNull);
    });
  });

  group('cloudSyncSettingsFromRaw & secret stripping', () {
    test('round-trips full settings including watermark', () {
      const original = CloudSyncSettings(
        credential: CloudSyncCredential(
          baseUrl: 'https://lexiloop.vercel.app',
          password: 'top-secret-password',
        ),
        mode: CloudSyncMode.pullMerge,
        status: CloudSyncLastStatus(
          lastSuccessAt: 1730000000000,
          lastServerWordCount: 120,
          lastSummary: '本机 +2 词',
        ),
        watermark: CloudSyncWatermark(
          serverDeviceId: 'srv-01',
          serverDatasetEpoch: 'ep-01',
          serverCursorMs: 1730000000000,
          localCursorMs: 1730000000500,
        ),
      );

      final parsed = cloudSyncSettingsFromRaw(original.toStorage());
      expect(parsed.credential?.baseUrl, 'https://lexiloop.vercel.app');
      expect(parsed.credential?.password, 'top-secret-password');
      expect(parsed.mode, CloudSyncMode.pullMerge);
      expect(parsed.watermark?.serverDeviceId, 'srv-01');
      expect(parsed.watermark?.serverCursorMs, 1730000000000);
      expect(parsed.status.lastServerWordCount, 120);
    });

    test('strips password and transient state on export', () {
      final exported = cloudSyncValueForExport(<String, Object?>{
        'baseUrl': 'https://lexiloop.vercel.app',
        'password': 'must-not-leak',
        'mode': 'BIDIRECTIONAL',
        'lastSuccessAt': 1730000000000,
        'watermark': <String, Object?>{'serverDeviceId': 'srv-01'},
      });

      expect(exported['baseUrl'], 'https://lexiloop.vercel.app');
      expect(exported['mode'], 'BIDIRECTIONAL');
      expect(exported.containsKey('password'), isFalse);
      expect(exported.containsKey('lastSuccessAt'), isFalse);
      expect(exported.containsKey('watermark'), isFalse);
    });
  });
}
