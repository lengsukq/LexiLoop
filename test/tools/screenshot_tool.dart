/// 离屏截图工具（不参与常规 `flutter test` 门禁）。
///
/// 用途：在没有窗口服务的环境里**看到**页面。macOS 的 `screencapture` 与
/// AppleScript 窗口查询都需要「录屏 / 辅助功能」授权，未授权时截图全黑、
/// 窗口数恒为 0——本会话正好卡在这里。这个工具绕过窗口服务：在测试里直接
/// 把渲染树画进 PNG。
///
/// 用法：`flutter test --no-pub test/tools/screenshot_tool.dart`
/// 产物：`build/screens/*.png`
///
/// 几个必须的细节：
/// * **要装真字体**。测试环境默认没有可用字体，文字会被画成方块，
///   截图失去意义。这里从系统装一份带中文的字体。
/// * 每个页面给足 pump 次数，等异步查询落库。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/configurator/initialization_configurator.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../services/audio/audio_fakes.dart';

/// 截图的宽高（macOS 默认窗口）。
const Size shotSize = Size(1280, 840);

/// 手机视口（iPhone 14 逻辑尺寸）。
///
/// 桌面尺寸之外**必须再出一套窄屏**：两端的布局分支完全不同
/// （侧边栏 / 底部 Tab、平铺筛选 / 筛选面板、单行页头 / 两行页头），
/// 只截桌面等于只验证了一半。
const Size phoneSize = Size(390, 844);

void main() {
  setUpAll(() async {
    // 装一份带中文的真字体，否则文字全是方块。注册多个常见族名，
    // 覆盖主题在 `null` 之外可能请求的名字。
    const cjkPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
    final cjk = File(cjkPath);
    if (cjk.existsSync()) {
      final bytes = await cjk.readAsBytes();
      for (final family in <String>[
        'Roboto',
        'PingFang SC',
        'Hiragino Sans GB',
        '.SF UI Text',
        '.AppleSystemUIFont',
      ]) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
    }
    // 图标字体：不装的话所有 Icon 都是方块。
    const iconPath =
        '/opt/homebrew/Caskroom/flutter/3.47.5/flutter/bin/cache/'
        'artifacts/material_fonts/MaterialIcons-Regular.otf';
    final icons = File(iconPath);
    if (icons.existsSync()) {
      final bytes = await icons.readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });

  testWidgets('shot configurator', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seedDemoData(db);
    tester.view.physicalSize = shotSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
          audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
        ],
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: LexiTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showInitializationConfigurator(
                      context,
                      initialScope: ConfiguratorScope.all,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _capture(tester, boundaryKey, 'configurator');
  });

  for (final route in <String>[
    '/',
    '/words',
    '/statistics',
    '/add',
    '/initialize',
    '/import',
    '/settings',
    '/games',
    '/phonetics',
    '/match',
  ]) {
    testWidgets('shot $route', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // 塞一点数据：空库只能看到空态，而「页面好不好看」主要在**有内容**时
      // 才看得出来（列表行、图表、进度条、分页条都在这一步才出现）。
      await seedDemoData(db);
      tester.view.physicalSize = shotSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final boundaryKey = GlobalKey();
      final router = createAppRouter(initialLocation: route);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            databaseProvider.overrideWithValue(db),
            audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
            audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
            studyClockFactoryProvider.overrideWithValue(
              () => StudyClock(
                now: () => DateTime(2026, 3, 1, 10).millisecondsSinceEpoch,
              ),
            ),
          ],
          child: RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp.router(
              theme: LexiTheme.light,
              routerConfig: router,
            ),
          ),
        ),
      );
      for (var i = 0; i < 14; i += 1) {
        await tester.pump(const Duration(milliseconds: 90));
      }

      final name = route == '/' ? 'dashboard' : route.replaceAll('/', '');
      await _capture(tester, boundaryKey, name);
      // 同一页再出一张手机宽度的：
      tester.view.physicalSize = phoneSize;
      await tester.pumpAndSettle();
      await _capture(tester, boundaryKey, '${name}_phone');
    });
  }
}

/// 塞入一批演示数据：不同掌握度、有作答记录、有初始化任务。
Future<void> seedDemoData(AppDatabase db) async {
  final now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  const terms = <String>[
    'apple',
    'banana',
    'cherry',
    'dragonfruit',
    'elderberry',
    'fig',
    'grape',
    'honeydew',
  ];
  for (var i = 0; i < terms.length; i += 1) {
    final term = terms[i];
    await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term,
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: now - i * 86400000,
            updatedAt: now - i * 86400000,
          ),
        );
  }
  final ids = await db.select(db.words).get();
  for (final word in ids) {
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(word.id),
            summaryJson: const Value<String>(
              '{"shortDefinition":"a sample word","translation":"示例词"}',
            ),
            definitionsJson: const Value<String>(
              '[{"partOfSpeech":"n.","meaning":"示例释义"}]',
            ),
            updatedAt: now,
          ),
        );
  }
  // 作答记录：让统计页的折线与表格有东西可画。
  for (var day = 0; day < 12; day += 1) {
    for (var n = 0; n < (day % 5) + 2; n += 1) {
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              clientAnswerId: 'shot-$day-$n',
              wordId: ids[day % ids.length].id,
              reviewedAt: now - day * 86400000 + n * 60000,
              rating: n.isEven ? ReviewRating.good : ReviewRating.again,
              questionType: QuestionType.enToZhChoice,
              isCorrect: n.isEven,
              durationMs: const Value<int>(4200),
              createdAt: now - day * 86400000 + n * 60000,
            ),
          );
    }
  }
}

/// 把 `RepaintBoundary` 画进 `build/screens/<name>.png`。
Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/screens/$name.png');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(data!.buffer.asUint8List());
  });
}
