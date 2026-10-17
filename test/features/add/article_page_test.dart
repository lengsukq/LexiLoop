/// 粘贴文章页的 widget 测试。
///
/// 钉住的性质：粘贴 → 分析 → 预览 → 勾选 → 提交这条状态机走得通、
/// **AI 回退原因显示在界面上**（而不是静默变成「没选中任何词」）、
/// 未配置 AI 时给出配置引导、没有勾选时提交按钮不可用、分段分析完成后
/// 自动合并出可提交的预览。
///
/// 服务用子类顶替，**不发真实网络请求、不碰 LLM**。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/article_import/article_ai_models.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/add/article_page.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/services/article_import/article_ai_selector.dart';
import 'package:lexiloop/services/article_import/article_import_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 假服务的依赖包。
class _FakeDeps {
  const new(this.db, this.settings, this.words, this.selector);

  final AppDatabase db;
  final SettingsService settings;
  final WordEditService words;
  final ArticleAiSelector selector;
}

/// 用不到的真实选词器：服务方法全部被覆盖，它不会被调用。
class _UnusedSelector implements ArticleAiSelector {
  @override
  Future<ArticleAiSelection> select(ArticleAiSelectInput input) async =>
      ArticleAiSelection.none;
}

/// 顶替全部服务方法。
class _FakeArticleService extends ArticleImportService {
  new(
    _FakeDeps deps, {
    this.previewResult,
    this.previewError,
    this.commitResult,
    this.commitError,
    this.mergeResult,
    this.segmentOutcomes = const <ArticleSegmentOutcome>[],
  }) : super(deps.db, deps.settings, deps.words, deps.selector);

  final ArticleImportPreview? previewResult;
  final AppError? previewError;
  final ArticleCommitResult? commitResult;
  final AppError? commitError;
  final ArticleImportPreview? mergeResult;
  final List<ArticleSegmentOutcome> segmentOutcomes;

  /// 最近一次提交的勾选键与模式。
  Set<String>? lastSelectedKeys;
  ImportMode? lastMode;

  /// 最近一次提交是否勾选了「重置已有词条的学习进度」。
  bool? lastResetLearningProgress;

  /// 预览调用次数。
  int previewCalls = 0;

  @override
  Future<ArticleImportPreview> preview({
    required String articleText,
    required int now,
    String sourceLanguage = 'en',
    String targetLanguage = 'zh-CN',
    List<VocabularyLevel>? examTargets,
  }) async {
    previewCalls += 1;
    final error = previewError;
    if (error != null) throw error;
    return previewResult!;
  }

  @override
  Stream<ArticleSegmentOutcome> previewSegments({
    required String articleText,
    required int segmentsPerBatch,
    required int now,
    List<VocabularyLevel>? examTargets,
  }) async* {
    for (final outcome in segmentOutcomes) {
      yield outcome;
    }
  }

  @override
  Future<ArticleImportPreview> mergePreviews({
    required List<String> tokens,
    required int now,
  }) async {
    final result = mergeResult;
    if (result == null) {
      throw const ValidationError(
        AppErrorCode.importPreviewExpired,
        details: '段落预览已过期或不存在',
      );
    }
    return result;
  }

  @override
  Future<ArticleCommitResult> commit({
    required String previewToken,
    required Set<String> selectedKeys,
    required ImportMode mode,
    required int now,
    bool resetLearningProgress = false,
  }) async {
    lastSelectedKeys = selectedKeys;
    lastMode = mode;
    lastResetLearningProgress = resetLearningProgress;
    final error = commitError;
    if (error != null) throw error;
    return commitResult!;
  }
}

ArticleCandidate candidate({
  String term = 'apple',
  LexicalContentType entryType = LexicalContentType.word,
  ArticleCandidateStatus status = ArticleCandidateStatus.candidate,
  int occurrences = 2,
  String? aiReason,
}) => ArticleCandidate(
  term: term,
  normalizedTerm: term.toLowerCase(),
  occurrences: occurrences,
  status: status,
  entryType: entryType,
  aiReason: aiReason,
);

ArticleImportPreview previewOf({
  String token = 'token-1',
  List<ArticleCandidate> candidates = const <ArticleCandidate>[],
  List<String> recommendedTerms = const <String>[],
  List<String> recommendedKeys = const <String>[],
  bool aiApplied = false,
  String? aiError,
}) => ArticleImportPreview(
  previewToken: token,
  filename: '文章 · 40 词 · 300 字符',
  sourceLanguage: 'en',
  targetLanguage: 'zh-CN',
  articleStats: ArticleStats(
    charCount: 300,
    wordCount: 40,
    uniqueCount: candidates.length,
    knownCount: candidates.where((item) => item.isKnown).length,
    unknownCount: candidates.where((item) => item.isCandidate).length,
    phraseCount: candidates
        .where((item) => item.entryType == LexicalContentType.phrase)
        .length,
    sentenceCount: candidates
        .where((item) => item.entryType == LexicalContentType.sentence)
        .length,
  ),
  candidates: candidates,
  recommendedTerms: recommendedTerms,
  recommendedKeys: recommendedKeys,
  aiApplied: aiApplied,
  aiError: aiError,
  totalCandidates: candidates.length,
  knownCount: candidates.where((item) => item.isKnown).length,
  expiresAt: DateTime(2026, 3, 1, 10, 30).millisecondsSinceEpoch,
);

/// 单段文章（不会触发分段入口）。
const String singleParagraphArticle =
    'The rapid advancement of artificial intelligence has profoundly reshaped '
    'how we acquire knowledge and how we retain it.';

/// 第一段（长度足够，不会被尾段合并）。
final String _paragraphOne = <String>[
  'The rapid advancement of artificial intelligence has profoundly reshaped',
  'how we acquire knowledge and how we retain it.',
].join(' ');

/// 第二段。
final String _paragraphTwo = <String>[
  'Contemporary cognitive science suggests that contextual learning yields',
  'durable retention for every diligent learner.',
].join(' ');

/// 两段文章（会触发分段入口）。
final String twoParagraphArticle = <String>[
  _paragraphOne,
  _paragraphTwo,
].join('\n\n');

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late _FakeDeps deps;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    deps = _FakeDeps(db, settings, WordEditService(db), _UnusedSelector());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpPage(
    WidgetTester tester,
    _FakeArticleService service,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // 复用同一份内存库：不覆盖的话 `databaseProvider` 会再开一个
          // `AppDatabase`，drift 会警告「同一个执行器被多个实例使用」。
          databaseProvider.overrideWithValue(db),
          articleImportServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(theme: LexiTheme.light, home: const ArticlePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 点击前先把目标滚进视口：整页是 `ListView`，候选列表与底部按钮
  /// 在默认视口外，直接 `tap` 会静默点空。
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> analyze(WidgetTester tester, {String? text}) async {
    await tester.enterText(
      find.byKey(const Key('articleText')),
      text ?? singleParagraphArticle,
    );
    await tester.pumpAndSettle();
    await tapKey(tester, 'articleAnalyze');
  }

  testWidgets('粘贴 → 分析 → 预览 → 提交 走完整条链路', (tester) async {
    final service = _FakeArticleService(
      deps,
      previewResult: previewOf(
        candidates: <ArticleCandidate>[
          candidate(aiReason: '学术词'),
          candidate(term: 'banana'),
        ],
        recommendedTerms: <String>['apple'],
        recommendedKeys: <String>['WORD\u0000apple'],
        aiApplied: true,
      ),
      commitResult: const ArticleCommitResult(
        createdWords: 2,
        existingWords: 0,
        queuedInitializations: 2,
      ),
    );
    await pumpPage(tester, service);

    await analyze(tester);

    expect(find.text('待学候选'), findsOneWidget);
    expect(find.text('AI 已筛选 · 推荐 1 词'), findsOneWidget);
    expect(find.textContaining('已选 1 / 2'), findsOneWidget);

    await tapKey(tester, 'articleCommit');

    expect(find.text('导入完成'), findsOneWidget);
    expect(find.textContaining('新增 2 个，识别已有 0 个，新增初始化任务 2 个'), findsOneWidget);
    expect(service.lastSelectedKeys, <String>{'word\u0000apple'});
    expect(service.lastMode, ImportMode.fillMissing);
  });

  testWidgets('「重置已有词条的学习进度」勾选后随提交一起送出', (tester) async {
    // 界面接线用例：开关真的渲染出来、真的被带进 commit 参数。
    // 它删的是不可恢复的学习历史，所以「渲染了但没生效」是不能接受的失败模式。
    final service = _FakeArticleService(
      deps,
      previewResult: previewOf(
        candidates: <ArticleCandidate>[candidate(aiReason: '学术词')],
        recommendedTerms: <String>['apple'],
        recommendedKeys: <String>['WORD\u0000apple'],
        aiApplied: true,
      ),
      commitResult: const ArticleCommitResult(
        createdWords: 1,
        existingWords: 0,
        queuedInitializations: 1,
      ),
    );
    await pumpPage(tester, service);
    await analyze(tester);

    expect(find.byKey(const Key('resetLearningProgress')), findsOneWidget);
    expect(find.text('重置已有词条的学习进度'), findsOneWidget);

    await tester.tap(find.byKey(const Key('resetLearningProgress')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'articleCommit');
    await tester.pumpAndSettle();

    // 勾上这个开关等于「删掉不可恢复的学习历史」，提交前必须再确认一次
    // （与 CSV 导入那条路径同一强度）。没点确认之前不能提交。
    expect(find.text('重置已有词条的学习进度？'), findsOneWidget);
    expect(service.lastResetLearningProgress, isNull);

    await tester.tap(find.text('重置并导入'));
    await tester.pumpAndSettle();

    expect(service.lastResetLearningProgress, isTrue);
  });

  testWidgets('AI 回退时把原因显示在界面上，候选仍然可用', (tester) async {
    final service = _FakeArticleService(
      deps,
      previewResult: previewOf(
        candidates: <ArticleCandidate>[
          candidate(),
          candidate(term: 'banana'),
        ],
        recommendedTerms: <String>['apple', 'banana'],
        recommendedKeys: <String>['WORD\u0000apple', 'WORD\u0000banana'],
        aiError: 'AI 未启用，请到设置页开启 AI。',
      ),
      commitResult: const ArticleCommitResult(
        createdWords: 2,
        existingWords: 0,
        queuedInitializations: 2,
      ),
    );
    await pumpPage(tester, service);

    await analyze(tester);

    expect(
      find.textContaining('AI 未启用，请到设置页开启 AI。 已回退为展示单词与本地切句'),
      findsOneWidget,
    );
    expect(find.text('未启用 AI · 展示单词与本地切句'), findsOneWidget);
    // 回退后仍然勾上了本地推荐词，提交按钮可用。
    expect(find.textContaining('已选 2 / 2'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('articleCommit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('未配置 AI 且没有报错时给出配置引导', (tester) async {
    final service = _FakeArticleService(
      deps,
      previewResult: previewOf(
        candidates: <ArticleCandidate>[candidate()],
        recommendedTerms: <String>['apple'],
        recommendedKeys: <String>['WORD\u0000apple'],
      ),
    );
    await pumpPage(tester, service);

    await analyze(tester);

    expect(find.textContaining('模型服务 → AI'), findsOneWidget);
    expect(find.text('未启用 AI · 展示单词与本地切句'), findsOneWidget);
  });

  testWidgets('分析失败时显示可操作的错误文案', (tester) async {
    final service = _FakeArticleService(
      deps,
      previewError: const ValidationError(
        AppErrorCode.validationError,
        details: '未能从文章中提取到有效单词',
      ),
    );
    await pumpPage(tester, service);

    await analyze(tester);

    expect(
      find.textContaining('这段文字不满足分析要求：至少 $minArticleChars 个字符'),
      findsOneWidget,
    );
    // 回到粘贴步骤，用户可以改完再试。
    expect(find.byKey(const Key('articleText')), findsOneWidget);
  });

  testWidgets('没有勾选任何词条时提交按钮不可用', (tester) async {
    final service = _FakeArticleService(
      deps,
      previewResult: previewOf(
        candidates: <ArticleCandidate>[candidate()],
        recommendedTerms: <String>['apple'],
        recommendedKeys: <String>['WORD\u0000apple'],
      ),
    );
    await pumpPage(tester, service);

    await analyze(tester);
    await tapKey(tester, 'articleClearSelection');

    expect(find.textContaining('已选 0 / 1'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('articleCommit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('提交失败时回到预览并显示原因', (tester) async {
    final service = _FakeArticleService(
      deps,
      previewResult: previewOf(
        candidates: <ArticleCandidate>[candidate()],
        recommendedTerms: <String>['apple'],
        recommendedKeys: <String>['WORD\u0000apple'],
      ),
      commitError: const ValidationError(
        AppErrorCode.importPreviewExpired,
        details: '预览已过期',
      ),
    );
    await pumpPage(tester, service);

    await analyze(tester);
    await tapKey(tester, 'articleCommit');

    expect(find.text('预览已过期，请重新分析这篇文章。'), findsOneWidget);
    expect(find.text('待学候选'), findsOneWidget);
  });

  testWidgets('分段分析：逐批展示进度，完成后自动合并出可提交的预览', (tester) async {
    final firstBatch = previewOf(
      token: 'token-a',
      candidates: <ArticleCandidate>[candidate()],
      recommendedTerms: <String>['apple'],
      recommendedKeys: <String>['WORD\u0000apple'],
    );
    final secondBatch = previewOf(
      token: 'token-b',
      candidates: <ArticleCandidate>[candidate(term: 'banana')],
      recommendedTerms: <String>['banana'],
      recommendedKeys: <String>['WORD\u0000banana'],
    );
    final merged = previewOf(
      token: 'token-merged',
      candidates: <ArticleCandidate>[
        candidate(),
        candidate(term: 'banana'),
      ],
      recommendedTerms: <String>['apple', 'banana'],
      recommendedKeys: <String>['WORD\u0000apple', 'WORD\u0000banana'],
    );
    final service = _FakeArticleService(
      deps,
      mergeResult: merged,
      segmentOutcomes: <ArticleSegmentOutcome>[
        ArticleSegmentOutcome.success(batchIndex: 0, preview: firstBatch),
        ArticleSegmentOutcome.success(batchIndex: 1, preview: secondBatch),
      ],
      commitResult: const ArticleCommitResult(
        createdWords: 2,
        existingWords: 0,
        queuedInitializations: 2,
      ),
    );
    await pumpPage(tester, service);

    await tester.enterText(
      find.byKey(const Key('articleText')),
      twoParagraphArticle,
    );
    await tester.pumpAndSettle();
    expect(find.text('智能分段预览'), findsOneWidget);

    await tapKey(tester, 'articleAnalyzeSegmented');

    // 合并结果进入预览步骤，两个批次都成功。
    expect(find.textContaining('共 2 段分 2 批'), findsOneWidget);
    expect(find.byKey(const Key('articleBatchRow0')), findsOneWidget);
    expect(find.textContaining('2/2 段完成'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('articleCommit')))
          .onPressed,
      isNotNull,
    );
  });
}
