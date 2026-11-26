/// 关键交互状态的本地截图，不访问真实数据或外部服务。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/study/study_choice_options.dart';
import 'package:lexiloop/services/tts_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

import '../../tool/visual_fixture.dart';
import '../services/audio/audio_fakes.dart';
import 'screenshot_tool.dart';

Future<GlobalKey> showScene(
  WidgetTester tester,
  String route, {
  bool dark = false,
  bool phone = true,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await seedDemoData(db);
  final router = createAppRouter(initialLocation: route);
  addTearDown(router.dispose);
  tester.view.physicalSize = phone ? phoneSize : shotSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
        audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
        ttsServiceProvider.overrideWithValue(
          TtsService(RecordingSpeechEngine()),
        ),
        // 截图固定「选项立即出现、自动朗读关」：2 秒倒计时会让题目截图
        // 只剩一个进度条，自动朗读则会让无头环境去碰平台通道。
        appSettingsProvider.overrideWith(
          (ref) => appSettingsFromRaw(<String, Object?>{
            'choiceRevealDelaySeconds': 0,
            'autoPlayPronunciation': false,
          }),
        ),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp.router(
          theme: screenshotTheme(dark ? LexiTheme.dark : LexiTheme.light),
          debugShowCheckedModeBanner: false,
          builder: (context, child) => AdaptiveTypography(child: child!),
          routerConfig: router,
        ),
      ),
    ),
  );
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return key;
}

void main() {
  VisualCaptureBinding();
  setUpAll(loadScreenshotFonts);
  for (final phone in <bool>[true, false]) {
    for (final dark in <bool>[false, true]) {
      final variant =
          '${phone ? "phone" : "desktop"}_${dark ? "dark" : "light"}';
      testWidgets('设置分类 $variant', (tester) async {
        final key = await showScene(
          tester,
          '/settings',
          dark: dark,
          phone: phone,
        );
        for (final label in <String>[
          '学习计划',
          '题型',
          '播放',
          '数据源',
          '词汇与考试',
          'AI 模型',
          '数据管理',
        ]) {
          await tester.tap(find.widgetWithText(ListTile, label));
          await tester.pumpAndSettle();
          await captureScreenshot(
            tester,
            key,
            'states/settings_${label}_$variant',
          );
          if (phone) {
            await tester.tap(find.byTooltip('设置分类'));
            await tester.pumpAndSettle();
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final mode in GameMode.values.where((mode) => mode.isMiniGame)) {
    testWidgets('游戏进行 ${mode.wire}', (tester) async {
      final key = await showScene(tester, '/games?mode=${mode.wire}');
      await tester.ensureVisible(find.text('开始'));
      await tester.tap(find.text('开始'));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byTooltip('退出'), findsOneWidget);
      await captureScreenshot(tester, key, 'states/game_${mode.wire}_phone');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('手机筛选面板', (tester) async {
    final key = await showScene(tester, '/words', dark: true);
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    await captureScreenshot(tester, key, 'states/word_filter_phone_dark');
    expect(tester.takeException(), isNull);
  });
  testWidgets('编辑词条弹窗', (tester) async {
    final key = await showScene(tester, '/words/1');
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await captureScreenshot(tester, key, 'states/edit_word_phone');
    expect(tester.takeException(), isNull);
  });
  for (final phone in <bool>[true, false]) {
    for (final dark in <bool>[false, true]) {
      final variant =
          '${phone ? "phone" : "desktop"}_${dark ? "dark" : "light"}';
      testWidgets('学习揭示 $variant', (tester) async {
        final key = await showScene(tester, '/study', dark: dark, phone: phone);
        // 演示题库的题型会随当前计划变化：选择题点第一个选项、看词说义点
        // 「显示答案」、文本题先填一个字再检查。三条路都能到揭示态，截图
        // 不依赖当天抽到哪道题。
        final options = find.descendant(
          of: find.byType(ChoiceOptions),
          matching: find.byType(InkWell),
        );
        if (options.evaluate().isNotEmpty) {
          await tester.tap(options.first);
        } else if (find.text('显示答案').evaluate().isNotEmpty) {
          await tester.tap(find.text('显示答案'));
        } else {
          await tester.enterText(find.byType(TextField), 'x');
          await tester.pump();
          await tester.tap(find.text('检查答案'));
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('study.reveal')), findsOneWidget);
        await captureScreenshot(tester, key, 'states/study_reveal_$variant');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
