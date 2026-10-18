/// 设置页的 widget 测试。
///
/// 覆盖「显示当前值」「改滑条真的落库」「全部关闭题型被拦下」
/// 与「未建模的 MW Key 能从 raw 读回」四件事。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/providers_section.dart';
import 'package:lexiloop/features/settings/settings_page.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    // 设置页有 6 个 tab，题型 tab 有 8 行开关 + 滑条：
    // 画布不够高会让控件落在屏幕外，点不到。
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: LexiTheme.light, home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    // 设置页新增了「外观」并放在第一位；这些用例测的是学习计划之后的
    // 分组，先切回学习计划，保持用例本身只关心被测分组。
    await tester.tap(find.text('学习计划'));
    await tester.pumpAndSettle();
  }

  /// 读取 `settings` 表里某个键的 JSON 值。
  Future<Object?> storedValue(String key) async {
    final rows = await db.select(db.settings).get();
    for (final row in rows) {
      if (row.key == key) return jsonDecode(row.valueJson);
    }
    return null;
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('默认显示当前配额与保持率', (tester) async {
    await pumpSettings(tester);

    expect(find.text('每日新词'), findsOneWidget);
    // 新词与错词的默认配额都是 10，因此这里各有两处相同文案。
    expect(find.text('$defaultDailyNewWords 个'), findsNWidgets(2));
    expect(find.text('$defaultDailyWrongWordLimit 个'), findsNWidgets(2));
    expect(find.text('$defaultDailyDueReviewLimit 个'), findsOneWidget);
    expect(
      find.text('${(defaultRetentionRate * 100).round()}%'),
      findsOneWidget,
    );
  });

  testWidgets('拖动配额滑条后写入 settings 表', (tester) async {
    await pumpSettings(tester);

    await tester.drag(
      find.descendant(
        of: find.byKey(const Key('studyPlanDailyNewWords')),
        matching: find.byType(Slider),
      ),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();

    final stored = await storedValue('dailyNewWords');
    expect(stored, isA<int>());
    expect(stored! as int, greaterThan(defaultDailyNewWords));
  });

  testWidgets('拖动保持率滑条后写入 settings 表', (tester) async {
    await pumpSettings(tester);

    await tester.drag(
      find.descendant(
        of: find.byKey(const Key('studyPlanRetention')),
        matching: find.byType(Slider),
      ),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();

    final stored = await storedValue('targetRetentionRate');
    expect(stored, isA<num>());
    expect(
      (stored! as num).toDouble(),
      inInclusiveRange(minRetentionRate, maxRetentionRate),
    );
  });

  testWidgets('关闭单个题型会写回配置', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, '题型');

    await tester.tap(
      find.byKey(Key('questionTypeSwitch-${QuestionType.letterBank.wire}')),
    );
    await tester.pumpAndSettle();

    final stored = await storedValue('questionTypeConfig');
    expect(stored, isA<Map<String, Object?>>());
    final config = stored! as Map<String, Object?>;
    final entry = config[QuestionType.letterBank.wire]! as Map<String, Object?>;
    expect(entry['enabled'], isFalse);
  });

  testWidgets('全部关闭题型时给出提示且不保存', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, '题型');

    for (final type in QuestionType.values) {
      await tester.tap(find.byKey(Key('questionTypeSwitch-${type.wire}')));
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const Key('questionTypeBlockedNotice')), findsOneWidget);
    expect(find.textContaining('至少要启用一种题型'), findsOneWidget);

    // 最后一个开关必须保持开启，否则会出现「抽不出题型」的空白会话。
    final stored = await storedValue('questionTypeConfig');
    final config = stored! as Map<String, Object?>;
    final enabled = config.values.whereType<Map<String, Object?>>().where(
      (entry) => entry['enabled'] == true,
    );
    expect(enabled, hasLength(1));
  });

  testWidgets('切换播放口音写入 settings 表', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, '播放');

    await tester.tap(find.text('英音 UK'));
    await tester.pumpAndSettle();

    expect(await storedValue('defaultAccent'), Accent.uk.wire);
  });

  testWidgets('数据源开关写入 settings 表', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, '数据源');
    await tester.tap(find.text('Merriam-Webster 密钥'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('providerSwitch-youdao')));
    await tester.pumpAndSettle();

    expect(await storedValue('youdaoEnabled'), isFalse);
  });

  testWidgets('Merriam-Webster Key 写入后能从 raw 读回', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, '数据源');
    await tester.tap(find.text('Merriam-Webster 密钥'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('merriamWebsterDictionaryKeyField')),
      'mw-dictionary-key',
    );
    await tester.pumpAndSettle();

    final loaded = await settings.load();
    expect(loaded.raw[merriamWebsterDictionaryKeyName], 'mw-dictionary-key');
  });

  testWidgets('考试目标可多选并写入 settings 表', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, '词汇与考试');

    await tester.tap(
      find.byKey(Key('examTarget-${VocabularyLevel.cet4.wire}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('examTarget-${VocabularyLevel.ielts.wire}')),
    );
    await tester.pumpAndSettle();

    final stored = await storedValue('examTargets');
    expect(stored, <Object?>['CET4', 'IELTS']);
  });

  testWidgets('数据管理 tab 显示 CSV 导入、远程备份与危险区', (tester) async {
    await pumpSettings(tester);
    await openTab(tester, '数据管理');

    expect(find.byKey(const Key('openCsvImport')), findsOneWidget);
    expect(find.byKey(const Key('clearAllData')), findsOneWidget);
    // 远程备份分组也在同一个 tab 里，且未配置时上传按钮不可点。
    expect(find.byKey(const Key('webdavBaseUrlField')), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('uploadToWebdav')))
          .onPressed,
      isNull,
    );
  });
}
