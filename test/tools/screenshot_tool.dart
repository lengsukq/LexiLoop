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
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/dashboard/cards/practice_card.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/configurator/initialization_configurator.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/ui/theme/lexi_appearance.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

import '../../tool/visual_fixture.dart';
import '../services/audio/audio_fakes.dart';

/// 截图保留真实阴影模糊；普通功能测试仍使用默认测试绑定。
class VisualCaptureBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

/// 截图的宽高（macOS 默认窗口）。
const Size shotSize = Size(1280, 840);

/// 手机视口（iPhone 14 逻辑尺寸）。
///
/// 桌面尺寸之外**必须再出一套窄屏**：两端的布局分支完全不同
/// （侧边栏 / 底部 Tab、平铺筛选 / 筛选面板、单行页头 / 两行页头），
/// 只截桌面等于只验证了一半。
const Size phoneSize = Size(390, 844);

void main() {
  VisualCaptureBinding();
  setUpAll(loadScreenshotFonts);

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
            theme: screenshotTheme(LexiTheme.light),
            debugShowCheckedModeBanner: false,
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
    await captureScreenshot(tester, boundaryKey, 'configurator');
  });

  testWidgets('shot practice sheet', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seedDemoData(db);
    tester.view.physicalSize = shotSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final boundaryKey = GlobalKey();
    final router = createAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
          audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
          studyClockFactoryProvider.overrideWithValue(
            () => StudyClock(now: () => DateTime.now().millisecondsSinceEpoch),
          ),
          appSettingsProvider.overrideWith(
            (ref) => appSettingsFromRaw(<String, Object?>{
              'choiceRevealDelaySeconds': 0,
              'autoPlayPronunciation': false,
            }),
          ),
        ],
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp.router(
            theme: screenshotTheme(LexiTheme.light),
            darkTheme: screenshotTheme(LexiTheme.dark),
            debugShowCheckedModeBanner: false,
            builder: (context, child) => AdaptiveTypography(child: child!),
            routerConfig: router,
          ),
        ),
      ),
    );
    for (var i = 0; i < 14; i += 1) {
      await tester.pump(const Duration(milliseconds: 90));
    }
    await tester.ensureVisible(find.byKey(practiceAllButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(practiceAllButtonKey));
    await tester.pumpAndSettle();
    await captureScreenshot(tester, boundaryKey, 'practice_sheet');
    expect(tester.takeException(), isNull);
  });

  for (final route in <String>[
    '/',
    '/words',
    '/words/1',
    '/study',
    '/article',
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
      final appearance = ValueNotifier<ThemeMode>(ThemeMode.light);
      addTearDown(appearance.dispose);
      final router = createAppRouter(initialLocation: route);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            databaseProvider.overrideWithValue(db),
            audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
            audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
            studyClockFactoryProvider.overrideWithValue(
              () =>
                  StudyClock(now: () => DateTime.now().millisecondsSinceEpoch),
            ),
            // 选项立即出现：延迟倒计时会让学习页截图只剩进度条。
            appSettingsProvider.overrideWith(
              (ref) => appSettingsFromRaw(<String, Object?>{
                'choiceRevealDelaySeconds': 0,
                'autoPlayPronunciation': false,
              }),
            ),
          ],
          child: RepaintBoundary(
            key: boundaryKey,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: appearance,
              builder: (context, mode, _) => MaterialApp.router(
                theme: screenshotTheme(LexiTheme.light),
                darkTheme: screenshotTheme(LexiTheme.dark),
                themeMode: mode,
                debugShowCheckedModeBanner: false,
                builder: (context, child) => AdaptiveTypography(child: child!),
                routerConfig: router,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 14; i += 1) {
        await tester.pump(const Duration(milliseconds: 90));
      }

      final name = route == '/' ? 'dashboard' : route.replaceAll('/', '');
      await captureScreenshot(tester, boundaryKey, name);
      // 同一页再出一张手机宽度的：
      tester.view.physicalSize = phoneSize;
      await tester.pumpAndSettle();
      await captureScreenshot(tester, boundaryKey, '${name}_phone');
      appearance.value = ThemeMode.dark;
      await tester.pumpAndSettle();
      await captureScreenshot(tester, boundaryKey, '${name}_phone_dark');
      tester.view.physicalSize = shotSize;
      await tester.pumpAndSettle();
      await captureScreenshot(tester, boundaryKey, '${name}_dark');
      expect(tester.takeException(), isNull);
    });
  }

  // 主题多样性：同一页在「海蓝/青」与「粉/紫」下各出一张桌面明暗图。
  // 默认主题的 13 条路由仍由上面的循环覆盖；这里只取首页与设置页，
  // 它们分别代表「内容排版」与「控件密度」两种极端。
  const altThemes = <String, (int, int)>{
    'ocean': (0xFF0A84FF, 0xFF30B0C7),
    'sakura': (0xFFFF2D55, 0xFFAF52DE),
  };
  for (final entry in altThemes.entries) {
    for (final route in <String>['/', '/settings']) {
      testWidgets('shot theme ${entry.key} $route', (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await seedDemoData(db);
        tester.view.physicalSize = shotSize;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final boundaryKey = GlobalKey();
        final appearance = ValueNotifier<LexiAppearance>(
          LexiAppearance(
            primary: Color(entry.value.$1),
            secondary: Color(entry.value.$2),
            mode: ThemeMode.light,
          ),
        );
        addTearDown(appearance.dispose);
        final router = createAppRouter(initialLocation: route);
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              databaseProvider.overrideWithValue(db),
              audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
              audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
              appSettingsProvider.overrideWith(
                (ref) => appSettingsFromRaw(<String, Object?>{}),
              ),
            ],
            child: RepaintBoundary(
              key: boundaryKey,
              child: ValueListenableBuilder<LexiAppearance>(
                valueListenable: appearance,
                builder: (context, value, _) {
                  final bundle = LexiTheme.build(value);
                  return MaterialApp.router(
                    theme: screenshotTheme(bundle.light),
                    darkTheme: screenshotTheme(bundle.dark),
                    themeMode: bundle.mode,
                    debugShowCheckedModeBanner: false,
                    builder: (context, child) =>
                        AdaptiveTypography(child: child!),
                    routerConfig: router,
                  );
                },
              ),
            ),
          ),
        );
        for (var i = 0; i < 14; i += 1) {
          await tester.pump(const Duration(milliseconds: 90));
        }
        final name = route == '/' ? 'dashboard' : 'settings';
        await captureScreenshot(
          tester,
          boundaryKey,
          'themes/${entry.key}_${name}_light',
        );
        appearance.value = appearance.value.copyWith(mode: ThemeMode.dark);
        await tester.pumpAndSettle();
        await captureScreenshot(
          tester,
          boundaryKey,
          'themes/${entry.key}_${name}_dark',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

/// 把 `RepaintBoundary` 画进 `build/screens/<name>.png`。
Future<void> captureScreenshot(
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

/// 离屏环境没有系统字体回退，显式加载本地字体供正文和按钮使用。
ThemeData screenshotTheme(ThemeData base) {
  const family = 'LexiScreenshot';
  final label = LexiType.callout.copyWith(fontFamily: family);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style!.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle>(label),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style!.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle>(label),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style!.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle>(label),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: base.segmentedButtonTheme.style!.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle>(
          LexiType.footnote.copyWith(fontFamily: family),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: LexiType.footnote.copyWith(fontFamily: family),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      hintStyle: LexiType.body.copyWith(fontFamily: family),
    ),
  );
}

/// 加载本机字体，截图不需要网络资源。
Future<void> loadScreenshotFonts() async {
  // 装一份带中文的真字体，否则文字全是方块。注册多个常见族名，
  // 覆盖主题在 `null` 之外可能请求的名字。
  //
  // **跨平台**：项目在 Windows 上同样要出截图；只写 macOS 路径会让所有
  // 中文变成方块（方块不是「字体没装」的证据，只是这份工具的盲区）。
  final candidates = <String>[
    if (Platform.isMacOS) ...<String>[
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      '/System/Library/Fonts/PingFang.ttc',
    ],
    if (Platform.isWindows) ...<String>[
      r'C:\Windows\Fonts\simhei.ttf',
      r'C:\Windows\Fonts\Deng.ttf',
      r'C:\Windows\Fonts\arialuni.ttf',
      r'C:\Windows\Fonts\msyh.ttc',
      r'C:\Windows\Fonts\msyhbd.ttc',
    ],
    if (Platform.isLinux) ...<String>[
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
    ],
  ];
  var loadedCjk = false;
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = await file.readAsBytes();
      for (final family in <String>[
        'LexiScreenshot',
        'Ahem',
        'sans-serif',
        'Arial',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        '.SF UI Display',
        'Roboto',
        'PingFang SC',
        'Hiragino Sans GB',
        'Microsoft YaHei',
        '.SF UI Text',
        '.AppleSystemUIFont',
        '.SF Pro Text',
        '.SF Pro Display',
      ]) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
      loadedCjk = true;
      break;
    } on Object {
      // TTC 合集或损坏字体加载失败时换下一个候选，不让截图整体失败。
      loadedCjk = false;
    }
  }
  if (!loadedCjk) {
    // 没有可用系统字体时，至少让截图明确暴露问题，而不是静默出方块。
    // 测试日志里能看到这一行；常规 `flutter test` 不加载本函数。
    // ignore: avoid_print
    print('截图字体：未找到可用的中文字体，文字可能显示为方块。');
  }
  final lucide = await rootBundle.load(
    'packages/lucide_icons_flutter/assets/lucide.ttf',
  );
  await (FontLoader(
    'packages/lucide_icons_flutter/Lucide',
  )..addFont(Future.value(lucide))).load();
  // 图标字体：不装的话所有 Icon 都是方块。优先用应用资源里的 MaterialIcons，
  // 找不到再退回本机 Flutter SDK 的缓存路径（各平台/版本路径不同）。
  var loadedIcons = false;
  try {
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
    loadedIcons = true;
  } on Object {
    loadedIcons = false;
  }
  if (!loadedIcons) {
    const macIconPath =
        '/opt/homebrew/Caskroom/flutter/3.47.5/flutter/bin/cache/'
        'artifacts/material_fonts/MaterialIcons-Regular.otf';
    for (final path in <String>[
      macIconPath,
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ]) {
      final icons = File(path);
      if (!icons.existsSync()) continue;
      final bytes = await icons.readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
      loadedIcons = true;
      break;
    }
  }
}
