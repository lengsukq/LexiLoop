/// 播放设置分组里「优先使用词典真人发音」开关的测试。
///
/// 钉的是「开关 → `settings` 表 → `AppSettings.playback.humanAudioEnabled`」
/// 这条完整链路。它是**相对旧版新增的开关**（旧版设置页没有这一项），
/// 链路两端分属不同文件（界面在 `features/settings`，消费方在
/// `services/audio/word_speaker.dart` 的运行时字段），任何一处漏接都会
/// 变成「开关能拨、实际仍在上网取 mp3」这种看不出来的故障。
///
/// 数据模型（`domain/models/app_settings.dart`）已冻结且已就绪，所以这里
/// 只断言往返不丢键，不重复测它的解析实现。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/playback_section.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 真人录音开关本身的 Key（与 `playback_section.dart` 保持一致）。
const Key humanAudioSwitchKey = Key('playbackHumanAudio');

/// 跟随 [appSettingsProvider] 重建的播放设置分组。
///
/// 必须真的 watch 设置：直接把 `AppSettings.defaults` 传进去会让这块子树
/// 变成常量控件，写库后永远不重建，回显断言就成了摆设。
class _PlaybackWatch extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(appSettingsProvider)
      .when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => Text('加载失败：$error'),
        data: (settings) => PlaybackSection(settings: settings),
      );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
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
          home: const Scaffold(body: _PlaybackWatch()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// `settings` 表里某个键的原始值（未经类型化解析）。
  Future<Object?> storedValue(String key) async {
    final rows = await db.select(db.settings).get();
    for (final row in rows) {
      if (row.key == key) return jsonDecode(row.valueJson);
    }
    return null;
  }

  Switch humanAudioSwitch(WidgetTester tester) =>
      tester.widget<Switch>(find.byKey(humanAudioSwitchKey));

  /// 点击开关并等到该键在表里变成 [expected]。
  ///
  /// 只 `pumpAndSettle` 不够：`saveSettings` 是一次真实的异步写库，写完才让
  /// `appSettingsProvider` 重建。这里轮询到预期值出现为止，避免把「还没写完」
  /// 误报成「没生效」。
  Future<void> toggleUntilStored(WidgetTester tester, Object? expected) async {
    await tester.tap(find.byKey(humanAudioSwitchKey));
    for (var i = 0; i < 20; i += 1) {
      await tester.pumpAndSettle();
      if (await storedValue('humanAudioEnabled') == expected) return;
    }
  }

  group('真人录音开关', () {
    testWidgets('默认开启，且表里没有该键时走默认值', (tester) async {
      await pumpSection(tester);

      expect(humanAudioSwitch(tester).value, isTrue);
      expect(
        await storedValue('humanAudioEnabled'),
        isNull,
        reason: '用户没拨过开关就不该往表里写一行',
      );
      expect(
        PlaybackSettings.defaults.humanAudioEnabled,
        isTrue,
        reason: '默认值必须是 true——真人录音是明确的音质提升',
      );
    });

    testWidgets('标题与说明写清代价与收益', (tester) async {
      await pumpSection(tester);

      expect(find.text('优先使用词典真人发音'), findsOneWidget);
      expect(
        find.textContaining('音质明显好于系统合成音'),
        findsOneWidget,
        reason: '收益：真人录音的音质',
      );
      expect(
        find.textContaining('自动回落系统朗读'),
        findsOneWidget,
        reason: '开启时的兜底：站点不可用自动回落系统朗读',
      );
      expect(
        find.textContaining('完全不联网'),
        findsOneWidget,
        reason: '代价：关闭后不再联网取 mp3',
      );
    });

    testWidgets('关掉后表里写入 false，再打开写回 true', (tester) async {
      await pumpSection(tester);

      await toggleUntilStored(tester, false);
      expect(await storedValue('humanAudioEnabled'), isFalse);
      // 界面回显：开关本身与设置值必须一致。
      expect(humanAudioSwitch(tester).value, isFalse);
      // 绕开 SettingsService 的内存缓存，证明值真的落到了表里。
      final reloaded = await SettingsService(SettingsDao(db)).load();
      expect(reloaded.playback.humanAudioEnabled, isFalse);

      await toggleUntilStored(tester, true);
      expect(await storedValue('humanAudioEnabled'), isTrue);
      expect(humanAudioSwitch(tester).value, isTrue);
    });
  });

  group('AppSettings 往返', () {
    test('解析 → 序列化不丢 humanAudioEnabled', () {
      final off = appSettingsFromRaw(<String, Object?>{
        'humanAudioEnabled': false,
      });
      expect(off.playback.humanAudioEnabled, isFalse);
      expect(off.toStorage()['humanAudioEnabled'], isFalse);

      // 完整往返：解析 → 写回 → 再解析，仍是同一个值。
      expect(
        appSettingsFromRaw(off.toStorage()).playback.humanAudioEnabled,
        isFalse,
      );
    });

    test('缺键时取默认值 true，且写回时带上该键', () {
      final settings = appSettingsFromRaw(const <String, Object?>{});

      expect(settings.playback.humanAudioEnabled, isTrue);
      expect(settings.toStorage()['humanAudioEnabled'], isTrue);
    });
  });
}
