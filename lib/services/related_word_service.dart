/// 关联词的预览与加入词库。
///
/// 对应旧版 `src/modules/words/related.ts` 的 `previewRelatedWord` 与
/// `addRelatedWord`（该文件的 `deleteWord` 属于删除路径，已在
/// `WordEditService.delete` 中实现，不重复搬过来）。
///
/// **为什么「加入关联词」要建初始化任务**：详情页上的同义词/反义词只是父
/// 词条内容里的一个字符串，它自己没有释义、音标与例句，直接入库会让用户
/// 在词库里看到一个永远学不了的空词条。旧版因此固定走「建词条 → 入队
/// 初始化」，这里照搬，并且优先级取 [jobPriorityRelatedWord]——比后台补充
/// 任务高得多，用户刚点下的动作应当排在前面。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/domain/text/normalizer.dart';

/// 父词条内容里可能记载关联词的四个字段。
///
/// 顺序与旧版 `findRelatedContent` 的展开顺序一致；同一文本同时出现在
/// 多个字段时，先出现的那个字段胜出。
const List<String> relatedContentFields = <String>[
  'synonyms',
  'antonyms',
  'wordFamily',
  'confusedWords',
];

/// 关联词服务。
class RelatedWordService {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 预览一个关联词：父词条里记载的关系信息 + 它是否已在词库。
  ///
  /// 词条文本取 1–300 字符；与父词条归一化后相同则拒绝——把词条自己加进
  /// 它自己的同义词列表，只会在详情页里生成一个指向自己的死循环入口。
  Future<RelatedWordPreview> preview({
    required int parentWordId,
    required String rawTerm,
  }) async {
    final parent = await _parent(parentWordId);
    final term = assertRelatedTerm(rawTerm);
    final normalizedTerm = normalizeTerm(term, parent.sourceLanguage);
    assertNotParentWord(normalizedTerm, parent.normalizedTerm);
    final related = _findRelated(await _content(parentWordId), term);
    return RelatedWordPreview(
      term: term,
      normalizedTerm: normalizedTerm,
      sourceLanguage: parent.sourceLanguage,
      targetLanguage: parent.targetLanguage,
      relation: _relationOf(related),
      translation: related?.text('translation'),
      partOfSpeech: related?.text('partOfSpeech'),
      difference: related?.text('difference'),
      source: related?.text('source'),
      existing: await _existingWord(normalizedTerm, parent),
    );
  }

  /// 把一个关联词加入词库，并在内容不完整时排入初始化任务。
  ///
  /// 整段逻辑在**一个事务**里：新建词条与建任务之间失败会留下一个永远
  /// 排不上队、界面上却显示「排队中」的词条。
  Future<RelatedAddResult> add({
    required int parentWordId,
    required String rawTerm,
    required RelationType relation,
    required int now,
  }) async {
    final parent = await _parent(parentWordId);
    final term = assertRelatedTerm(rawTerm);
    final normalizedTerm = normalizeTerm(term, parent.sourceLanguage);
    assertNotParentWord(normalizedTerm, parent.normalizedTerm);
    return await _db.transaction(() async {
      final existing = await _existingWord(normalizedTerm, parent);
      final created = existing == null;
      final wordId =
          existing?.id ?? await _createWord(parent, term, normalizedTerm, now);
      final status = existing?.initializationStatus;
      if (_hasUsableContent(status)) {
        return RelatedAddResult(
          wordId: wordId,
          term: existing!.term,
          created: false,
          queued: false,
          relation: relation,
          initializationStatus: status!,
        );
      }
      final jobId = await _queueInitialization(
        wordId,
        created: created,
        now: now,
      );
      await _setWordQueued(wordId, now);
      return RelatedAddResult(
        wordId: wordId,
        term: _resultTerm(existing, term, parent),
        created: created,
        queued: true,
        jobId: jobId,
        relation: relation,
        initializationStatus: InitializationStatus.queued,
      );
    });
  }

  /// 结果里回显的词条文本：复用既有词条时用它的文本，新建时按语言规则规整。
  String _resultTerm(
    RelatedWordExisting? existing,
    String term,
    _RelatedParent parent,
  ) =>
      existing?.term ??
      displayTerm(term, parent.sourceLanguage, detectContentType(term));

  /// 新建词条行（内容留空，由初始化任务补）。
  Future<int> _createWord(
    _RelatedParent parent,
    String term,
    String normalizedTerm,
    int now,
  ) {
    final type = detectContentType(term);
    return _db
        .into(_db.words)
        .insert(
          WordsCompanion.insert(
            term: displayTerm(term, parent.sourceLanguage, type),
            normalizedTerm: normalizedTerm,
            sourceLanguage: parent.sourceLanguage,
            targetLanguage: parent.targetLanguage,
            sourceLanguageName: Value<String?>(parent.sourceLanguageName),
            targetLanguageName: Value<String?>(parent.targetLanguageName),
            entryType: entryTypeFor(type),
            contentType: Value<LexicalContentType>(type),
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.queued,
            ),
            masteryLevel: const Value<MasteryLevel>(MasteryLevel.newWord),
            masteryScore: const Value<int>(0),
            isSuspended: const Value<bool>(false),
            sourceCreatedAt: Value<int?>(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 排一个初始化任务；已有活跃任务时升级它而不是再建一个。
  ///
  /// 部分唯一索引保证同一词条的同一任务类型最多一个活跃任务，因此
  /// 「已存在」是常态：用户可能先点过一次、任务还没跑。升级优先级的写法
  /// 用 `max(priority, ?)` 而不是直接赋值——把用户显式选中的批量初始化
  /// （优先级更高）降下来，会让这个刚点下的任务排到别的任务后面。
  Future<int> _queueInitialization(
    int wordId, {
    required bool created,
    required int now,
  }) async {
    final active = await _activeJobId(wordId);
    if (active != null) {
      await _db.customUpdate(
        'UPDATE initialization_jobs SET mode = ?, priority = max(priority, ?), '
        'available_at = ?, updated_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<String>(InitializationMode.fillMissingFields.wire),
          const Variable<int>(jobPriorityRelatedWord),
          Variable<int>(now),
          Variable<int>(now),
          Variable<int>(active),
        ],
        updates: <ResultSetImplementation<dynamic, dynamic>>{
          _db.initializationJobs,
        },
        updateKind: UpdateKind.update,
      );
      return active;
    }
    return await _db
        .into(_db.initializationJobs)
        .insert(
          InitializationJobsCompanion.insert(
            wordId: wordId,
            // 新建的词条必然还没有内容，用 SKIP_INITIALIZED 让 worker 少跑
            // 一次「已有内容是否够用」的判定；复用的既有词条走只补空缺。
            mode: created
                ? InitializationMode.skipInitialized
                : InitializationMode.fillMissingFields,
            priority: const Value<int>(jobPriorityRelatedWord),
            maxAttempts: const Value<int>(importJobMaxAttempts),
            availableAt: Value<int?>(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 该词条当前活跃的初始化任务 ID；没有时返回 `null`。
  ///
  /// 必须限定 `task_type`：词条上可能挂着一个待跑的例句翻译任务，
  /// 不限定就会把那个任务的 ID 当成初始化任务返回。
  Future<int?> _activeJobId(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM initialization_jobs WHERE word_id = ? '
          "AND task_type = ? AND status IN ('QUEUED', 'RUNNING') LIMIT 1",
          variables: <Variable<Object>>[
            Variable<int>(wordId),
            Variable<String>(JobTaskType.initialize.wire),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<int>('id');
  }

  /// 把词条状态置为「排队中」。
  Future<void> _setWordQueued(int wordId, int now) => _db.customUpdate(
    'UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?',
    variables: <Variable<Object>>[
      Variable<String>(InitializationStatus.queued.wire),
      Variable<int>(now),
      Variable<int>(wordId),
    ],
    updates: <ResultSetImplementation<dynamic, dynamic>>{_db.words},
    updateKind: UpdateKind.update,
  );

  /// 按「归一化文本 + 语言对」查词库中已有的词条。
  Future<RelatedWordExisting?> _existingWord(
    String normalizedTerm,
    _RelatedParent parent,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT id, term, initialization_status, mastery_level, '
          'mastery_score FROM words WHERE normalized_term = ? '
          'AND source_language = ? AND target_language = ? LIMIT 1',
          variables: <Variable<Object>>[
            Variable<String>(normalizedTerm),
            Variable<String>(parent.sourceLanguage),
            Variable<String>(parent.targetLanguage),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RelatedWordExisting(
      id: row.read<int>('id'),
      term: row.read<String>('term'),
      initializationStatus:
          wireLookup(
            InitializationStatus.values,
            row.read<String>('initialization_status'),
          ) ??
          InitializationStatus.pending,
      masteryLevel:
          wireLookup(MasteryLevel.values, row.read<String>('mastery_level')) ??
          MasteryLevel.newWord,
      masteryScore: row.read<int>('mastery_score'),
    );
  }

  /// 读取父词条行；不存在时抛 [AppErrorCode.wordNotFound]。
  Future<_RelatedParent> _parent(int parentWordId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, normalized_term, source_language, target_language, '
          'source_language_name, target_language_name, content_type '
          'FROM words WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(parentWordId)],
        )
        .get();
    if (rows.isEmpty) throw const NotFoundError(AppErrorCode.wordNotFound);
    final row = rows.first;
    return _RelatedParent(
      normalizedTerm: row.read<String>('normalized_term'),
      sourceLanguage: row.read<String>('source_language'),
      targetLanguage: row.read<String>('target_language'),
      sourceLanguageName: row.readNullable<String>('source_language_name'),
      targetLanguageName: row.readNullable<String>('target_language_name'),
    );
  }

  /// 读取父词条内容；没有内容行时返回空内容。
  Future<DictionaryContent> _content(int parentWordId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM word_contents WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(parentWordId)],
        )
        .get();
    if (rows.isEmpty) return emptyDictionaryContent();
    return dictionaryContentFromColumns(
      rows.first.data.cast<String, Object?>(),
    );
  }
}

/// 校验并规整关联词文本。
///
/// 旧版用 zod 的 `min(1).max(300)`，统一抛 `VALIDATION_ERROR`；这里改用
/// 更具体的 [AppErrorCode.termRequired] / [AppErrorCode.termTooLong]：
/// 弹窗要把「不能为空」与「太长了」分别说清楚，笼统的「参数无效」
/// 让用户不知道该改哪里。
String assertRelatedTerm(String rawTerm) {
  final term = rawTerm.trim();
  if (term.isEmpty) throw const ValidationError(AppErrorCode.termRequired);
  if (term.length > termMaxLength) {
    throw const ValidationError(AppErrorCode.termTooLong);
  }
  return term;
}

/// 关联词不能是父词条自己。
void assertNotParentWord(String normalizedTerm, String parentNormalizedTerm) {
  if (normalizedTerm == parentNormalizedTerm) {
    throw const ConflictError(AppErrorCode.relatedWordSameAsParent);
  }
}

/// 该状态是否已具备可用内容。
bool _hasUsableContent(InitializationStatus? status) =>
    status == InitializationStatus.ready ||
    status == InitializationStatus.partial;

/// 在父词条内容里按归一化文本找关联项。
_RelatedItem? _findRelated(DictionaryContent content, String term) {
  final key = relatedWordLookupKey(term);
  for (final field in relatedContentFields) {
    for (final item in content.records(field)) {
      final word = relatedWordOf(item);
      if (word.isEmpty) continue;
      if (relatedWordLookupKey(word) == key) return _RelatedItem(item);
    }
  }
  return null;
}

/// 关联项记载的关系类型；缺失或无法识别时退回近义词（与旧版一致）。
RelationType _relationOf(_RelatedItem? item) {
  if (item == null) return RelationType.synonym;
  return wireLookup(RelationType.values, item.text('relation') ?? '') ??
      RelationType.synonym;
}

/// 父词条里找到的关联项。
class _RelatedItem {
  const new(this.item);

  final Map<String, Object?> item;

  /// 取一个可空文本字段。
  String? text(String key) => fieldOf(item, key);
}

/// 关联词操作需要的父词条信息。
class _RelatedParent {
  const new({
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.sourceLanguageName,
    this.targetLanguageName,
  });

  final String normalizedTerm;
  final String sourceLanguage;
  final String targetLanguage;
  final String? sourceLanguageName;
  final String? targetLanguageName;
}
