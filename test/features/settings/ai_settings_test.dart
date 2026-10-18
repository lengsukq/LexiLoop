/// 「AI 模型」设置分组的 widget 测试。
///
/// 覆盖这条迁移里最关键的一条链路：**LLM 配置只存在于
/// `AppSettings.raw['llmConfig']`，界面必须能把它读出来、改回去，
/// 并且在结构变更后不留下悬空引用。**
///
/// 全部联网动作经由 `httpFetcherProvider` 注入假客户端，测试完全离线。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/features/settings/settings_page.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../../data/dictionary/fake_http_fetcher.dart';

/// OpenAI 兼容的成功响应。
const String okChatBody = '{"choices":[{"message":{"content":"ok"}}]}';

/// 两个模型的 Models 接口响应。
const String twoModelsBody = '{"data":[{"id":"m1"},{"id":"m2"}]}';

/// 构造一个 provider 的存储形状。
Map<String, Object?> providerJson({
  required String id,
  String name = '',
  String baseUrl = 'https://a.example/v1',
  String apiKey = 'sk-test',
  List<String> models = const <String>[],
  String defaultModel = '',
  String apiType = 'openai',
}) => <String, Object?>{
  'id': id,
  'name': name,
  'apiType': apiType,
  'baseUrl': baseUrl,
  'apiKey': apiKey,
  'models': models,
  'defaultModel': defaultModel,
};

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  /// 假客户端的响应，由各用例改写；注入一次即可。
  var chatStatus = 200;
  var chatBody = okChatBody;
  var modelsStatus = 200;
  var modelsBody = twoModelsBody;
  late FakeHttpFetcher fetcher;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    chatStatus = 200;
    chatBody = okChatBody;
    modelsStatus = 200;
    modelsBody = twoModelsBody;
    fetcher = FakeHttpFetcher((url, body) async {
      if (url.endsWith('/models')) {
        return HttpFetchResponse(statusCode: modelsStatus, body: modelsBody);
      }
      return HttpFetchResponse(statusCode: chatStatus, body: chatBody);
    });
    fetcher.calls.clear();
    container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        httpFetcherProvider.overrideWithValue(fetcher),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  /// 写入一份 LLM 配置（模拟「恢复旧备份」把它带回来）。
  Future<void> seedLlm(
    Map<String, Object?> llmConfig, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) => container.read(settingsServiceProvider).update(<String, Object?>{
    llmConfigSettingsKey: llmConfig,
    ...extra,
  }, now: 0);

  Future<void> pumpSettings(WidgetTester tester) async {
    // 画布不够高会让卡片下半部分落到屏幕外，点不到。
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: LexiTheme.light, home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 模型'));
    await tester.pumpAndSettle();
    if (find.text('高级模型参数').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('高级模型参数'));
      await tester.tap(find.text('高级模型参数'));
      await tester.pumpAndSettle();
    }
  }

  /// 从 `appSettingsProvider` 解析出当前的 LLM 配置。
  Future<LlmConfig> currentConfig() async => llmConfigFromSettings(
    (await container.read(appSettingsProvider.future)).raw,
  );

  /// 某个区间数字框当前显示的文本（用来验证「显示的」与「写入的」一致）。
  /// 区间数字框本体：Key 挂在外层容器上，`enterText` 只认输入框本身。
  Finder numberField(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(TextField));

  /// 某个区间数字框当前显示的文本（验证「显示的」与「写入的」一致）。
  String fieldText(WidgetTester tester, Key key) =>
      tester.widget<TextField>(numberField(key)).controller!.text;

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('aiAddProvider')));
    await tester.pumpAndSettle();
  }

  Future<void> submitEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('aiProviderEditorSubmit')));
    await tester.pumpAndSettle();
  }

  /// 走一遍「新增一个可用 provider」的完整流程。
  Future<void> addProvider(
    WidgetTester tester, {
    String id = 'p1',
    String name = '',
  }) async {
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('aiProviderEditorId')), id);
    await tester.enterText(find.byKey(const Key('aiProviderEditorName')), name);
    await tester.enterText(
      find.byKey(const Key('aiProviderEditorBaseUrl')),
      'https://a.example/v1',
    );
    await tester.enterText(
      find.byKey(const Key('aiProviderEditorApiKey')),
      'k',
    );
    await submitEditor(tester);
  }

  group('Provider 增删改', () {
    testWidgets('新增的 provider 能从 appSettingsProvider 读回', (tester) async {
      await pumpSettings(tester);

      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('aiProviderEditorId')),
        'my-openai',
      );
      await tester.enterText(
        find.byKey(const Key('aiProviderEditorName')),
        '我的 OpenAI',
      );
      await tester.enterText(
        find.byKey(const Key('aiProviderEditorBaseUrl')),
        'https://api.example.com/v1/',
      );
      await tester.enterText(
        find.byKey(const Key('aiProviderEditorApiKey')),
        'k1',
      );
      // API Key 默认隐藏：设置页的截图可能被用户拿去提问。
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('aiProviderEditorApiKey')))
            .obscureText,
        isTrue,
      );
      await submitEditor(tester);

      final config = await currentConfig();
      expect(config.providers, hasLength(1));
      expect(config.providers.single.id, 'my-openai');
      expect(config.providers.single.apiKey, 'k1');
      // 尾部斜杠必须去掉，否则会拼出 `//chat/completions`。
      expect(config.providers.single.baseUrl, 'https://api.example.com/v1');
      expect(find.byKey(const Key('aiProviderCard-my-openai')), findsOneWidget);
      // 卡片上不出现明文 Key。
      expect(find.text('k1'), findsNothing);
    });

    testWidgets('重复 ID、空接口地址、空 API Key 都被拦下', (tester) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[providerJson(id: 'p1')],
      });
      await pumpSettings(tester);

      await openEditor(tester);
      final idField = find.byKey(const Key('aiProviderEditorId'));
      final urlField = find.byKey(const Key('aiProviderEditorBaseUrl'));
      final keyField = find.byKey(const Key('aiProviderEditorApiKey'));

      await tester.enterText(idField, 'p1');
      await tester.enterText(urlField, 'https://b.example/v1');
      await tester.enterText(keyField, 'k2');
      await submitEditor(tester);
      expect(find.byKey(const Key('aiProviderEditorError')), findsOneWidget);
      expect(find.textContaining('已被另一个 Provider 占用'), findsOneWidget);
      // 对话框不能关掉，更不能写入。
      expect((await currentConfig()).providers, hasLength(1));

      await tester.enterText(idField, '');
      await submitEditor(tester);
      expect(find.textContaining('ID 不能为空'), findsOneWidget);

      await tester.enterText(idField, 'p2');
      await tester.enterText(urlField, '');
      await submitEditor(tester);
      expect(find.textContaining('接口地址不能为空'), findsOneWidget);

      await tester.enterText(urlField, 'https://b.example/v1');
      await tester.enterText(keyField, '');
      await submitEditor(tester);
      expect(find.textContaining('API Key 不能为空'), findsOneWidget);
      expect((await currentConfig()).providers, hasLength(1));
    });

    testWidgets('删除主 provider 会清空 ai.providerId 并关闭总开关', (tester) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[
          providerJson(id: 'p1', models: <String>['m1'], defaultModel: 'm1'),
          providerJson(id: 'p2'),
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'm1',
        },
      });
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderRemove-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aiProviderRemoveConfirm')));
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.providers.map((item) => item.id), <String>['p2']);
      // 留下悬空引用会让 AI 永远不生效，且用户没有任何入口能修。
      expect(config.ai.providerId, isEmpty);
      expect(config.ai.enabled, isFalse);
      expect(find.byKey(const Key('aiProviderCard-p1')), findsNothing);
    });

    testWidgets('删除备用 provider 会清空 retryProviderId 与 retryModel', (
      tester,
    ) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[
          providerJson(id: 'p1', models: <String>['m1'], defaultModel: 'm1'),
          providerJson(id: 'p2', models: <String>['m2'], defaultModel: 'm2'),
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'm1',
          'retryProviderId': 'p2',
          'retryModel': 'm2',
        },
      });
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderRemove-p2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aiProviderRemoveConfirm')));
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.ai.retryProviderId, isEmpty);
      expect(config.ai.retryModel, isEmpty);
      // 主配置不受影响。
      expect(config.ai.providerId, 'p1');
      expect(config.ai.enabled, isTrue);
    });

    testWidgets('恢复备份带回来的配置可以直接编辑', (tester) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[
          providerJson(
            id: 'restored',
            name: '旧备份里的 Provider',
            models: <String>['old-model'],
            defaultModel: 'old-model',
          ),
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'restored',
          'model': 'old-model',
        },
      });
      await pumpSettings(tester);

      // 限定在卡片内找：provider 名同时出现在卡片标题与下拉框标签里。
      expect(
        find.descendant(
          of: find.byKey(const Key('aiProviderCard-restored')),
          matching: find.text('旧备份里的 Provider'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('aiProviderManageModels-restored')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modelPickerClear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modelPickerApply')));
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.providers.single.models, isEmpty);
      expect(config.providers.single.defaultModel, isEmpty);
      expect(config.ai.model, isEmpty);
    });
  });

  group('测试连接', () {
    Future<void> seedOneModel() => seedLlm(<String, Object?>{
      'providers': <Object?>[
        providerJson(id: 'p1', models: <String>['m1'], defaultModel: 'm1'),
      ],
    });

    testWidgets('成功时显示模型与耗时', (tester) async {
      await seedOneModel();
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderTest-p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('aiProviderTestResult-p1')), findsOneWidget);
      expect(find.textContaining('m1 响应正常'), findsOneWidget);
      expect(find.textContaining('ms'), findsOneWidget);
    });

    testWidgets('失败时显示原因且不崩溃', (tester) async {
      chatStatus = 401;
      chatBody = 'unauthorized';
      await seedOneModel();
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderTest-p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('aiProviderTestResult-p1')), findsOneWidget);
      expect(find.textContaining('请检查接口地址、API Key 与模型名'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('没有模型时提示先添加模型，不发请求', (tester) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[providerJson(id: 'p1')],
      });
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderTest-p1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('请先通过 Models 接口获取或添加一个模型'), findsOneWidget);
      expect(fetcher.calls, isEmpty);
    });
  });

  group('模型选择器', () {
    testWidgets('从 Models 接口获取后写回 models 与 defaultModel', (tester) async {
      await pumpSettings(tester);
      await addProvider(tester);

      await tester.tap(find.byKey(const Key('aiProviderFetchModels-p1')));
      await tester.pumpAndSettle();

      expect(finderOption('m1'), findsOneWidget);
      expect(finderOption('m2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('modelPickerApply')));
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.providers.single.models, <String>['m1', 'm2']);
      // 原本没有默认模型，取第一个。
      expect(config.providers.single.defaultModel, 'm1');
    });

    testWidgets('清空选择会删除全部模型并修好 ai.model', (tester) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[
          providerJson(id: 'p1', models: <String>['m1'], defaultModel: 'm1'),
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'm1',
        },
      });
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderManageModels-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modelPickerClear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modelPickerApply')));
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.providers.single.models, isEmpty);
      expect(config.providers.single.defaultModel, isEmpty);
      // ai.model 指向已不存在的模型会让每次调用都失败，必须一起修掉。
      expect(config.ai.model, isEmpty);
    });

    testWidgets('筛选只作用于筛选结果，全选新增也只加筛选结果', (tester) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[
          providerJson(
            id: 'p1',
            models: <String>['keep-me', 'other'],
            defaultModel: 'keep-me',
          ),
        ],
      });
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderManageModels-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modelPickerClear')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('modelPickerFilter')),
        'other',
      );
      await tester.pumpAndSettle();
      expect(finderOption('other'), findsOneWidget);
      expect(finderOption('keep-me'), findsNothing);

      await tester.tap(find.byKey(const Key('modelPickerSelectAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modelPickerApply')));
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.providers.single.models, <String>['other']);
      expect(config.providers.single.defaultModel, 'other');
    });

    testWidgets('接口失败时保留原有模型并给出原因', (tester) async {
      modelsStatus = 500;
      modelsBody = 'boom';
      await seedLlm(<String, Object?>{
        'providers': <Object?>[
          providerJson(id: 'p1', models: <String>['m1'], defaultModel: 'm1'),
        ],
      });
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderFetchModels-p1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('aiProviderModelsResult-p1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('modelPickerApply')), findsNothing);
      expect((await currentConfig()).providers.single.models, <String>['m1']);
    });
  });

  group('AI 参数', () {
    Future<void> seedEnabledAi() => seedLlm(
      <String, Object?>{
        'providers': <Object?>[
          providerJson(id: 'p1', models: <String>['m1'], defaultModel: 'm1'),
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'm1',
        },
      },
      // `aiRetryCount` 在设置顶层，不在 llmConfig 里（见 llm_config.dart）。
      extra: <String, Object?>{aiRetryCountSettingsKey: 3},
    );

    testWidgets('数值参数写回后与输入一致', (tester) async {
      await seedEnabledAi();
      await pumpSettings(tester);

      await tester.enterText(numberField(const Key('aiTemperature')), '0.7');
      await tester.pumpAndSettle();
      await tester.enterText(
        numberField(const Key('aiMaxOutputTokens')),
        '4096',
      );
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.ai.temperature, 0.7);
      expect(config.ai.maxOutputTokens, 4096);
      expect(fieldText(tester, const Key('aiTemperature')), '0.7');
    });

    testWidgets('越界的数值在输入时就被夹取', (tester) async {
      await seedEnabledAi();
      await pumpSettings(tester);

      // 超时按秒填：1 秒低于 `minLlmTimeoutMs`，必须夹到下限。
      await tester.enterText(numberField(const Key('aiTimeoutSeconds')), '1');
      await tester.pumpAndSettle();
      expect((await currentConfig()).ai.timeoutMs, minLlmTimeoutMs);
      expect(
        fieldText(tester, const Key('aiTimeoutSeconds')),
        '${minLlmTimeoutMs ~/ secondMs}',
      );

      await tester.enterText(
        numberField(const Key('aiMaxOutputTokens')),
        '99999999',
      );
      await tester.pumpAndSettle();
      expect((await currentConfig()).ai.maxOutputTokens, maxLlmMaxOutputTokens);
      expect(
        fieldText(tester, const Key('aiMaxOutputTokens')),
        '$maxLlmMaxOutputTokens',
      );

      await tester.enterText(numberField(const Key('aiTemperature')), '5');
      await tester.pumpAndSettle();
      expect((await currentConfig()).ai.temperature, maxLlmTemperature);
      expect(fieldText(tester, const Key('aiTemperature')), '1');
    });

    testWidgets('思考参数只在开启后出现并能写回', (tester) async {
      await seedEnabledAi();
      await pumpSettings(tester);

      expect(find.byKey(const Key('aiThinkingBudget')), findsNothing);
      await tester.tap(find.byKey(const Key('aiThinkingSwitch')));
      await tester.pumpAndSettle();
      expect((await currentConfig()).ai.thinkingEnabled, isTrue);

      await tester.enterText(numberField(const Key('aiThinkingBudget')), '10');
      await tester.pumpAndSettle();
      // 思考预算下限远高于用户输入，夹取必须发生在写入之前。
      expect(
        (await currentConfig()).ai.thinkingBudgetTokens,
        minThinkingBudgetTokens,
      );
      expect(
        fieldText(tester, const Key('aiThinkingBudget')),
        '$minThinkingBudgetTokens',
      );
    });

    testWidgets('写 AI 配置不会动顶层的 aiRetryCount', (tester) async {
      await seedEnabledAi();
      await pumpSettings(tester);

      await tester.enterText(numberField(const Key('aiTemperature')), '0.5');
      await tester.pumpAndSettle();

      final settings = await container.read(appSettingsProvider.future);
      expect(settings.raw[aiRetryCountSettingsKey], 3);
      expect((await currentConfig()).ai.retryCount, 3);
    });

    testWidgets('切换主 provider 会把模型收敛到新 provider 的默认模型', (tester) async {
      await seedLlm(<String, Object?>{
        'providers': <Object?>[
          providerJson(
            id: 'p1',
            name: '主用',
            models: <String>['m1'],
            defaultModel: 'm1',
          ),
          providerJson(
            id: 'p2',
            name: '备用网关',
            models: <String>['m2'],
            defaultModel: 'm2',
          ),
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'm1',
        },
      });
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiProviderSelect')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownMenuItem<String>, '备用网关'));
      await tester.pumpAndSettle();

      final config = await currentConfig();
      expect(config.ai.providerId, 'p2');
      expect(config.ai.model, 'm2');
    });

    testWidgets('关闭总开关会落库', (tester) async {
      await seedEnabledAi();
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('aiEnabledSwitch')));
      await tester.pumpAndSettle();

      expect((await currentConfig()).ai.enabled, isFalse);
    });
  });

  testWidgets('tab 可达且在窄屏下不溢出', (tester) async {
    const providerId = 'a-very-long-provider-identifier';
    await seedLlm(<String, Object?>{
      'providers': <Object?>[
        providerJson(
          id: providerId,
          name: '一个名字相当长的 Provider',
          models: <String>['a-very-long-model-name-for-testing'],
          defaultModel: 'a-very-long-model-name-for-testing',
        ),
      ],
      'ai': <String, Object?>{
        'enabled': true,
        'providerId': providerId,
        'model': 'a-very-long-model-name-for-testing',
        'thinkingEnabled': true,
      },
    });
    await pumpSettings(tester);

    expect(find.byKey(const Key('aiAddProvider')), findsOneWidget);
    expect(find.byKey(const Key('aiProviderCard-$providerId')), findsOneWidget);
    expect(find.byKey(const Key('aiTemperature')), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(420, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// 选择器里某个模型的选项。
Finder finderOption(String model) =>
    find.byKey(Key('modelPickerOption-$model'));
