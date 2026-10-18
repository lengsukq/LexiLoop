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
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/configurator/initialization_configurator.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_providers.dart';
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
  );
}

/// 加载本机字体，截图不需要网络资源。
Future<void> loadScreenshotFonts() async {
  // 装一份带中文的真字体，否则文字全是方块。注册多个常见族名，
  // 覆盖主题在 `null` 之外可能请求的名字。
  const cjkPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  final cjk = File(cjkPath);
  if (cjk.existsSync()) {
    final bytes = await cjk.readAsBytes();
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
      '.SF UI Text',
      '.AppleSystemUIFont',
      '.SF Pro Text',
      '.SF Pro Display',
    ]) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  final lucide = await rootBundle.load(
    'packages/lucide_icons_flutter/assets/lucide.ttf',
  );
  await (FontLoader(
    'packages/lucide_icons_flutter/Lucide',
  )..addFont(Future.value(lucide))).load();
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
}
