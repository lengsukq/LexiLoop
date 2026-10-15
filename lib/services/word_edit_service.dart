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
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/text/normalizer.dart';

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
  Future<void> setSuspended({
    required int wordId,
    required bool suspended,
    required int now,
  }) async {
    await (_db.update(_db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        isSuspended: Value<bool>(suspended),
        updatedAt: Value<int>(now),
      ),
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
