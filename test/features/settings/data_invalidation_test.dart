/// 恢复本地数据后缓存失效的行为测试。
///
/// 对应 `lib/features/settings/data_invalidation.dart` 的清单。
/// 备份导入是**原地替换**同一个 SQLite 文件的内容而 `AppDatabase` 实例不变，
/// 所以已经算出来的 `FutureProvider` 快照会变过期——这组用例逐个验证
/// 最容易在真实使用中撞到的几条路径。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/words/words_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
  });

  void invalidate() => invalidateDataBackedProviders(
    invalidate: container.invalidate,
    settings: container.read(settingsServiceProvider),
  );

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord(String term) async {
    const now = 1;
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh-CN',
            entryType: EntryType.word,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(
              jsonEncode(<Object?>[
                <String, Object?>{'language': 'zh-CN', 'text': '$term 的释义'},
              ]),
            ),
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 造一份只含 N 个词条的合法备份。
  String backupWith(int words) {
    const now = 1;
    return jsonEncode(<String, Object?>{
      'format': backupFormat,
      'version': 3,
      'exportedAt': DateTime(2026, 3, 2).toIso8601String(),
      'words': <Map<String, Object?>>[
        for (var i = 0; i < words; i += 1)
          <String, Object?>{
            'id': i + 1,
            'term': 'w$i',
            'normalized_term': 'w$i',
            'source_language': 'en',
            'target_language': 'zh-CN',
            'entry_type': 'WORD',
            'content_type': 'WORD',
            'initialization_status': 'READY',
            'mastery_score': 0,
            'created_at': now,
            'updated_at': now,
          },
      ],
    });
  }

  test('恢复备份后词库列表与词条数刷新', () async {
    await insertWord('before');
    expect(await container.read(wordCountProvider.future), 1);

    await BackupImporter(db).import(backupWith(5));
    invalidate();

    expect(await container.read(wordCountProvider.future), 5);
    expect(await container.read(wordListProvider.future), hasLength(5));
  });

  test('恢复备份后首页概览刷新', () async {
    await insertWord('before');
    expect(
      (await container.read(dashboardOverviewProvider.future)).totalWords,
      1,
    );

    await BackupImporter(db).import(backupWith(3));
    invalidate();

    final overview = await container.read(dashboardOverviewProvider.future);
    expect(overview.totalWords, 3);
  });

  test('恢复备份后统计概览刷新', () async {
    await insertWord('before');
    await container.read(statisticsOverviewProvider.future);

    await BackupImporter(db).import(backupWith(7));
    invalidate();

    final overview = await container.read(statisticsOverviewProvider.future);
    expect(overview.totalWords, 7);
  });

  test('清单覆盖了所有会读库的顶层 provider', () {
    // 这条不是行为断言而是「清单不许悄悄变短」：几个关键页面必须在列，
    // 否则恢复备份后它们会继续显示导入前的快照。
    expect(
      dataBackedProviders,
      containsAll(<Object>[
        wordListProvider,
        wordCountProvider,
        dashboardOverviewProvider,
        dailySuggestionProvider,
        statisticsOverviewProvider,
        queuePageProvider,
        queueProgressProvider,
      ]),
    );
  });
}
