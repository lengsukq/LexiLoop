/// 「未建模的键必须原样往返」的测试，以及 `backgroundConcurrency` 的去向结论。
///
/// **为什么这个测试重要**：`AppSettings` 只建模了学习计划、播放、数据源、
/// 词汇与题型五组设置；`llmConfig`、`merriamWebsterDictionaryKey`、
/// `translationProviderOrder` 这些键全部靠 [AppSettings.raw] 原样带出。
/// 解析是「读已知键 + 保留其余」，写回是「已知键覆盖 + 其余原样」——
/// 一旦这条链断掉，用户在 AI 页做完配置、在学习页改一次配额，AI 配置就没了。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../architecture/source_scan.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('未建模的键', () {
    test('连续两次保存后仍能从库里原样读回', () async {
      final service = SettingsService(SettingsDao(db));
      const llmConfig = <String, Object?>{
        'providers': <Object?>[
          <String, Object?>{
            'id': 'main',
            'name': '主',
            'apiType': 'openai',
            'baseUrl': 'https://example.test/v1',
            'apiKey': 'sk-secret',
            'models': <Object?>['m1', 'm2'],
            'defaultModel': 'm1',
          },
        ],
        'ai': <String, Object?>{'enabled': true, 'providerId': 'main'},
      };

      // 第一次：AI 页写入未建模的键。
      await service.update(<String, Object?>{
        'llmConfig': llmConfig,
        'merriamWebsterDictionaryKey': 'mw-dictionary-key',
        'translationProviderOrder': <Object?>['ai', 'youdao'],
      }, now: 1);
      // 第二次：学习页改一个已建模的键。
      await service.update(<String, Object?>{'dailyNewWords': 12}, now: 2);

      // 用全新的 service 实例读，绕开内存缓存，证明值真的落到了表里。
      final reloaded = await SettingsService(SettingsDao(db)).load();

      expect(reloaded.studyPlan.dailyNewWords, 12);
      expect(reloaded.raw['merriamWebsterDictionaryKey'], 'mw-dictionary-key');
      expect(reloaded.raw['translationProviderOrder'], <Object?>[
        'ai',
        'youdao',
      ]);
      final config = reloaded.raw['llmConfig']! as Map<String, Object?>;
      final providers = config['providers']! as List<Object?>;
      expect(providers.single, isA<Map<String, Object?>>());
      expect(
        (providers.single! as Map<String, Object?>)['apiKey'],
        'sk-secret',
      );
    });

    test('传 null 删除该键，回到默认值', () async {
      final service = SettingsService(SettingsDao(db));
      await service.update(<String, Object?>{'aiRetryCount': 4}, now: 1);
      await service.update(<String, Object?>{'aiRetryCount': null}, now: 2);

      final reloaded = await SettingsService(SettingsDao(db)).load();
      expect(reloaded.raw.containsKey('aiRetryCount'), isFalse);
      expect(
        reloaded.studyPlan.aiRetryCount,
        aiRetryCountDefault,
        reason: '键被删掉后应回到默认值而不是保留 4',
      );
    });
  });

  group('backgroundConcurrency', () {
    test('作为未建模的键原样往返（旧数据不丢）', () async {
      final service = SettingsService(SettingsDao(db));
      await service.update(<String, Object?>{
        'backgroundConcurrency': 4,
      }, now: 1);
      await service.update(<String, Object?>{'dailyNewWords': 8}, now: 2);

      final reloaded = await SettingsService(SettingsDao(db)).load();
      expect(reloaded.raw['backgroundConcurrency'], 4);
    });

    test('lib/ 下没有任何读取点——所以设置页不给它开输入框', () {
      final hits = <String>[];
      for (final file in collectDartFiles('lib')) {
        for (var i = 0; i < file.lines.length; i += 1) {
          final line = file.lines[i];
          if (!line.contains('backgroundConcurrency')) continue;
          if (isCommentOrBlank(line)) continue;
          hits.add('${file.locate(i + 1)}：${line.trim()}');
        }
      }

      expect(
        hits,
        isEmpty,
        reason: <String>[
          '出现了 backgroundConcurrency 的代码引用。',
          '如果这是新增的读取点，请顺手删掉本用例并在该处写明它控制什么；',
          '如果只是把它挪进了 raw 之类的数据结构，也请删掉本用例——',
          '本用例的前提是「这个键在本应用里没有任何消费方」。',
          '背景：旧版 Next.js 里它同样只有类型、默认值、zod 与界面四处出现，',
          '从来没有人读过；本版 worker 单进程且严格串行，没有可并发的调用面。',
          '命中：',
          ...hits,
        ].join('\n'),
      );
    });
  });
}
