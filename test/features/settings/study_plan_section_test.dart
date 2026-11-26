/// 学习计划分组里 AI 重试遍数一项的 widget 测试。
///
/// 钉的是「滑条 → settings 表 → LlmAiConfig」这条完整链路：上一版
/// `llmConfigFromSettings` 从 `llmConfig.ai` 下读 `aiRetryCount`，
/// 用户改了设置也永远拿默认值。只测写入或只测解析都会漏掉这种断链。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/settings/study_plan_section.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 跟随 [appSettingsProvider] 重建的学习计划分组。
class _SettingsWatch extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(appSettingsProvider)
      .when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => Text('加载失败：$error'),
        data: (settings) => StudyPlanSection(settings: settings),
      );
}

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

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: LexiTheme.light,
          // 必须真的 watch 设置：直接传 `AppSettings.defaults` 的写法会让
          // 这块子树变成常量控件，写库后永远不会重建，回显断言就成了摆设。
          home: const Scaffold(body: _SettingsWatch()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 拖动滑条并等到设置真正落库、界面回显更新。
  ///
  /// 只 `pumpAndSettle` 是不够的：`saveSettings` 是一次真实的异步写库，
  /// 写完才让 `appSettingsProvider` 重建，而回显文案来自设置值。
  /// 这里改成轮询到预期文案出现为止，避免把「还没写完」误报成「没生效」。
  Future<void> dragAiRetryTo(
    WidgetTester tester,
    double dx,
    String expectedLabel,
  ) async {
    await tester.drag(
      find.descendant(
        of: find.byKey(const Key('studyPlanAiRetryCount')),
        matching: find.byType(Slider),
      ),
      Offset(dx, 0),
    );
    for (var i = 0; i < 20; i += 1) {
      await tester.pumpAndSettle();
      if (find.text(expectedLabel).evaluate().isNotEmpty) return;
    }
  }

  Future<Object?> storedValue(String key) async {
    final rows = await db.select(db.settings).get();
    for (final row in rows) {
      if (row.key == key) return jsonDecode(row.valueJson);
    }
    return null;
  }

  testWidgets('默认显示默认遍数并解释「遍」的含义', (tester) async {
    await pumpSection(tester);

    expect(find.text('AI 重试遍数'), findsNWidgets(2));
    expect(find.text('$aiRetryCountDefault 遍'), findsOneWidget);
    expect(
      find.textContaining('整条候选链'),
      findsOneWidget,
      reason: '必须说明重试单位是候选链重放，而不是单个模型重试',
    );
    expect(find.textContaining('词典补全'), findsOneWidget);
  });

  testWidgets('拉到最高写入 settings 表并到达 LlmAiConfig.retryCount', (tester) async {
    await pumpSection(tester);
    await dragAiRetryTo(tester, 4000, '$aiRetryCountCeiling 遍');

    expect(await storedValue('aiRetryCount'), aiRetryCountCeiling);

    final raw = (await settings.load()).raw;
    expect(raw[aiRetryCountSettingsKey], aiRetryCountCeiling);
    expect(llmConfigFromSettings(raw).ai.retryCount, aiRetryCountCeiling);
  });

  testWidgets('拉到最低写入 0 而不是负数', (tester) async {
    await pumpSection(tester);
    await dragAiRetryTo(tester, -4000, '$aiRetryCountFloor 遍');

    expect(await storedValue('aiRetryCount'), aiRetryCountFloor);
    expect(find.text('$aiRetryCountFloor 遍'), findsOneWidget);
  });
}
