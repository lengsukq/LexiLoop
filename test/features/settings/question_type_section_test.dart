/// 题型分组的 widget 测试。
///
/// 覆盖旧版 `question-type-settings.tsx` 有、本版缺失的那层「外壳」：
/// 4 个权重预设、「重置均衡」、权重占比条与 4 组分组。
/// 预设的权重取值本身由 `test/domain/models/app_settings_test.dart` 钉住，
/// 这里只钉「点得动、存得对、不会顺手改掉别的题型」。
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
import 'package:lexiloop/features/settings/question_type_section.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    // 分组后题型区更高，8 行 ×（标签 + 说明 + 滑条）需要足够的画布。
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(
            body: QuestionTypeSection(settings: AppSettings.defaults),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Map<String, Object?>> storedConfig() async {
    final rows = await db.select(db.settings).get();
    for (final row in rows) {
      if (row.key == 'questionTypeConfig') {
        return jsonDecode(row.valueJson) as Map<String, Object?>;
      }
    }
    throw StateError('questionTypeConfig 未写入');
  }

  Future<int> storedWeight(QuestionType type) async {
    final config = await storedConfig();
    final entry = config[type.wire]! as Map<String, Object?>;
    return entry['weight']! as int;
  }

  Future<void> tapPreset(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('questionTypePreset-$id')));
    await tester.pumpAndSettle();
  }

  Future<void> dragWeight(
    WidgetTester tester,
    QuestionType type,
    double dx,
  ) async {
    await tester.drag(
      find.descendant(
        of: find.byKey(Key('questionTypeWeight-${type.wire}')),
        matching: find.byType(Slider),
      ),
      Offset(dx, 0),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('展示 4 个预设、4 个分组与 8 种题型', (tester) async {
    await pumpSection(tester);

    for (final preset in questionTypeWeightPresets) {
      expect(
        find.byKey(Key('questionTypePreset-${preset.id}')),
        findsOneWidget,
      );
    }
    expect(find.text('重置均衡'), findsOneWidget);
    for (final label in <String>['看词认义', '拼写输出', '听力训练', '语境运用']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final type in QuestionType.values) {
      expect(questionTypeLabel(type), isNotEmpty);
      expect(
        find.byKey(Key('questionTypeSwitch-${type.wire}')),
        findsOneWidget,
        reason: type.wire,
      );
    }
  });

  testWidgets('占比合计为 100%，未启用的题型显示「未启用」', (tester) async {
    await pumpSection(tester);

    // 8 种题型权重相同，各占 12.5%，四舍五入后仍是 13% × 8 = 104 的问题
    // 由 domain 侧保证，这里断言的是「界面拿到的就是 100% 的分配」。
    final shares = QuestionTypeConfig.defaults.sharePercents();
    expect(shares.reduce((a, b) => a + b), closeTo(100, 1e-9));
    expect(find.text('13%'), findsNWidgets(8));

    await tester.tap(
      find.byKey(Key('questionTypeSwitch-${QuestionType.letterBank.wire}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('未启用'), findsOneWidget);
  });

  testWidgets('点「拼写强化」只改列出的三种题型', (tester) async {
    await pumpSection(tester);
    await tapPreset(tester, 'spellingFocus');

    expect(await storedWeight(QuestionType.zhToEnSpelling), 9);
    expect(await storedWeight(QuestionType.letterBank), 8);
    expect(await storedWeight(QuestionType.clozeSentence), 7);
    expect(
      await storedWeight(QuestionType.enToZh),
      defaultQuestionTypeWeight,
      reason: '预设没列出的题型必须保持用户当前值',
    );
  });

  testWidgets('应用预设后手动调一个题型，其余保持预设值', (tester) async {
    await pumpSection(tester);
    await tapPreset(tester, 'spellingFocus');
    await dragWeight(tester, QuestionType.letterBank, -4000);

    expect(await storedWeight(QuestionType.letterBank), minQuestionTypeWeight);
    expect(await storedWeight(QuestionType.zhToEnSpelling), 9);
    expect(await storedWeight(QuestionType.clozeSentence), 7);
  });

  testWidgets('「重置均衡」恢复全部启用且权重一致', (tester) async {
    await pumpSection(tester);
    await tapPreset(tester, 'listeningFocus');
    await tester.tap(
      find.byKey(Key('questionTypeSwitch-${QuestionType.letterBank.wire}')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('questionTypeResetBalanced')));
    await tester.pumpAndSettle();

    final config = await storedConfig();
    for (final type in QuestionType.values) {
      final entry = config[type.wire]! as Map<String, Object?>;
      expect(entry['enabled'], isTrue, reason: type.wire);
      expect(entry['weight'], defaultQuestionTypeWeight, reason: type.wire);
    }
  });

  testWidgets('保存后重新加载仍能读回预设结果', (tester) async {
    await pumpSection(tester);
    await tapPreset(tester, 'recallFirst');

    final settings = SettingsService(SettingsDao(db));
    final reloaded = await settings.load();
    expect(reloaded.questionTypeConfig.weightOf(QuestionType.enToZhChoice), 8);
    expect(reloaded.questionTypeConfig.weightOf(QuestionType.zhToEnChoice), 7);
  });
}
