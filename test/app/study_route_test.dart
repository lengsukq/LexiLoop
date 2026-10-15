/// `/study?mode=` 的路由测试。
///
/// **为什么这组用例非写不可**：8 种学习模式的服务层逻辑早已实现且有测试，
/// 但路由此前把模式写死成 `StudyMode.daily`——于是 7 种模式既没有 UI 入口
/// 也没有路由入口，测试全绿而功能不可达。这里从「用户点得到」的角度
/// 钉死：8 个取值各自落到正确的模式，非法值与裸路径都能兜底。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/study/study_page.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 直接在给定地址上打开应用，返回学习页当前配置的模式。
  ///
  /// **不用 `pumpAndSettle`**：会话开始后可能停在加载态（无限动画），
  /// `pumpAndSettle` 会一直等到超时。断言只依赖路由结果，不需要等会话。
  Future<StudyMode> modeAt(WidgetTester tester, String location) async {
    final router = createAppRouter(initialLocation: location);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        // 必须挂上应用主题：`context.lexiColors` 依赖 [LexiTheme] 注入的
        // 扩展，缺了它会在 `AmbientBackground` 里抛空断言。
        child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(StudyPage), findsOneWidget, reason: '应渲染学习页');
    return tester.widget<StudyPage>(find.byType(StudyPage)).mode;
  }

  for (final mode in StudyMode.values) {
    testWidgets('/study?mode=${mode.wire} 进入对应模式', (tester) async {
      expect(await modeAt(tester, '/study?mode=${mode.wire}'), mode);
    });
  }

  testWidgets('未知的 mode 兜底为每日综合', (tester) async {
    expect(await modeAt(tester, '/study?mode=NOT_A_MODE'), StudyMode.daily);
  });

  testWidgets('裸 /study 仍然可用', (tester) async {
    expect(await modeAt(tester, '/study'), StudyMode.daily);
  });

  group('studyModeOf', () {
    test('缺失与非法取值都退回每日综合', () {
      expect(studyModeOf(null), StudyMode.daily);
      expect(studyModeOf(''), StudyMode.daily);
      expect(studyModeOf('daily'), StudyMode.daily);
      expect(studyModeOf('WRONG_WORDS'), StudyMode.wrongWords);
    });
  });
}
