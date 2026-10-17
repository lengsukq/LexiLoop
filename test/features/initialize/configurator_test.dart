/// 初始化配置器的测试。
///
/// **为什么这组用例非写不可**：`EnqueueRequest.requestedFields` /
/// `requestedProviders` / `providerStrategy` 与 `InitializationQueries.enqueueBulk`
/// 早已实现且有测试，但**没有任何界面调用它们**——在配置器出现之前，
/// 用户根本无从指定「补哪些字段、走哪些数据源、覆盖还是只填空」。
/// 这里同时钉住草稿状态机与最终发出的请求，避免又出现
/// 「代码写好了但没人调」。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_controls.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_fields.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_providers.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/configurator/initialization_configurator.dart';

import '../../support/app_harness.dart';

void main() {
  late AppDatabase db;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord(
    String term, {
    bool isSuspended = false,
    // 默认「尚未初始化」：SKIP_INITIALIZED 模式会跳过已完成的词条，
    // 用 READY 当默认会让「入队」类用例全部空跑。
    InitializationStatus status = InitializationStatus.pending,
  }) => db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: term,
          normalizedTerm: term.toLowerCase(),
          sourceLanguage: 'en',
          targetLanguage: 'zh-CN',
          entryType: EntryType.word,
          isSuspended: Value<bool>(isSuspended),
          initializationStatus: Value<InitializationStatus>(status),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// 打开一个隔离的配置器作用域。
  ///
  /// 对话框本身也是这么做的——草稿是一次性的，不能留在全局容器里被
  /// 上一次的字段与范围污染。
  Future<ProviderContainer> openConfigurator([
    ConfiguratorScope scope = ConfiguratorScope.all,
  ]) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        configuratorProvider.overrideWith(() => ConfiguratorNotifier(scope)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(configuratorProvider, (_, _) {});
    // 数据源选项来自异步读到的设置，草稿据此推导可选来源。
    // 不等它就操作，等于在「还没任何来源」的状态下断言。
    await container.read(configuratorProviderOptionsProvider.future);
    return container;
  }

  /// 按展示名取预设——预设是数据（列表），不是枚举。
  ConfiguratorPreset presetByLabel(String label) =>
      configuratorPresets.firstWhere((preset) => preset.label == label);

  ConfiguratorState draftOf(ProviderContainer container) =>
      container.read<ConfiguratorState>(configuratorProvider);

  ConfiguratorNotifier notifierOf(ProviderContainer container) =>
      container.read<ConfiguratorNotifier>(configuratorProvider.notifier);

  group('草稿状态机', () {
    test('预设一键填充字段，且「仅补音标」不是全选', () async {
      final container = await openConfigurator();

      notifierOf(container).applyPreset(presetByLabel('仅补音标'));
      final phonetic = draftOf(container).draft;
      expect(phonetic.fields, contains(phoneticField));
      expect(
        phonetic.fields.length,
        lessThan(allConfiguratorFields.length),
        reason: '「仅补音标」不该把所有字段都勾上',
      );

      notifierOf(container).applyPreset(presetByLabel('完整初始化'));
      expect(
        draftOf(container).draft.fields,
        containsAll(allConfiguratorFields),
      );
    });

    test('「有道词典」预设锁死来源，解锁后恢复可选', () async {
      final container = await openConfigurator();
      notifierOf(container).applyPreset(presetByLabel('有道词典'));

      final locked = draftOf(container).draft;
      expect(locked.youdaoOnly, isTrue);
      expect(locked.providers, <String>[youdaoProviderId]);
      // 锁死时策略没有意义（旧版会让两个可点却不生效的控件误导用户）。
      expect(locked.strategy, ProviderStrategy.priorityFallback);

      notifierOf(container).unlockSources();
      final unlocked = draftOf(container).draft;
      expect(unlocked.youdaoOnly, isFalse);
      expect(unlocked.providers.length, greaterThan(1));
    });

    test('数据源优先级可以上下移动', () async {
      final container = await openConfigurator();
      notifierOf(container).applyPreset(presetByLabel('完整初始化'));
      final before = draftOf(container).draft.providers;
      expect(before.length, greaterThan(1));

      notifierOf(container).moveProvider(before.first, 1);
      final after = draftOf(container).draft.providers;
      expect(after.first, before[1]);
      expect(after[1], before.first);
    });

    test('字段一个都不选时拒绝创建', () async {
      final container = await openConfigurator();
      notifierOf(container).applyPreset(presetByLabel('仅补音标'));
      draftOf(container).draft.fields
          .toList()
          .forEach(notifierOf(container).toggleField);

      expect(
        await notifierOf(container).create(overwriteConfirmed: false),
        isFalse,
      );
      expect(await db.select(db.initializationJobs).get(), isEmpty);
      expect(draftOf(container).messageIsError, isTrue);
    });
  });

  group('创建任务', () {
    test('按草稿发出正确的 EnqueueRequest', () async {
      await insertWord('alpha');
      await insertWord('beta');
      final container = await openConfigurator();

      notifierOf(container).applyPreset(presetByLabel('仅补音标'));
      notifierOf(container).setStrategy(ProviderStrategy.parallelMerge);

      expect(
        await notifierOf(container).create(overwriteConfirmed: false),
        isTrue,
      );

      final jobs = await db.select(db.initializationJobs).get();
      expect(jobs, hasLength(2));
      for (final job in jobs) {
        expect(job.mode, InitializationMode.fillMissingFields);
        expect(job.providerStrategy, ProviderStrategy.parallelMerge);
        expect(job.priority, jobPriorityManualBulk);
        expect(job.requestedFieldsJson, isNotNull);
        expect(job.requestedProvidersJson, isNotNull);
        expect(job.status, InitializationStatus.queued);
      }
    });

    test('「只填空」跳过已满足所选字段的词条', () async {
      final wordId = await insertWord('ready');
      await db
          .into(db.wordContents)
          .insert(
            WordContentsCompanion.insert(
              wordId: Value<int>(wordId),
              pronunciationsJson: Value<String>(
                jsonEncode(<Object?>[
                  <String, Object?>{
                    'accent': 'US',
                    'phonetic': 'ˈredi',
                    'language': 'en',
                  },
                ]),
              ),
              updatedAt: now,
            ),
          );
      final container = await openConfigurator();

      // 跳过判定是**字段级**的：只要所选字段已经齐了就不必再跑一次，
      // 而不是看 `initialization_status`。
      notifierOf(container).applyPreset(presetByLabel('仅补音标'));
      notifierOf(container).setMode(InitializationMode.fillMissingFields);

      final preview = await container.read(configuratorPreviewProvider.future);
      expect(preview.satisfiedWords, 1);

      await notifierOf(container).create(overwriteConfirmed: false);
      expect(await db.select(db.initializationJobs).get(), isEmpty);
    });

    test('覆盖模式必须二次确认', () async {
      await insertWord('ready', status: InitializationStatus.ready);
      final container = await openConfigurator();

      notifierOf(container).applyPreset(presetByLabel('完整初始化'));
      notifierOf(container).setMode(InitializationMode.forceOverwrite);

      expect(
        await notifierOf(container).create(overwriteConfirmed: false),
        isFalse,
      );
      expect(await db.select(db.initializationJobs).get(), isEmpty);

      expect(
        await notifierOf(container).create(overwriteConfirmed: true),
        isTrue,
      );
      expect(await db.select(db.initializationJobs).get(), hasLength(1));
    });

    test('暂停的词条不入队', () async {
      final alive = await insertWord('alive');
      final paused = await insertWord('paused', isSuspended: true);
      final container = await openConfigurator();

      notifierOf(container).applyPreset(presetByLabel('仅补音标'));
      await notifierOf(container).create(overwriteConfirmed: false);

      final jobs = await db.select(db.initializationJobs).get();
      expect(jobs.map((job) => job.wordId), <int>[alive]);
      expect(jobs.single.wordId, isNot(paused));
    });

    test('重复入队被部分唯一索引挡下而不是产生两条任务', () async {
      await insertWord('alpha');
      final container = await openConfigurator();

      notifierOf(container).applyPreset(presetByLabel('仅补音标'));
      await notifierOf(container).create(overwriteConfirmed: false);
      await notifierOf(container).create(overwriteConfirmed: false);

      expect(await db.select(db.initializationJobs).get(), hasLength(1));
    });
  });

  testWidgets('对话框能打开、渲染完整且不溢出', (tester) async {
    await insertWord('alpha');
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapWithScope(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInitializationConfigurator(
                context,
                initialScope: ConfiguratorScope.all,
              ),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: [databaseProvider.overrideWithValue(db)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(InitializationConfigurator), findsOneWidget);
    expect(find.text('创建任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('细节默认收起，且收起时仍能看到当前选择', (tester) async {
    await insertWord('alpha');
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapWithScope(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInitializationConfigurator(
                context,
                initialScope: ConfiguratorScope.all,
              ),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: [databaseProvider.overrideWithValue(db)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 三块细节默认收起：配置器打开时只有「预设 + 一行摘要」，
    // 而不是 16 个字段和 6 个数据源全铺在眼前。
    expect(find.byType(ConfiguratorDisclosure), findsNWidgets(3));
    // 收起时**内容没有被构建**：字段网格里的「例句」不该在树上。
    expect(find.text('例句'), findsNothing);
    // 但收起不等于隐藏：摘要行仍然说明当前选了什么。
    expect(find.text('全部词条'), findsWidgets);
    expect(find.text('1 个字段'), findsOneWidget);
    expect(find.text('3 个来源 · 按顺序尝试'), findsOneWidget);

    // 展开「要补全的字段」后字段网格才出现。
    await tester.tap(find.text('要补全的字段'));
    await tester.pumpAndSettle();
    expect(find.text('例句'), findsOneWidget);
    expect(find.byType(ConfiguratorDisclosure), findsNWidgets(3));
  });
}

/// 取出某个词形的 ID，用于断言「暂停的词条没有混进来」。
Future<int> insertWordIdOf(String term) async =>
    throw StateError('not used — 词条 ID 由 [insertWord] 的返回值给出');
