/// 手动添加的「词典批量预览」：逐行生成预览与确认落库。
///
/// 对应旧版 `app/api/manual/preview/route.ts`、`app/api/manual/confirm/route.ts`；
/// 业务语义见 `modules/manual/service.ts`，字段补齐与落库见
/// `modules/manual/storage.ts`。
///
/// **与旧版的三处有意差异**：
/// 1. 预览**不落表**。旧版写 `manual_previews` 并靠
///    `UPDATE ... WHERE status = 'PREVIEW'` 认领令牌，是为了让多个并发的
///    HTTP 请求里只有一个能确认成功；纯本地单进程没有这种竞争，预览存内存
///    带 TTL 即可（TTL 沿用 [importPreviewTtlMs]，与旧版
///    `IMPORT_PREVIEW_TTL_MS` 同值）。
/// 2. 兜底数据源只剩 AI。旧版是「腾讯翻译 + AI」，腾讯翻译的 SecretKey 必须
///    内嵌进客户端，已刻意舍弃。
/// 3. 错误码复用 [AppErrorCode.requestedFieldsEmpty]。`lib/core/errors.dart`
///    已冻结，不再新增旧版的 `DICTIONARY_PREVIEW_EMPTY`；可操作的原因写进
///    [AppError.details]，界面按 `features/import/rollback_blocked_message.dart`
///    的同一约定读取。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/youdao_fields.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/text/normalizer.dart';
import 'package:lexiloop/services/dictionary/merge.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 一次词典抓取的调用签名。
///
/// 用函数类型而不是「单方法接口 + 适配器」：本服务只需要「调用」这一个动作，
/// 为它定义接口会多出一份只为测试而存在的样板（对照
/// `word_content_refresh_service.dart` 的 `WordLookup`，那里是因为同一抽象
/// 已被两处复用才值得具名）。测试里给一个返回预置结果的闭包即可，不发任何
/// 网络请求。
typedef ManualPreviewLookup = Future<DictionaryLookupResult> Function({
  required AppSettings settings,
  required ProviderRequest request,
  required List<String> selectedProviders,
  required ProviderStrategy strategy,
});

/// 一条手动预览。
///
/// 字段与旧版 `ManualContentPreview` 逐条对应；`content` 是**尚未落库**的
/// 词典内容。
class ManualPreview {
  /// 以各字段构造。
  const new({
    required this.previewToken,
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.sourceLanguageName,
    required this.targetLanguage,
    required this.targetLanguageName,
    required this.contentType,
    required this.content,
    required this.providerAttempts,
    required this.existingWordId,
    required this.expiresAt,
  });

  /// 确认时使用的令牌。
  final String previewToken;

  /// 用户输入的原始文本。
  final String term;

  /// 归一化文本（词条唯一性键的第一段）。
  final String normalizedTerm;

  /// 源语言代码。
  final String sourceLanguage;

  /// 源语言显示名。
  final String sourceLanguageName;

  /// 目标语言代码。
  final String targetLanguage;

  /// 目标语言显示名。
  final String targetLanguageName;

  /// 内容类型（已按 [detectContentType] 判定过）。
  final LexicalContentType contentType;

  /// 抓到的内容（预览，未写库）。
  final DictionaryContent content;

  /// 各数据源的调用记录。
  final List<ProviderAttemptRecord> providerAttempts;

  /// 该词条是否已存在（`normalized_term + 源语言 + 目标语言` 命中）。
  final int? existingWordId;

  /// 预览过期时间（epoch 毫秒）。
  final int expiresAt;

  /// 该预览是否已过期。
  bool isExpiredAt(int now) => now > expiresAt;
}

/// 确认预览的结果。
class ManualPreviewCommit {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.created,
    required this.idempotent,
    required this.initializationStatus,
    required this.contentType,
  });

  /// 写入或命中的词条 ID。
  final int wordId;

  /// 是否新建了词条（`false` 表示合并进了已有词条）。
  final bool created;

  /// 是否是同一令牌的重复确认。
  final bool idempotent;

  /// 落库后的初始化状态。
  final InitializationStatus initializationStatus;

  /// 落库后的内容类型。
  final LexicalContentType contentType;
}

/// 手动预览服务。
class ManualPreviewService {
  /// 以数据库、设置、词典查询与词条写入服务构造。
  new(this._db, this._settings, this._lookup, this._edit);

  final AppDatabase _db;
  final SettingsService _settings;
  final ManualPreviewLookup _lookup;
  final WordEditService _edit;

  /// 未过期的预览（令牌 → 预览）。**只在内存里**，见库级文档。
  final Map<String, ManualPreview> _previews = <String, ManualPreview>{};

  /// 已确认的令牌（令牌 → 落库结果），用于幂等返回。
  final Map<String, ManualPreviewCommit> _committed =
      <String, ManualPreviewCommit>{};

  /// 令牌序号：同一毫秒内多次预览靠它区分。
  int _sequence = 0;

  /// 生成一条预览（**不写任何表**）。
  ///
  /// [contentType] 为 `null` 时按 [detectContentType] 判定，对应旧版
  /// `TypeChoice = "AUTO"` 不传 `contentType` 的分支。
  ///
  /// [sourceLanguageName] / [targetLanguageName] 由调用方传入：语言显示名
  /// 的唯一出处是界面层的 `supportedLanguages`，服务再维护一份会漂移。
  Future<ManualPreview> createPreview({
    required String text,
    required String sourceLanguage,
    required String sourceLanguageName,
    required String targetLanguage,
    required String targetLanguageName,
    required int now,
    LexicalContentType? contentType,
  }) async {
    final term = text.trim();
    if (term.isEmpty) throw const ValidationError(AppErrorCode.termRequired);
    final type = contentType ?? detectContentType(term);
    final normalized = normalizeTerm(term, sourceLanguage);
    final existingId = await _edit.findByTerm(
      term: term,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final resolved = await _resolveLookup(
      term: term,
      type: type,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    _purgeExpired(now);
    final preview = ManualPreview(
      previewToken: 'manual-$now-${_sequence++}',
      term: term,
      normalizedTerm: normalized,
      sourceLanguage: sourceLanguage,
      sourceLanguageName: sourceLanguageName,
      targetLanguage: targetLanguage,
      targetLanguageName: targetLanguageName,
      contentType: type,
      content: resolved.content,
      providerAttempts: _withFieldsReturned(
        resolved.attempts,
        resolved.content,
      ),
      existingWordId: existingId,
      expiresAt: now + importPreviewTtlMs,
    );
    _previews[preview.previewToken] = preview;
    return preview;
  }

  /// 确认一条预览，返回落库结果。
  ///
  /// **幂等**：同一令牌只提交一次，第二次直接返回上次的 `wordId` 且
  /// [ManualPreviewCommit.idempotent] 为真——旧版靠
  /// `manual_previews.status = 'COMMITTED'` 达到同一效果。
  Future<ManualPreviewCommit> confirmPreview({
    required String previewToken,
    required int now,
  }) async {
    final committed = _committed[previewToken];
    if (committed != null) return committed.copyWithIdempotent();
    final preview = _previews[previewToken];
    if (preview == null) {
      throw const NotFoundError(
        AppErrorCode.notFound,
        details: _previewMissingReason,
      );
    }
    if (preview.isExpiredAt(now)) {
      _previews.remove(previewToken);
      throw const NotFoundError(
        AppErrorCode.notFound,
        details: _previewExpiredReason,
      );
    }
    final result = await _db.transaction(() => _commit(preview, now));
    _committed[previewToken] = result;
    return result;
  }

  /// 只用有道查一次；失败（`FAILED`）时再用 AI 兜底一次。
  ///
  /// 两次都失败时抛 [AppErrorCode.requestedFieldsEmpty]，可操作原因写进
  /// `details`。
  Future<_ResolvedLookup> _resolveLookup({
    required String term,
    required LexicalContentType type,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final settings = await _settings.load();
    final request = _request(
      term: term,
      type: type,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final primary = await _tryLookup(
      settings: settings,
      request: request,
      selectedProviders: const <String>[youdaoDictionarySource],
    );
    var content = normalizeDictionaryContent(primary.result.content.fields);
    var attempts = primary.result.attempts;
    final youdaoUnavailable = primary.unavailableReason;
    String? aiUnavailable;
    if (contentStatus(content, type) == InitializationStatus.failed) {
      final fallback = await _tryLookup(
        settings: settings,
        request: request,
        selectedProviders: const <String>[aiProviderSelectorId],
      );
      content = normalizeDictionaryContent(fallback.result.content.fields);
      attempts = <ProviderAttemptRecord>[
        ...attempts,
        ...fallback.result.attempts,
      ];
      aiUnavailable = fallback.unavailableReason;
    }
    if (contentStatus(content, type) == InitializationStatus.failed) {
      throw ExternalServiceError(
        AppErrorCode.requestedFieldsEmpty,
        details: _emptyPreviewReason(youdaoUnavailable, aiUnavailable),
      );
    }
    return _ResolvedLookup(content: content, attempts: attempts);
  }

  /// 调一次词典，并把「这次根本没跑起来」翻译成可读原因。
  ///
  /// `selection` 在来源未启用、不支持该语言或凭据不全时会把它筛掉；筛到
  /// 一个不剩时 `lookup` 直接抛 [AppErrorCode.providerNotFound]。旧版
  /// `lookupDictionary` 此时返回的是空内容，由「两次都失败」统一报错——
  /// 否则用户看到的是「指定的数据源不存在」，与「有道查不到这个词」完全
  /// 不是一回事（例如源语言选了日语，有道本来就只支持英文）。
  Future<_LookupAttempt> _tryLookup({
    required AppSettings settings,
    required ProviderRequest request,
    required List<String> selectedProviders,
  }) async {
    try {
      return _LookupAttempt(
        result: await _lookup(
          settings: settings,
          request: request,
          selectedProviders: selectedProviders,
          strategy: ProviderStrategy.priorityFallback,
        ),
      );
    } on AppError catch (error) {
      final details = error.details;
      return _LookupAttempt(
        result: DictionaryLookupResult(
          content: emptyDictionaryContent(),
          attempts: const <ProviderAttemptRecord>[],
          hasTransientFailure: error.isTransient,
          contentSource: ContentSource.dictionaryOnly,
        ),
        unavailableReason: details is String && details.isNotEmpty
            ? details
            : error.message,
      );
    }
  }

  /// 确认落库：新建或合并、写内容与审计、禁用排队中的初始化任务。
  ///
  /// 全部在一个事务里：半套的写入（词条已建而内容还是空的）比整次失败更糟。
  Future<ManualPreviewCommit> _commit(ManualPreview preview, int now) async {
    final existingId = await _existingWordId(preview);
    final wordId = existingId ?? await _insertWord(preview, now);
    final existingContent = existingId == null
        ? null
        : await _loadContent(wordId);
    final content = existingContent == null
        ? preview.content
        : mergeDictionaryContent(<DictionaryContent?>[
            existingContent,
            preview.content,
          ]);
    final status = contentStatus(content, preview.contentType);
    await _writeContent(
      wordId: wordId,
      content: content,
      attempts: preview.providerAttempts,
      source: existingId == null
          ? _contentSourceFor(preview.providerAttempts)
          : ContentSource.mixed,
      now: now,
    );
    await _writeMeta(
      wordId: wordId,
      contentType: preview.contentType,
      status: status,
      now: now,
    );
    await _disableQueuedJobs(wordId: wordId, now: now);
    return ManualPreviewCommit(
      wordId: wordId,
      created: existingId == null,
      idempotent: false,
      initializationStatus: status,
      contentType: preview.contentType,
    );
  }

  /// 该词条是否已存在；存在则返回 ID。
  Future<int?> _existingWordId(ManualPreview preview) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM words WHERE normalized_term = ? '
          'AND source_language = ? AND target_language = ? LIMIT 1',
          variables: <Variable<Object>>[
            Variable<String>(preview.normalizedTerm),
            Variable<String>(preview.sourceLanguage),
            Variable<String>(preview.targetLanguage),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<int>('id');
  }

  /// 新建词条：掌握度归零、不暂停，初始化状态由内容推导。
  Future<int> _insertWord(ManualPreview preview, int now) {
    return _db
        .into(_db.words)
        .insert(
          WordsCompanion.insert(
            term: displayTerm(
              preview.term,
              preview.sourceLanguage,
              preview.contentType,
            ),
            normalizedTerm: preview.normalizedTerm,
            sourceLanguage: preview.sourceLanguage,
            targetLanguage: preview.targetLanguage,
            sourceLanguageName: Value<String?>(preview.sourceLanguageName),
            targetLanguageName: Value<String?>(preview.targetLanguageName),
            entryType: entryTypeFor(preview.contentType),
            contentType: Value<LexicalContentType>(preview.contentType),
            initializationStatus: Value<InitializationStatus>(
              contentStatus(preview.content, preview.contentType),
            ),
            masteryLevel: const Value<MasteryLevel>(MasteryLevel.newWord),
            masteryScore: const Value<int>(0),
            isSuspended: const Value<bool>(false),
            sourceCreatedAt: Value<int>(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 读词条内容；没有内容行时返回 `null`。
  Future<DictionaryContent?> _loadContent(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM word_contents WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) return null;
    return dictionaryContentFromColumns(
      rows.first.data.cast<String, Object?>(),
    );
  }

  /// 整份写入内容（16 个 JSON 列）与数据源审计。
  ///
  /// **必须写满全部内容列**：合并后的内容缺哪一列，库里就留着上一轮的旧值，
  /// 界面上就是「合并了但例句还是老的」。
  Future<void> _writeContent({
    required int wordId,
    required DictionaryContent content,
    required List<ProviderAttemptRecord> attempts,
    required ContentSource source,
    required int now,
  }) async {
    final columns = content.toJsonColumns();
    final names = <String>[
      'word_id',
      ...columns.keys,
      'provider_metadata_json',
      'content_source',
      'content_version',
      'initialized_at',
      'updated_at',
    ];
    final assignments = <String>[
      for (final name in names)
        if (name != 'word_id' && name != 'content_version')
          '$name = excluded.$name',
      'content_version = word_contents.content_version + 1',
    ];
    await _db.customUpdate(
      'INSERT INTO word_contents (${names.join(', ')}) '
      'VALUES (${List<String>.filled(names.length, '?').join(', ')}) '
      'ON CONFLICT(word_id) DO UPDATE SET ${assignments.join(', ')}',
      variables: <Variable<Object>>[
        Variable<int>(wordId),
        for (final column in columns.keys) Variable<String>(columns[column]),
        Variable<String>(jsonEncode(_attemptsJson(attempts))),
        Variable<String>(source.wire),
        const Variable<int>(contentVersionWithContent),
        Variable<int>(now),
        Variable<int>(now),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.wordContents},
      updateKind: UpdateKind.update,
    );
    await _writeAttempts(wordId, attempts, now);
  }

  /// 把本次的数据源调用记录写入审计表。
  ///
  /// `initialization_job_id` 显式写 `NULL`：这是一次用户手动触发的预览确认，
  /// 不属于任何队列任务，挂到任务上会让「初始化质量」卡把它算进重试次数。
  Future<void> _writeAttempts(
    int wordId,
    List<ProviderAttemptRecord> attempts,
    int now,
  ) async {
    for (final attempt in attempts) {
      await _db.customInsert(
        'INSERT INTO provider_attempts (initialization_job_id, word_id, '
        'provider_id, status, duration_ms, fields_returned_json, error_code, '
        'error_message, metadata_json, created_at) '
        'VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: <Variable<Object>>[
          Variable<int>(wordId),
          Variable<String>(attempt.providerId),
          Variable<String>(attempt.status.wire),
          Variable<int>(attempt.durationMs),
          Variable<String>(jsonEncode(attempt.fieldsReturned)),
          Variable<String>(attempt.errorCode),
          Variable<String>(attempt.errorMessage),
          Variable<String>(
            attempt.metadata == null ? null : jsonEncode(attempt.metadata),
          ),
          Variable<int>(now),
        ],
        updates: <ResultSetImplementation<dynamic, dynamic>>{
          _db.providerAttempts,
        },
      );
    }
  }

  /// 写内容类型、初始化状态与更新时间。
  ///
  /// 不动 `entry_type`：与旧版一致，已有词条的 `entry_type` 由它自己的历史
  /// 决定，一次预览确认不该把它从 WORD 改成 PHRASE。
  Future<void> _writeMeta({
    required int wordId,
    required LexicalContentType contentType,
    required InitializationStatus status,
    required int now,
  }) async {
    await (_db.update(_db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        contentType: Value<LexicalContentType>(contentType),
        initializationStatus: Value<InitializationStatus>(status),
        updatedAt: Value<int>(now),
      ),
    );
  }

  /// 把该词条所有排队中的初始化任务置为「已禁用」。
  ///
  /// **为什么直接写库**：内容已经由预览确认落库，队列里针对这个词条的
  /// `QUEUED` 任务再跑一次只会用同一份词典内容覆盖一遍（或把刚写的内容
  /// 改回部分字段），并让「初始化」页显示一个永远不会完成的条目。
  /// `WordEditService` 没有「禁用任务」这类方法，且它属于另一个工作流，
  /// 因此在这里用与旧版 `modules/manual/service.ts` 逐字一致的 SQL 直接写。
  ///
  /// `last_error` / `last_error_code` 是旧版的固定文案（英文），用于区分
  /// 「被手动确认取代」与「任务失败」两种禁用原因。
  Future<void> _disableQueuedJobs({
    required int wordId,
    required int now,
  }) async {
    await _db.customUpdate(
      '''
UPDATE initialization_jobs
SET status = ?, completed_at = ?, updated_at = ?, locked_at = NULL,
    locked_by = NULL, last_error = ?, last_error_code = ?
WHERE word_id = ? AND status = ?''',
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.disabled.wire),
        Variable<int>(now),
        Variable<int>(now),
        const Variable<String>(_manualPreviewConfirmedError),
        const Variable<String>(_manualPreviewConfirmedErrorCode),
        Variable<int>(wordId),
        Variable<String>(InitializationStatus.queued.wire),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.initializationJobs,
      },
      updateKind: UpdateKind.update,
    );
  }

  /// 丢弃已过期的预览，避免内存里越积越多。
  void _purgeExpired(int now) =>
      _previews.removeWhere((_, preview) => preview.isExpiredAt(now));

  /// 构造一次查询请求；`wantedFields` 传空集表示「不限字段」。
  ProviderRequest _request({
    required String term,
    required LexicalContentType type,
    required String sourceLanguage,
    required String targetLanguage,
  }) => ProviderRequest(
    term: term,
    contentType: type,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    wantedFields: const <String>{},
  );
}

/// 一次预览解析的结果。
class _ResolvedLookup {
  const new({required this.content, required this.attempts});

  final DictionaryContent content;
  final List<ProviderAttemptRecord> attempts;
}

/// 一次数据源调用的结果与「没跑起来」的原因。
class _LookupAttempt {
  const new({required this.result, this.unavailableReason});

  final DictionaryLookupResult result;

  /// 非空表示这次调用压根没有可用的数据源（未启用 / 不支持 / 未配置）。
  final String? unavailableReason;
}

/// 批量输入的行切分（去空行）。
///
/// 放在服务层而不是界面层：它同时是 [manualBatchLimitError] 的输入，
/// 两处各写一遍会在「什么算一行」上漂移。
List<String> manualBatchLines(String text) => text
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

/// 批量输入的上限校验；通过时返回 `null`，否则返回中文报错文案。
///
/// 三条上限与旧版 `components/add/manual-tab.tsx` 的 `MAX_ROWS` /
/// `MAX_CHARS_PER_LINE` / `MAX_TOTAL_CHARS` 一致（常量见
/// `core/constants.dart` 的 `manualBatch*`）。
///
/// **与旧版的一处差异**：旧版把总长度交给 `<textarea maxLength>` 静默截断，
/// 用户粘贴超长文本时会「内容少了但没有任何提示」。这里改为在生成预览时
/// 报错，并给出与另外两条一致的中文文案。
String? manualBatchLimitError(String text) {
  final lines = manualBatchLines(text);
  if (lines.length > manualBatchMaxRows) {
    return '一次最多支持 $manualBatchMaxRows 行，请分多次添加。';
  }
  for (final line in lines) {
    if (line.length > manualBatchMaxCharsPerLine) {
      return '“${line.substring(0, manualBatchErrorSnippetLength)}…”'
          '超过单行 $manualBatchMaxCharsPerLine 字符限制，请缩短后重试。';
    }
  }
  if (text.length > manualBatchMaxTotalChars) {
    return '一次最多支持 $manualBatchMaxTotalChars 字符，请分多次添加。';
  }
  return null;
}

/// 以受限并发逐项执行 [task]，并等待全部完成。
///
/// 对应旧版 `manual-tab.tsx` 的 `runWithConcurrency`：词典站点对并发敏感，
/// 串行又太慢。单行任务抛异常会**向上传播并中断**调用方的等待，因此调用方
/// 必须在 [task] 内部自行捕获——批量预览正是靠这一点做到「单行失败不影响
/// 其他行」。
Future<void> runWithConcurrency<T>(
  List<T> items, {
  required int limit,
  required Future<void> Function(T item, int index) task,
}) async {
  var nextIndex = 0;
  Future<void> worker() async {
    while (nextIndex < items.length) {
      final index = nextIndex;
      nextIndex += 1;
      await task(items[index], index);
    }
  }

  final count = limit < items.length ? limit : items.length;
  await Future.wait(<Future<void>>[
    for (var i = 0; i < count; i += 1) worker(),
  ]);
}

/// 报错文案里截取的输入片段长度（旧版 `overlong.slice(0, 24)`）。
///
/// **为什么不放进 `core/constants.dart`**：该文件被本次迁移冻结，而这条数值
/// 只服务于本文件的报错文案，没有第二处消费者。架构守卫禁止 `lib/services/`
/// 出现裸数字，故按它自己给出的豁免方式标注（`lib/core/constants.dart` 的
/// `manualBatch*` 三条是本次唯一允许复用的上限常量）。
// 片段长度取自 `lib/core/constants.dart`，不在这里再定义一个数值。

/// 确认预览时写入初始化任务的 `last_error`（旧版逐字如此，英文）。
const String _manualPreviewConfirmedError = 'Manual preview confirmed';

/// 确认预览时写入初始化任务的 `last_error_code`（旧版逐字如此）。
const String _manualPreviewConfirmedErrorCode = 'MANUAL_PREVIEW_CONFIRMED';

/// 预览过期时的可操作原因。
const String _previewExpiredReason = '预览已过期，请重新生成。';

/// 令牌不存在时的可操作原因。
const String _previewMissingReason = '预览不存在，请重新生成。';

/// 词典与 AI 都没给出可用内容时的可操作原因。
///
/// 前半句与旧版 `DICTIONARY_PREVIEW_EMPTY` 的文案逐字一致，括号里补上
/// 「查过谁、为什么还是没内容」——旧版只报「请调整输入」，用户无从判断
/// 该改输入、该换语言，还是该去设置里配 AI。
String _emptyPreviewReason(String? youdaoReason, String? aiReason) {
  final notes = <String>[
    if (youdaoReason != null) '有道词典不可用：$youdaoReason',
    if (aiReason != null) 'AI 兜底不可用：$aiReason',
  ];
  if (notes.isEmpty) {
    return '词典没有返回可用释义，请调整输入或稍后重试。'
        '（已查有道词典并用 AI 兜底，两次都没有可用内容。）';
  }
  return '词典没有返回可用释义，请调整输入或稍后重试。'
      '（${notes.join('；')}）';
}

/// 给「没有记录到字段」的调用记录补上内容里实际非空的字段。
///
/// 对应旧版 `modules/manual/storage.ts` 的 `fieldsReturned(content)`：
/// 逐字段看数组是否非空、对象是否有任一非空值。有的数据源不汇报字段名，
/// 留空会让「初始化质量」卡显示「返回 0 个字段」。
List<ProviderAttemptRecord> _withFieldsReturned(
  List<ProviderAttemptRecord> attempts,
  DictionaryContent content,
) {
  final fields = _nonEmptyFields(content);
  return <ProviderAttemptRecord>[
    for (final attempt in attempts)
      if (attempt.fieldsReturned.isNotEmpty)
        attempt
      else
        ProviderAttemptRecord(
          providerId: attempt.providerId,
          status: attempt.status,
          durationMs: attempt.durationMs,
          fieldsReturned: fields,
          errorCode: attempt.errorCode,
          errorMessage: attempt.errorMessage,
          metadata: attempt.metadata,
        ),
  ];
}

/// 内容里实际非空的字段名。
List<String> _nonEmptyFields(DictionaryContent content) => <String>[
  for (final entry in content.fields.entries)
    if (_fieldHasContent(entry.value)) entry.key,
];

bool _fieldHasContent(Object? value) {
  if (value is List) return value.isNotEmpty;
  if (value is Map) {
    for (final item in value.values) {
      if (item is List ? item.isNotEmpty : item != null) return true;
    }
  }
  return false;
}

/// 由数据源调用记录推导内容来源，判据与 `ProviderPipeline` 一致。
ContentSource _contentSourceFor(List<ProviderAttemptRecord> attempts) {
  var ai = false;
  var dictionary = false;
  for (final attempt in attempts) {
    if (attempt.status != ProviderAttemptStatus.success) continue;
    if (isAiProviderId(attempt.providerId)) {
      ai = true;
    } else {
      dictionary = true;
    }
  }
  if (ai && dictionary) return ContentSource.mixed;
  return ai ? ContentSource.aiOnly : ContentSource.dictionaryOnly;
}

/// 调用记录的 JSON 形态（与 `WordEditService` 的同名构造一致）。
List<Map<String, Object?>> _attemptsJson(
  List<ProviderAttemptRecord> attempts,
) => <Map<String, Object?>>[
  for (final attempt in attempts)
    <String, Object?>{
      'providerId': attempt.providerId,
      'status': attempt.status.wire,
      'durationMs': attempt.durationMs,
      'fieldsReturned': attempt.fieldsReturned,
      if (attempt.errorCode != null) 'errorCode': attempt.errorCode,
      if (attempt.errorMessage != null) 'errorMessage': attempt.errorMessage,
      if (attempt.metadata != null) 'metadata': attempt.metadata,
    },
];

/// [ManualPreviewCommit] 的幂等副本。
extension _ManualPreviewCommitIdempotent on ManualPreviewCommit {
  /// 同一令牌的第二次确认：`idempotent` 置真、`created` 置假。
  ManualPreviewCommit copyWithIdempotent() => ManualPreviewCommit(
    wordId: wordId,
    created: false,
    idempotent: true,
    initializationStatus: initializationStatus,
    contentType: contentType,
  );
}
