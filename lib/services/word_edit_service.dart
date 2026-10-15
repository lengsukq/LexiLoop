/// 词条的写入。
///
/// `WordDao` 只做读；写入集中在这里，因为「创建词条」涉及
/// `words` + `word_contents` 两张表与内容状态推导，散在界面里容易写漏。
///
/// **与旧版的差异**：旧版手动添加是「预览（调词典）→ 确认」两阶段，
/// 预览落在服务端 `manual_previews` 表里并带 TTL 与令牌认领。本版是
/// 单用户本地应用，没有并发认领问题，因此**不建预览表**：
/// 手动录入直接写库，词典补全走初始化任务队列（写 `initialization_jobs`）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/review_dao.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/text/normalizer.dart';
import 'package:lexiloop/services/dictionary/merge.dart';

/// 界面下标定位到的例句原始位置。
///
/// 详情页渲染的是**过滤后**的例句列表（丢弃非对象与空句子），
/// 而 `examples_json` 是未经过滤的数组。两个下标不一定相等，
/// 所以删除与翻译都必须先经由本结构换算，不能直接拿界面下标去数组里取。
class ExampleLocation {
  /// 以原始元素列表与下标构造。
  const new({required this.entries, required this.position});

  /// `examples_json` 解码后的原始数组。
  final List<Object?> entries;

  /// 目标例句在该数组中的真实下标。
  final int position;
}

/// 一条例句草稿。
class WordExampleDraft {
  /// 以各字段构造。
  const new({required this.sentence, this.translation});

  /// 例句原文。
  final String sentence;

  /// 例句翻译。
  final String? translation;
}

/// 词条草稿。
class WordDraft {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.contentType,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.definitions = const <String>[],
    this.phonetic,
    this.examples = const <WordExampleDraft>[],
    this.tags = const <String>[],
    this.note,
  });

  /// 词条文本（用户输入的原始形态）。
  final String term;

  /// 内容类型。
  final LexicalContentType contentType;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 释义（目标语言）。
  final List<String> definitions;

  /// 音标。
  final String? phonetic;

  /// 例句。
  final List<WordExampleDraft> examples;

  /// 标签。
  final List<String> tags;

  /// 用户笔记。
  final String? note;

  /// 归一化后的词条文本。
  String get normalizedTerm => normalizeTerm(term, sourceLanguage);

  /// 是否有可用释义——决定内容状态是 READY 还是 PENDING。
  bool get hasDefinitions => definitions.any((text) => text.trim().isNotEmpty);
}

/// 词条写入入口。
class WordEditService {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 按归一化键查找已存在的词条 ID。
  Future<int?> findByTerm({
    required String term,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final normalized = normalizeTerm(term, sourceLanguage);
    final row = await _db
        .customSelect(
          '''
SELECT id FROM words
WHERE normalized_term = ? AND source_language = ? AND target_language = ?
LIMIT 1''',
          variables: <Variable<Object>>[
            Variable<String>(normalized),
            Variable<String>(sourceLanguage),
            Variable<String>(targetLanguage),
          ],
        )
        .getSingleOrNull();
    return row?.read<int>('id');
  }

  /// 创建词条与内容，返回新词条 ID。
  ///
  /// 重复词条抛 [AppErrorCode.termAlreadyExists]——静默合并会让用户
  /// 以为自己新建了一个词，实际改的是旧的。
  Future<int> create({required WordDraft draft, required int now}) async {
    final term = draft.term.trim();
    _assertValidTerm(term);
    final normalized = draft.normalizedTerm;

    final existing = await findByTerm(
      term: term,
      sourceLanguage: draft.sourceLanguage,
      targetLanguage: draft.targetLanguage,
    );
    if (existing != null) {
      throw const ConflictError(AppErrorCode.termAlreadyExists);
    }

    return await _db.transaction(() async {
      final wordId = await _db
          .into(_db.words)
          .insert(
            WordsCompanion.insert(
              term: displayTerm(term, draft.sourceLanguage, draft.contentType),
              normalizedTerm: normalized,
              sourceLanguage: draft.sourceLanguage,
              targetLanguage: draft.targetLanguage,
              entryType: legacyEntryType(draft.contentType),
              contentType: Value<LexicalContentType>(draft.contentType),
              initializationStatus: Value<InitializationStatus>(
                _statusFor(draft),
              ),
              userNote: Value<String?>(_blankToNull(draft.note)),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _upsertContent(wordId, draft, now);
      return wordId;
    });
  }

  /// 覆盖词条内容（不改词条文本与语种）。
  Future<void> updateContent({
    required int wordId,
    required WordDraft draft,
    required int now,
  }) async {
    await _db.transaction(() async {
      await _upsertContent(wordId, draft, now);
      await (_db.update(
        _db.words,
      )..where((row) => row.id.equals(wordId))).write(
        WordsCompanion(
          contentType: Value<LexicalContentType>(draft.contentType),
          entryType: Value<EntryType>(legacyEntryType(draft.contentType)),
          initializationStatus: Value<InitializationStatus>(_statusFor(draft)),
          userNote: Value<String?>(_blankToNull(draft.note)),
          updatedAt: Value<int>(now),
        ),
      );
    });
  }

  /// 切换「暂停学习」。
  ///
  /// 暂停会把该词条在**所有会话**里的待答题一并撤下
  /// （`skip_reason = WORD_SUSPENDED`，见 [wordSuspendedSkipReason]）：
  /// 留着它们等于让用户对着一个自己刚声明「不想学」的词继续做题，
  /// 被抽空的会话还会永远显示「未完成」。对应旧版
  /// `modules/words/mutations.ts` 的 `cancelPendingStudyItemsForSuspend`。
  ///
  /// 恢复学习**不**把撤下的题目放回队列：它们已经计入
  /// `completed_count`，放回去会让统计虚高；用户重开一次会话即可重新抽到。
  ///
  /// 撤题、计数、会话收尾与 `is_suspended` 的写入在**同一个事务**里：
  /// 半套的暂停（词已暂停而题还挂在队列上）比不暂停更糟。
  Future<void> setSuspended({
    required int wordId,
    required bool suspended,
    required int now,
  }) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.words,
      )..where((row) => row.id.equals(wordId))).write(
        WordsCompanion(
          isSuspended: Value<bool>(suspended),
          updatedAt: Value<int>(now),
        ),
      );
      if (suspended) await _withdrawPendingItems(wordId, now);
    });
  }

  /// 撤下某词条在待答题队列中的全部题目，并收尾被抽空的会话。
  ///
  /// 先按会话分组数出待答题：单条 `UPDATE` 只给出总数，而会话计数是
  /// **按会话**累加的，不知道每组各有几题就无从更新。
  /// 该词条没有任何待答题时直接返回——暂停是用户意图，不该因为
  /// 「没东西可撤」而失败。
  Future<void> _withdrawPendingItems(int wordId, int now) async {
    final grouped = await _pendingItemCounts(wordId);
    if (grouped.isEmpty) return;
    await _markWithdrawn(wordId, now);
    final review = ReviewDao(_db);
    for (final row in grouped) {
      final sessionId = row.read<int>('session_id');
      await _countWithdrawn(sessionId, row.read<int>('c'));
      if (await review.pendingItemCount(sessionId) == 0) {
        await review.closeSession(sessionId, now);
      }
    }
  }

  /// 该词条在各个会话里的待答题数（按会话分组）。
  Future<List<QueryRow>> _pendingItemCounts(int wordId) {
    return _db
        .customSelect(
          'SELECT study_session_id AS session_id, count(*) AS c '
          'FROM study_session_items '
          'WHERE word_id = ? AND status = ? GROUP BY study_session_id',
          variables: <Variable<Object>>[
            Variable<int>(wordId),
            Variable<String>(StudyItemStatus.pending.wire),
          ],
        )
        .get();
  }

  /// 把该词条的全部待答题标记为「因暂停而跳过」。
  ///
  /// `answered_at` 必须写：候选排除只看「已跳过**且**有作答时间」的题目，
  /// 留空等于让这个暂停在候选侧失效。
  Future<void> _markWithdrawn(int wordId, int now) async {
    await _db.customUpdate(
      '''
UPDATE study_session_items
SET status = ?, answered_at = ?, skip_reason = ?
WHERE word_id = ? AND status = ?''',
      variables: <Variable<Object>>[
        Variable<String>(StudyItemStatus.skipped.wire),
        Variable<int>(now),
        const Variable<String>(wordSuspendedSkipReason),
        Variable<int>(wordId),
        Variable<String>(StudyItemStatus.pending.wire),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.studySessionItems,
      },
      updateKind: UpdateKind.update,
    );
  }

  /// 把撤下的题数记进所属会话的完成数与跳过数。
  ///
  /// 跳过也算「处理过」：会话的完成判定只看还有没有待答题，
  /// `completed_count` 不跟着涨，进度条就会永远差一截。
  Future<void> _countWithdrawn(int sessionId, int count) async {
    await _db.customUpdate(
      'UPDATE study_sessions '
      'SET completed_count = completed_count + ?, '
      'skipped_count = skipped_count + ? '
      'WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<int>(count),
        Variable<int>(count),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.studySessions},
      updateKind: UpdateKind.update,
    );
  }

  /// 保存用户笔记；传 `null` 或空白表示清空。
  Future<void> saveNote({
    required int wordId,
    required String? note,
    required int now,
  }) async {
    await (_db.update(_db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        userNote: Value<String?>(_blankToNull(note)),
        updatedAt: Value<int>(now),
      ),
    );
  }

  /// 写入或替换用户手工撰写的那条释义。
  ///
  /// 对应旧版 `modules/words/mutations.ts` 的 `updateManualDefinition`：
  /// 先摘掉全部历史手工释义，再把新的一条**前置**——用户刚写下的那句
  /// 就是他现在最想看到的那句，排在词典释义后面等于让他先翻十几行。
  ///
  /// 识别「历史手工释义」用 [isUserProtectedItem]（`isUserEdited == true`）
  /// 而不是旧版的「`source === 'user'` 且 `isUserEdited`」双条件：本项目
  /// 手工录入路径写的是 [manualContentSource]，按旧条件永远删不掉，
  /// 每保存一次就多出一条自己写的释义。用合并层同一套判定，两条路径的
  /// 「谁算用户资产」才不会漂移。
  ///
  /// [definition] 传空白表示「撤掉我写的释义」；原本就没有手工释义且
  /// 新内容也为空时不写库，避免把一次空操作记成一次编辑。
  Future<void> updateManualDefinition({
    required int wordId,
    required String definition,
    required int now,
    String? partOfSpeech,
  }) async {
    final text = definition.trim();
    _assertDefinitionLength(text, partOfSpeech);
    final word = await _contentWord(wordId);
    final content = await _loadContent(wordId);
    final previous = content.records('definitions');
    final kept = previous
        .where((item) => !isUserProtectedItem('definitions', item))
        .toList();
    if (text.isEmpty && kept.length == previous.length) return;

    final next = <Map<String, Object?>>[
      if (text.isNotEmpty)
        _userDefinition(word.targetLanguage, text, partOfSpeech),
      ...kept,
    ];
    final status = contentStatus(
      content.withField('definitions', next),
      word.contentType,
    );
    await _db.transaction(() async {
      await _writeDefinitions(wordId, next, now);
      await (_db.update(
        _db.words,
      )..where((row) => row.id.equals(wordId))).write(
        WordsCompanion(
          initializationStatus: Value<InitializationStatus>(status),
          updatedAt: Value<int>(now),
        ),
      );
    });
  }

  /// 删除一条例句。
  ///
  /// [index] 是**界面渲染顺序**里的下标（详情页逐条渲染
  /// `parseDetailExamples` 的结果），底层用 [detailExamplePositions] 换算回
  /// `examples_json` 的真实下标——解析会丢弃「非对象」与「句子为空」的条目，
  /// 两个下标并不总是相等，不换算就会删掉隔壁那条。
  ///
  /// 下标越界抛 [NotFoundError] 而不是静默返回：调用方是「用户点了第 N 条的
  /// 删除」，若此时列表刚被别的改动刷新过，静默返回会让按钮看起来是坏的，
  /// 而真正的原因（列表已变）根本不会被记录。
  ///
  /// 顺手重算内容状态：删掉最后一条例句后词条应从 `READY` 退到 `PARTIAL`，
  /// 不重算的话界面上会一直显示「内容齐了」，而出填空题时又真的没有句子可用。
  Future<void> deleteExample({
    required int wordId,
    required int index,
    required int now,
  }) async {
    final target = await _exampleAt(wordId, index);
    final kept = <Object?>[...target.entries]..removeAt(target.position);
    final word = await _contentWord(wordId);
    final status = contentStatus(
      (await _loadContent(wordId)).withField('examples', kept),
      word.contentType,
    );
    await _db.transaction(() async {
      await _writeExamples(wordId, kept, now);
      await (_db.update(
        _db.words,
      )..where((row) => row.id.equals(wordId))).write(
        WordsCompanion(
          initializationStatus: Value<InitializationStatus>(status),
          updatedAt: Value<int>(now),
        ),
      );
    });
  }

  /// 为一条例句排一个「AI 翻译」任务。
  ///
  /// **不在这里做翻译**：翻译由 `initialization_worker` 执行，本方法只负责
  /// 入队。这样「翻译质量」与「翻译入口」解耦——界面、批量操作、导入回放
  /// 都能触发同一个 worker 路径，不会出现两套翻译实现给出两种译文。
  ///
  /// 重复点击是幂等的：`initialization_jobs_active_word_task_unique` 保证
  /// 同一词条的同一任务类型最多一个活跃任务，插入冲突被
  /// `ON CONFLICT DO NOTHING` 吞掉。
  Future<void> translateExample({
    required int wordId,
    required int index,
    required int now,
  }) async {
    await _exampleAt(wordId, index);
    await enqueueInitialization(
      wordId: wordId,
      now: now,
      taskType: JobTaskType.exampleTranslations,
    );
  }

  /// 定位界面下标对应的例句原始元素。
  ///
  /// 索引换算与越界判定都收在这里：两个调用方拿到的
  /// [ExampleLocation.position] 一定是「用户指的那一条」在
  /// `examples_json` 里的真实下标。
  Future<ExampleLocation> _exampleAt(int wordId, int index) async {
    final raw = await _contentColumn(wordId, contentColumnNames['examples']);
    final positions = detailExamplePositions(raw);
    if (index < 0 || index >= positions.length) {
      throw const NotFoundError(AppErrorCode.exampleNotFound);
    }
    return ExampleLocation(
      entries: decodeJsonList(raw),
      position: positions[index],
    );
  }

  /// 读单个内容列的 JSON 文本。
  Future<String?> _contentColumn(int wordId, String? column) async {
    if (column == null) return null;
    final rows = await _db
        .customSelect(
          'SELECT $column FROM word_contents WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>(column);
  }

  /// 读取词条的内容类型与目标语言；词条不存在时抛 [AppErrorCode.wordNotFound]。
  ///
  /// 手工释义要用目标语言作为 `language`，内容状态要按内容类型判定，
  /// 两者都只能从 `words` 行取——`word_contents` 里没有这份信息。
  Future<({LexicalContentType contentType, String targetLanguage})>
  _contentWord(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT content_type, target_language FROM words WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) throw const NotFoundError(AppErrorCode.wordNotFound);
    return (
      contentType:
          wireLookup(
            LexicalContentType.values,
            rows.first.read<String>('content_type'),
          ) ??
          LexicalContentType.word,
      targetLanguage: rows.first.read<String>('target_language'),
    );
  }

  /// 读取该词条的完整内容；没有内容行时返回空内容。
  Future<DictionaryContent> _loadContent(int wordId) async {
    final columns = contentColumnNames.values.join(', ');
    final rows = await _db
        .customSelect(
          'SELECT $columns FROM word_contents WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) return emptyDictionaryContent();
    return dictionaryContentFromColumns(
      rows.first.data.cast<String, Object?>(),
    );
  }

  /// 覆写释义列并自增内容版本号。
  ///
  /// `content_version` 必须自增：它是并发冲突提示的依据，
  /// 用 `excluded` 覆盖会永远停在 1。
  Future<void> _writeDefinitions(
    int wordId,
    List<Map<String, Object?>> definitions,
    int now,
  ) => _db.customUpdate(
    'UPDATE word_contents SET definitions_json = ?, '
    'content_version = content_version + 1, updated_at = ? WHERE word_id = ?',
    variables: <Variable<Object>>[
      Variable<String>(jsonEncode(definitions)),
      Variable<int>(now),
      Variable<int>(wordId),
    ],
    updates: <ResultSetImplementation<dynamic, dynamic>>{_db.wordContents},
    updateKind: UpdateKind.update,
  );

  /// 覆写例句列并自增内容版本号。
  Future<void> _writeExamples(
    int wordId,
    List<Object?> examples,
    int now,
  ) => _db.customUpdate(
    'UPDATE word_contents SET examples_json = ?, '
    'content_version = content_version + 1, updated_at = ? WHERE word_id = ?',
    variables: <Variable<Object>>[
      Variable<String>(jsonEncode(examples)),
      Variable<int>(now),
      Variable<int>(wordId),
    ],
    updates: <ResultSetImplementation<dynamic, dynamic>>{_db.wordContents},
    updateKind: UpdateKind.update,
  );

  /// 构造一条用户手工撰写的释义。
  ///
  /// `isUserEdited: true` 是「用户资产」的判据（[isUserProtectedItem]），
  /// `source` 则让界面能一眼看出这条不是词典给的。
  Map<String, Object?> _userDefinition(
    String language,
    String text,
    String? partOfSpeech,
  ) => <String, Object?>{
    'language': language,
    'partOfSpeech': _blankToNull(partOfSpeech),
    'text': text,
    'source': userAuthoredDefinitionSource,
    'isUserEdited': true,
  };

  /// 手工释义与词性标注的长度校验。
  ///
  /// 复用一个错误码但各自写明原因：超长释义会让选择题选项撑破卡片，
  /// 超长词性标注没有任何使用场景。
  void _assertDefinitionLength(String text, String? partOfSpeech) {
    if (text.length > manualDefinitionMaxLength) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '释义过长',
      );
    }
    if ((partOfSpeech?.trim().length ?? 0) >
        manualDefinitionPartOfSpeechMaxLength) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '词性标注过长',
      );
    }
  }

  /// 删除词条。
  ///
  /// 内容、卡片、日志、错词状态由外键级联删除（`beforeOpen` 里开了
  /// `PRAGMA foreign_keys = ON`，见 `database.dart`）。
  Future<void> delete(int wordId) async {
    await (_db.delete(_db.words)..where((row) => row.id.equals(wordId))).go();
  }

  /// 把词条加入初始化队列（补全缺失字段）。
  ///
  /// 同一词条的同一任务类型最多一个活跃任务——那条部分唯一索引在
  /// `database.dart` 里，这里用 `ON CONFLICT DO NOTHING` 让重复入队幂等。
  ///
  /// [mode] 默认「补全缺失字段」：手动录入的词条通常已有部分内容，
  /// 初始化只该补空，不该覆盖用户刚填的东西。
  Future<void> enqueueInitialization({
    required int wordId,
    required int now,
    JobTaskType taskType = JobTaskType.initialize,
    InitializationMode mode = InitializationMode.fillMissingFields,
    int priority = jobPriorityDefault,
  }) async {
    await _db.customInsert(
      '''
INSERT INTO initialization_jobs
  (word_id, task_type, mode, status, priority, attempt_count, max_attempts,
   available_at, created_at, updated_at)
VALUES (?, ?, ?, 'QUEUED', ?, 0, ?, ?, ?, ?)
ON CONFLICT DO NOTHING''',
      variables: <Variable<Object>>[
        Variable<int>(wordId),
        Variable<String>(taskType.wire),
        Variable<String>(mode.wire),
        Variable<int>(priority),
        const Variable<int>(importJobMaxAttempts),
        Variable<int>(now),
        Variable<int>(now),
        Variable<int>(now),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.initializationJobs,
      },
    );
  }

  Future<void> _upsertContent(int wordId, WordDraft draft, int now) async {
    final companion = WordContentsCompanion(
      wordId: Value<int>(wordId),
      definitionsJson: Value<String>(_definitionsJson(draft)),
      pronunciationsJson: Value<String>(_pronunciationsJson(draft)),
      examplesJson: Value<String>(_examplesJson(draft)),
      tagsJson: Value<String>(jsonEncode(_cleanList(draft.tags))),
      contentSource: const Value<ContentSource>(ContentSource.dictionaryOnly),
      contentVersion: Value<int>(_contentVersionFor(draft)),
      updatedAt: Value<int>(now),
    );

    final existing = await (_db.select(
      _db.wordContents,
    )..where((row) => row.wordId.equals(wordId))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.wordContents).insert(companion);
    } else {
      await (_db.update(
        _db.wordContents,
      )..where((row) => row.wordId.equals(wordId))).write(companion);
    }
  }

  String _definitionsJson(WordDraft draft) => jsonEncode(<Object?>[
    for (final text in _cleanList(draft.definitions))
      <String, Object?>{
        'language': draft.targetLanguage,
        'text': text,
        'source': manualContentSource,
      },
  ]);

  String _pronunciationsJson(WordDraft draft) {
    final phonetic = draft.phonetic?.trim() ?? '';
    if (phonetic.isEmpty) return '[]';
    return jsonEncode(<Object?>[
      <String, Object?>{
        'accent': defaultAccent,
        'phonetic': phonetic,
        'source': manualContentSource,
      },
    ]);
  }

  String _examplesJson(WordDraft draft) => jsonEncode(<Object?>[
    for (final example in draft.examples)
      if (example.sentence.trim().isNotEmpty)
        <String, Object?>{
          'sentence': example.sentence.trim(),
          'translation': _blankToNull(example.translation),
        },
  ]);

  InitializationStatus _statusFor(WordDraft draft) => draft.hasDefinitions
      ? InitializationStatus.ready
      : InitializationStatus.pending;

  /// 内容版本号：有释义记 1，否则记 0。
  ///
  /// 备份回放与词典补全都用它判断「这份内容是不是空的」，
  /// 因此必须与内容一起写，不能留在 `words` 上。
  int _contentVersionFor(WordDraft draft) =>
      draft.hasDefinitions ? contentVersionWithContent : contentVersionEmpty;

  void _assertValidTerm(String term) {
    if (term.isEmpty) {
      throw const ValidationError(AppErrorCode.termRequired);
    }
    if (term.length > termMaxLength) {
      throw const ValidationError(AppErrorCode.termTooLong);
    }
  }
}

/// 手工录入内容的来源标识。
const String manualContentSource = 'manual';

/// 有内容时的内容版本号。
const int contentVersionWithContent = 1;

/// 无内容时的内容版本号。
const int contentVersionEmpty = 0;

List<String> _cleanList(List<String> values) => values
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList(growable: false);

String? _blankToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// 句子类型归到 `PHRASE`——`entry_type` 是旧的二值字段，没有 SENTENCE。
EntryType legacyEntryType(LexicalContentType type) =>
    type == LexicalContentType.word ? EntryType.word : EntryType.phrase;
