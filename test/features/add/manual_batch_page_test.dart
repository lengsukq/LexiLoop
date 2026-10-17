/// 添加页「词典批量预览」的 widget 测试。
///
/// 钉住的性质：两条路径的入口都在且默认停在离线手填、三条上限各自给出
/// 对应文案、逐行状态与失败原因分开显示（单行失败不影响其他行）、
/// 已确认的行不可重复确认、「全部确认」一次提交所有待确认行、快捷填入会
/// 重置已有结果。
///
/// 服务用子类顶替，**不发真实网络请求**。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/add/add_page.dart';
import 'package:lexiloop/features/add/manual_batch_providers.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/manual_preview_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 假服务的依赖包。
///
/// 打包成一个对象而不是多个位置参数：`ManualPreviewService` 的构造参数是
/// 私有字段形参，无法用 `super.db` 转发，直接转发会触发
/// `use_super_parameters`。
class _FakeDeps {
  const new(this.db, this.settings);

  final AppDatabase db;
  final SettingsService settings;
}

/// 用不到的假词典：服务方法全部被覆盖，它不会被调用。
Future<DictionaryLookupResult> _unusedLookup({
  required AppSettings settings,
  required ProviderRequest request,
  required List<String> selectedProviders,
  required ProviderStrategy strategy,
}) async => DictionaryLookupResult(
  content: emptyDictionaryContent(),
  attempts: const <ProviderAttemptRecord>[],
  hasTransientFailure: false,
  contentSource: ContentSource.dictionaryOnly,
);

/// 顶替预览与确认的服务。
class _FakeManualPreviewService extends ManualPreviewService {
  new(_FakeDeps deps, {this.failTerms = const <String>{}})
    : super(deps.db, deps.settings, _unusedLookup, WordEditService(deps.db));

  /// 这些词条的预览会失败。
  final Set<String> failTerms;

  /// 已确认的令牌（按顺序）。
  final List<String> confirmedTokens = <String>[];

  @override
  Future<ManualPreview> createPreview({
    required String text,
    required String sourceLanguage,
    required String sourceLanguageName,
    required String targetLanguage,
    required String targetLanguageName,
    required int now,
    LexicalContentType? contentType,
  }) async {
    if (failTerms.contains(text)) {
      throw const ExternalServiceError(
        AppErrorCode.requestedFieldsEmpty,
        details: '词典没有返回可用释义，请调整输入或稍后重试。',
      );
    }
    return ManualPreview(
      previewToken: 'token-$text',
      term: text,
      normalizedTerm: text.toLowerCase(),
      sourceLanguage: sourceLanguage,
      sourceLanguageName: sourceLanguageName,
      targetLanguage: targetLanguage,
      targetLanguageName: targetLanguageName,
      contentType: contentType ?? LexicalContentType.word,
      content: DictionaryContent(<String, Object?>{
        'summary': <String, Object?>{'translation': '译文 $text'},
        'definitions': <Object?>[
          <String, Object?>{'language': 'zh-CN', 'text': '释义 $text'},
        ],
        'examples': <Object?>[
          <String, Object?>{'sentence': 'A sentence for $text.'},
        ],
      }),
      providerAttempts: const <ProviderAttemptRecord>[],
      existingWordId: null,
      expiresAt: now + importPreviewTtlMs,
    );
  }

  @override
  Future<ManualPreviewCommit> confirmPreview({
    required String previewToken,
    required int now,
  }) async {
    confirmedTokens.add(previewToken);
    return ManualPreviewCommit(
      wordId: 100 + confirmedTokens.length,
      created: true,
      idempotent: false,
      initializationStatus: InitializationStatus.ready,
      contentType: LexicalContentType.word,
    );
  }
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

  _FakeDeps deps() => _FakeDeps(db, settings);

  Future<void> pumpPage(
    WidgetTester tester,
    ManualPreviewService service,
  ) async {
    // 添加页是一整列卡片：把画布调高，避免「控件在屏幕外点不到」
    // 把测试失败误报成界面缺陷。
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          manualPreviewServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          // 真实应用里 AddPage 挂在 AdaptiveShell 下，那里有 Material；
          // 测试里补一层 Scaffold，否则 TextField 会因为找不到 Material 祖先而报错。
          home: const Scaffold(body: AddPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 切到「词典批量预览」并填入文本。
  Future<void> fillBatch(WidgetTester tester, String text) async {
    await tester.tap(find.text('词典批量预览'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manualBatchText')), text);
    await tester.pumpAndSettle();
  }

  Future<void> tapPreview(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('manualBatchPreview')));
    await tester.pumpAndSettle();
  }

  String lines(int count, String prefix) =>
      <String>[for (var i = 0; i < count; i += 1) '$prefix$i'].join('\n');

  testWidgets('默认停在离线手填，分段切换可进入批量预览', (tester) async {
    await pumpPage(tester, _FakeManualPreviewService(deps()));

    // 离线路径是默认入口：不依赖网络，弱网下唯一能建词条的路。
    expect(find.text('手动填写'), findsOneWidget);
    expect(find.text('保存到词库'), findsOneWidget);
    expect(find.byKey(const Key('manualBatchText')), findsNothing);

    await tester.tap(find.text('词典批量预览'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manualBatchText')), findsOneWidget);
    expect(find.byKey(const Key('manualBatchPreview')), findsOneWidget);
    expect(find.text('保存到词库'), findsNothing);
  });

  group('上限', () {
    testWidgets('行数超限时报旧版文案', (tester) async {
      await pumpPage(tester, _FakeManualPreviewService(deps()));
      await fillBatch(tester, lines(manualBatchMaxRows + 1, 'w'));

      await tapPreview(tester);

      expect(find.byKey(const Key('manualBatchError')), findsOneWidget);
      expect(find.text('一次最多支持 100 行，请分多次添加。'), findsOneWidget);
      expect(find.byKey(const Key('manualBatchRow-0')), findsNothing);
    });

    testWidgets('单行超限时报旧版文案', (tester) async {
      await pumpPage(tester, _FakeManualPreviewService(deps()));
      await fillBatch(tester, 'a' * (manualBatchMaxCharsPerLine + 1));

      await tapPreview(tester);

      expect(find.textContaining('超过单行 1200 字符限制，请缩短后重试。'), findsOneWidget);
    });

    testWidgets('总长度超限时报错', (tester) async {
      await pumpPage(tester, _FakeManualPreviewService(deps()));
      await fillBatch(
        tester,
        <String>[for (var i = 0; i < 30; i += 1) 'a' * 900].join('\n'),
      );

      await tapPreview(tester);

      expect(find.text('一次最多支持 24000 字符，请分多次添加。'), findsOneWidget);
    });
  });

  group('逐行结果', () {
    testWidgets('成功行显示译文，失败行显示失败原因且不影响其他行', (tester) async {
      await pumpPage(
        tester,
        _FakeManualPreviewService(deps(), failTerms: <String>{'bad'}),
      );
      await fillBatch(tester, 'good-one\nbad\ngood-two');

      await tapPreview(tester);

      expect(find.text('译文 good-one'), findsOneWidget);
      expect(find.text('译文 good-two'), findsOneWidget);
      expect(find.textContaining('词典没有返回可用释义'), findsOneWidget);
      // 失败行没有确认按钮，成功行都有。
      expect(find.byKey(const Key('manualBatchConfirm-1')), findsNothing);
      expect(find.byKey(const Key('manualBatchConfirm-0')), findsOneWidget);
      expect(find.byKey(const Key('manualBatchConfirm-2')), findsOneWidget);
    });

    testWidgets('展开详情渲染释义与例句', (tester) async {
      await pumpPage(tester, _FakeManualPreviewService(deps()));
      await fillBatch(tester, 'good-one\ngood-two');

      await tapPreview(tester);
      await tester.tap(find.byKey(const Key('manualBatchToggle-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manualBatchDetail')), findsOneWidget);
      expect(find.text('释义 good-one'), findsOneWidget);
      expect(find.text('A sentence for good-one.'), findsOneWidget);
      expect(find.textContaining('英语 → 简体中文'), findsOneWidget);
    });

    testWidgets('已确认的行显示词条 ID 且不可重复确认', (tester) async {
      final service = _FakeManualPreviewService(deps());
      await pumpPage(tester, service);
      await fillBatch(tester, 'good-one');
      await tapPreview(tester);

      await tester.tap(find.byKey(const Key('manualBatchConfirm-0')));
      await tester.pumpAndSettle();

      expect(find.text('词条 ID：101'), findsOneWidget);
      expect(find.byKey(const Key('manualBatchConfirm-0')), findsNothing);
      expect(service.confirmedTokens, <String>['token-good-one']);
    });

    testWidgets('「全部确认」提交所有待确认行', (tester) async {
      final service = _FakeManualPreviewService(deps());
      await pumpPage(tester, service);
      await fillBatch(tester, 'good-one\ngood-two\ngood-three');
      await tapPreview(tester);

      expect(find.text('全部确认加入（3）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('manualBatchConfirmAll')));
      await tester.pumpAndSettle();

      // 批量写库是零撤销的，必须先过一道确认：没点之前一行都不写。
      expect(find.text('全部确认加入？'), findsOneWidget);
      expect(service.confirmedTokens, isEmpty);

      await tester.tap(find.text('写入词库'));
      await tester.pumpAndSettle();

      expect(service.confirmedTokens, hasLength(3));
      expect(find.byKey(const Key('manualBatchAllConfirmed')), findsOneWidget);
      expect(find.text('已全部加入词库'), findsOneWidget);

      // 「继续添加」清空结果，回到空文本域。
      await tester.tap(find.byKey(const Key('manualBatchReset')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manualBatchAllConfirmed')), findsNothing);
      final field = tester.widget<TextField>(
        find.byKey(const Key('manualBatchText')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('失败的预览行不参与「全部确认」的计数', (tester) async {
      await pumpPage(
        tester,
        _FakeManualPreviewService(deps(), failTerms: <String>{'bad'}),
      );
      await fillBatch(tester, 'good-one\nbad');
      await tapPreview(tester);

      expect(find.text('全部确认加入（1）'), findsOneWidget);
    });
  });

  group('快捷填入', () {
    testWidgets('三个示例各自填入对应文本', (tester) async {
      await pumpPage(tester, _FakeManualPreviewService(deps()));
      await tester.tap(find.text('词典批量预览'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manualBatchQuickWord')));
      await tester.pumpAndSettle();
      TextField field() =>
          tester.widget<TextField>(find.byKey(const Key('manualBatchText')));
      expect(field().controller!.text, 'serendipity\nresilient\nmeticulous');

      await tester.tap(find.byKey(const Key('manualBatchQuickSentence')));
      await tester.pumpAndSettle();
      expect(
        field().controller!.text,
        'Practice makes perfect.\nAction speaks louder than words.',
      );
    });

    testWidgets('已有预览结果时快捷填入会一并重置', (tester) async {
      await pumpPage(tester, _FakeManualPreviewService(deps()));
      await fillBatch(tester, 'good-one');
      await tapPreview(tester);
      expect(find.byKey(const Key('manualBatchRow-0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('manualBatchQuickPhrase')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manualBatchRow-0')), findsNothing);
      final field = tester.widget<TextField>(
        find.byKey(const Key('manualBatchText')),
      );
      expect(field.controller!.text, 'bring up\ntake for granted\ncome across');
    });
  });

  testWidgets('⌘/Ctrl + Enter 触发预览', (tester) async {
    await pumpPage(tester, _FakeManualPreviewService(deps()));
    await fillBatch(tester, 'good-one');
    // enterText 之后焦点在文本域上，快捷键应当由 CallbackShortcuts 接住。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manualBatchRow-0')), findsOneWidget);
  });
}
