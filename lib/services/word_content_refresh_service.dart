/// 有道词典内容的预览与应用。
///
/// 对应旧版 `src/modules/words/youdao-refresh.ts` 的
/// `previewYoudaoContent` 与 `applyYoudaoContent`。
///
/// **为什么单独成服务而不是塞进 `WordEditService`**：本服务要联网（走
/// 词典管线），而 `WordEditService` 是纯写库入口，测试里用内存库即可覆盖。
/// 把联网与写库分开，服务测试可以只替换 `DictionaryLookupService` 的
/// HTTP 客户端，不必让写库测试也背上网络依赖。
///
/// **与旧版的差异**：旧版 `previewYoudaoContent` 从服务端 `getSettings()`
/// 读设置；纯本地版由 [SettingsService] 提供，语义一致。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/youdao_fields.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/lookup_service.dart';
import 'package:lexiloop/services/dictionary/merge.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 一次词典抓取的抽象。
///
/// [DictionaryLookupService] 必须先注入 HTTP 客户端才能构造，而本服务的
/// 单元测试要断言的是「只查有道」「合并语义」「写库结果」，不该被某个
/// provider 的响应格式绑架。抽一个只有 `lookup` 的接口，测试里给一个
/// 返回预置结果、并记录调用参数的假实现即可（假词典，不发任何网络请求）。
abstract interface class WordLookup {
  /// 按设置执行一次查询。
  Future<DictionaryLookupResult> lookup({
    required AppSettings settings,
    required ProviderRequest request,
    required List<String> selectedProviders,
    required ProviderStrategy strategy,
  });
}

/// 把 [DictionaryLookupService] 适配成 [WordLookup]。
///
/// 适配器而不是让 [DictionaryLookupService] 直接实现接口：那个文件属于
/// 词典层，不该为了界面层的测试便利而多背一个接口。
class DictionaryLookupAdapter implements WordLookup {
  /// 以词典查询服务构造。
  const new(this._service);

  final DictionaryLookupService _service;

  @override
  Future<DictionaryLookupResult> lookup({
    required AppSettings settings,
    required ProviderRequest request,
    required List<String> selectedProviders,
    required ProviderStrategy strategy,
  }) => _service.lookup(
    settings: settings,
    request: request,
    selectedProviders: selectedProviders,
    strategy: strategy,
  );
}

/// 有道预览结果。
///
/// 对应旧版 `YoudaoPreviewResult`。`hasContent` 决定弹窗是展示内容分区
/// 还是「没有有效内容 + 各次尝试的错误说明」。
class YoudaoPreviewResult {
  /// 以各字段构造。
  const new({
    required this.content,
    required this.attempts,
    required this.hasContent,
  });

  /// 抓取到的内容（**尚未写库**）。
  final DictionaryContent content;

  /// 各数据源的调用记录。
  final List<ProviderAttemptRecord> attempts;

  /// 是否抓到了任何可用内容。
  final bool hasContent;
}

/// 有道内容的预览与应用服务。
class WordContentRefreshService {
  /// 以数据库、设置、词典查询与写库服务构造。
  const new(this._db, this._settings, this._dictionary, this._edit);

  final AppDatabase _db;
  final SettingsService _settings;
  final WordLookup _dictionary;
  final WordEditService _edit;

  /// 只抓取有道内容，**不写库**。
  ///
  /// [termOverride] 非空时用它代替库里的词条文本——「编辑词条」流程要用
  /// 新文本去查，而不是旧文本。
  ///
  /// **与旧版的差异**：旧版还把重算后的 `normalizedTerm` 传给
  /// `lookupDictionary`；本版的 `ProviderRequest` 没有这个字段（各 provider
  /// 自行按语言规则归一化），因此这里只传词条文本。查询行为等价。
  /// 策略固定为 `PRIORITY_FALLBACK`（`lookup` 的默认值），与旧版一致。
  Future<YoudaoPreviewResult> preview({
    required int wordId,
    String? termOverride,
  }) async {
    final row = await _wordRow(wordId);
    final override = termOverride?.trim() ?? '';
    final term = override.isEmpty ? row.term : override;
    final result = await _dictionary.lookup(
      settings: await _settings.load(),
      request: ProviderRequest(
        term: term,
        contentType: row.contentType,
        sourceLanguage: row.sourceLanguage,
        targetLanguage: row.targetLanguage,
        wantedFields: const <String>{},
      ),
      selectedProviders: const <String>[youdaoDictionarySource],
      strategy: ProviderStrategy.priorityFallback,
    );
    return YoudaoPreviewResult(
      content: result.content,
      attempts: result.attempts,
      hasContent: hasAnyDictionaryContent(result.content),
    );
  }

  /// 把预览内容应用到词条。
  ///
  /// [mode] 为 [InitializationMode.forceOverwrite] 时保留用户资产后覆盖
  /// （[preserveUserContent]），否则只补空缺（[mergeDictionaryContent]）。
  /// [newTerm] 非空表示同时改词条文本——校验、查重与写入都在
  /// [WordEditService.updateContent] 的同一个事务里完成。
  Future<void> apply({
    required int wordId,
    required DictionaryContent fetched,
    required InitializationMode mode,
    required List<ProviderAttemptRecord> attempts,
    required int now,
    String? newTerm,
  }) async {
    final row = await _wordRow(wordId);
    final existing = await _existingContent(wordId);
    final merged = mode == InitializationMode.forceOverwrite
        ? preserveUserContent(existing, fetched)
        : mergeDictionaryContent(<DictionaryContent>[existing, fetched]);
    await _edit.updateContent(
      wordId: wordId,
      draft: WordDraft(
        term: newTerm?.trim() ?? row.term,
        contentType: row.contentType,
        sourceLanguage: row.sourceLanguage,
        targetLanguage: row.targetLanguage,
        content: merged,
      ),
      now: now,
      attempts: attempts,
    );
  }

  /// 读取预览与应用需要的词条行；不存在时抛 [AppErrorCode.wordNotFound]。
  Future<_RefreshWordRow> _wordRow(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT term, normalized_term, source_language, target_language, '
          'content_type FROM words WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) throw const NotFoundError(AppErrorCode.wordNotFound);
    final row = rows.first;
    return _RefreshWordRow(
      term: row.read<String>('term'),
      normalizedTerm: row.read<String>('normalized_term'),
      sourceLanguage: row.read<String>('source_language'),
      targetLanguage: row.read<String>('target_language'),
      contentType:
          wireLookup(
            LexicalContentType.values,
            row.read<String>('content_type'),
          ) ??
          LexicalContentType.word,
    );
  }

  /// 读取词条现有内容；没有内容行时返回空内容。
  Future<DictionaryContent> _existingContent(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM word_contents WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) return emptyDictionaryContent();
    return dictionaryContentFromColumns(
      rows.first.data.cast<String, Object?>(),
    );
  }
}

/// 抓取结果是否含任何可展示内容。
///
/// 与旧版 `youdao-parser.ts` 的 `hasAnyContent` 逐条对应：只要有一类
/// 内容非空，或摘要里有译文/短释义，就算「抓到了东西」。`confusedWords`
/// 不在旧版清单里，这里也不加——保持与旧版一致，避免「只有易混词」
/// 的词条在旧版被判为无内容、在这里被判为有内容。
bool hasAnyDictionaryContent(DictionaryContent content) {
  const fields = <String>[
    'definitions',
    'pronunciations',
    'forms',
    'examples',
    'phrases',
    'synonyms',
    'antonyms',
    'wordFamily',
    'roots',
    'affixes',
  ];
  if (fields.any((field) => content.records(field).isNotEmpty)) return true;
  final summary = content.record('summary');
  return _nonEmpty(summary['translation']) ||
      _nonEmpty(summary['shortDefinition']);
}

/// 预览与应用需要的词条行。
class _RefreshWordRow {
  const new({
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
  });

  final String term;
  final String normalizedTerm;
  final String sourceLanguage;
  final String targetLanguage;
  final LexicalContentType contentType;
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;
