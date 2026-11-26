/// 词书包元信息与学习进度查询 DAO。
library;

import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';

/// 已安装词书的聚合视图（含实时掌握进度与初始化状态统计）。
class InstalledWordPackSummary {
  /// 以各统计字段构造。
  const new({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.description,
    required this.version,
    required this.contentMode,
    required this.includeInDailyStudy,
    required this.installedAt,
    required this.totalWords,
    required this.masteredWords,
    required this.learningWords,
    required this.readyWords,
    required this.partialWords,
    required this.pendingWords,
  });

  /// 词书 ID。
  final String id;

  /// 词书短名。
  final String slug;

  /// 词书展示名。
  final String name;

  /// 分类。
  final WordPackCategory category;

  /// 简介。
  final String description;

  /// 版本号。
  final String version;

  /// 预初始化等级。
  final WordPackContentMode contentMode;

  /// 是否已纳入每日学习计划。
  final bool includeInDailyStudy;

  /// 安装时间（epoch 毫秒）。
  final int installedAt;

  /// 词书当前关联词条总数。
  final int totalWords;

  /// 已掌握词数（`MASTERED`）。
  final int masteredWords;

  /// 学习中词数（`LEARNING` / `FAMILIAR` / `PROFICIENT`）。
  final int learningWords;

  /// 已完全就绪（`READY`）词数。
  final int readyWords;

  /// 部分就绪（`PARTIAL`，如 ECDICT 预填充可立即学习）词数。
  final int partialWords;

  /// 待初始化（`PENDING` / `QUEUED` / `RUNNING` / `FAILED`）词数。
  final int pendingWords;

  /// 尚未接触的新词数。
  int get newWords => math.max(0, totalWords - masteredWords - learningWords);

  /// 仍可用有道进一步补全（例句/短语/同根词）的词条数。
  int get enrichableWords => partialWords + pendingWords;

  /// 掌握率（0–100）。
  int get masteredPercent =>
      totalWords == 0 ? 0 : (masteredWords * percentScale / totalWords).round();
}

/// 卸载一本词书前的精确影响评估。
class WordPackUninstallImpact {
  /// 以各类词条影响计数构造。
  const new({
    required this.packId,
    required this.packName,
    required this.totalWords,
    required this.personalKeptCount,
    required this.sharedOtherPackCount,
    required this.removableUnlearnedCount,
    required this.learnedOnlyInPackCount,
  });

  /// 词书 ID。
  final String packId;

  /// 词书名。
  final String packName;

  /// 词书总词数。
  final int totalWords;

  /// 本身在个人词库中（`is_personal = 1`），卸载后丝毫不动的词数。
  final int personalKeptCount;

  /// 仍属于其他已安装词书，卸载后保留的词数。
  final int sharedOtherPackCount;

  /// 仅属于本词书且从未学习过，将被安全清理释放空间的词数。
  final int removableUnlearnedCount;

  /// 仅属于本词书但已产生复习记录/卡片的词数（默认转入个人词库保留）。
  final int learnedOnlyInPackCount;
}

/// 卸载影响评估查询 SQL（按词条归属与学习记录分四类统计）。
const String _uninstallImpactSql = '''
SELECT
  count(*) AS total_words,
  coalesce(sum(CASE WHEN w.is_personal = 1 THEN 1 ELSE 0 END), 0)
    AS personal_kept,
  coalesce(sum(CASE WHEN w.is_personal = 0 AND EXISTS (
      SELECT 1 FROM word_pack_items other
      WHERE other.word_id = w.id AND other.pack_id <> ?
    ) THEN 1 ELSE 0 END), 0) AS shared_other,
  coalesce(sum(CASE WHEN w.is_personal = 0
    AND NOT EXISTS (
      SELECT 1 FROM word_pack_items other
      WHERE other.word_id = w.id AND other.pack_id <> ?
    )
    AND NOT EXISTS (SELECT 1 FROM review_logs rl WHERE rl.word_id = w.id)
    AND NOT EXISTS (SELECT 1 FROM review_cards rc WHERE rc.word_id = w.id)
    AND NOT EXISTS (SELECT 1 FROM study_session_items si WHERE si.word_id = w.id)
    THEN 1 ELSE 0 END), 0) AS removable_unlearned,
  coalesce(sum(CASE WHEN w.is_personal = 0
    AND NOT EXISTS (
      SELECT 1 FROM word_pack_items other
      WHERE other.word_id = w.id AND other.pack_id <> ?
    )
    AND (
      EXISTS (SELECT 1 FROM review_logs rl WHERE rl.word_id = w.id)
      OR EXISTS (SELECT 1 FROM review_cards rc WHERE rc.word_id = w.id)
      OR EXISTS (SELECT 1 FROM study_session_items si WHERE si.word_id = w.id)
    )
    THEN 1 ELSE 0 END), 0) AS learned_only
FROM word_pack_items pi
JOIN words w ON w.id = pi.word_id
WHERE pi.pack_id = ?''';

/// 词书包数据访问入口。
class WordPackDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 读取全部已安装词书及其学习进度聚合。
  Future<List<InstalledWordPackSummary>> listInstalled() async {
    final rows = await _db.customSelect('''
SELECT
  p.id, p.slug, p.name, p.category, p.description, p.version,
  p.content_mode, p.include_in_daily_study, p.installed_at,
  count(pi.word_id) AS total_words,
  coalesce(sum(CASE WHEN w.mastery_level = 'MASTERED' THEN 1 ELSE 0 END), 0)
    AS mastered_words,
  coalesce(sum(CASE WHEN w.mastery_level IN ('LEARNING', 'FAMILIAR', 'PROFICIENT')
    THEN 1 ELSE 0 END), 0) AS learning_words,
  coalesce(sum(CASE WHEN w.initialization_status = 'READY' THEN 1 ELSE 0 END), 0)
    AS ready_words,
  coalesce(sum(CASE WHEN w.initialization_status = 'PARTIAL' THEN 1 ELSE 0 END), 0)
    AS partial_words,
  coalesce(sum(CASE WHEN w.initialization_status NOT IN ('READY', 'PARTIAL')
    THEN 1 ELSE 0 END), 0) AS pending_words
FROM word_packs p
LEFT JOIN word_pack_items pi ON pi.pack_id = p.id
LEFT JOIN words w ON w.id = pi.word_id
GROUP BY p.id
ORDER BY p.installed_at DESC, p.name ASC''').get();
    return rows.map(_mapSummary).toList(growable: false);
  }

  /// 按 ID 读取单本已安装词书，不存在返回 `null`。
  Future<InstalledWordPackSummary?> findById(String packId) async {
    final all = await listInstalled();
    for (final pack in all) {
      if (pack.id == packId) return pack;
    }
    return null;
  }

  /// 切换词书是否纳入「今日每日学习计划」。
  Future<void> setIncludeInDailyStudy(
    String packId, {
    required bool enabled,
    required int now,
  }) async {
    await _db.customUpdate(
      'UPDATE word_packs SET include_in_daily_study = ?, updated_at = ? '
      'WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<int>(enabled ? 1 : 0),
        Variable<int>(now),
        Variable<String>(packId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.wordPacks},
    );
  }

  /// 将指定词条收入「个人词库」（幂等设为 `is_personal = 1`）。
  Future<void> promoteToPersonal(int wordId, {required int now}) async {
    await _db.customUpdate(
      'UPDATE words SET is_personal = 1, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[Variable<int>(now), Variable<int>(wordId)],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.words},
    );
  }

  /// 批量查询词条归属的词书名称（避免列表页 N+1 查询）。
  Future<Map<int, List<String>>> packNamesByWordIds(List<int> wordIds) async {
    if (wordIds.isEmpty) return const <int, List<String>>{};
    final result = <int, List<String>>{};
    for (var start = 0; start < wordIds.length; start += sqlBatchChunkSize) {
      final chunk = wordIds.sublist(
        start,
        math.min(start + sqlBatchChunkSize, wordIds.length),
      );
      final placeholders = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _db
          .customSelect(
            '''
SELECT pi.word_id, p.name
FROM word_pack_items pi
JOIN word_packs p ON p.id = pi.pack_id
WHERE pi.word_id IN ($placeholders)
ORDER BY p.installed_at DESC, p.name ASC''',
            variables: <Variable<Object>>[...chunk.map(Variable<int>.new)],
          )
          .get();
      for (final row in rows) {
        final wordId = row.read<int>('word_id');
        result
            .putIfAbsent(wordId, () => <String>[])
            .add(row.read<String>('name'));
      }
    }
    return result;
  }

  /// 查询某词书尚未完全 `READY` 的下一批待学词条 ID（按词书 `rank` 顺序）。
  Future<List<int>> findEnrichableWordIds(
    String packId, {
    required int limit,
  }) async {
    final rows = await _db
        .customSelect(
          '''
SELECT w.id
FROM word_pack_items pi
JOIN words w ON w.id = pi.word_id
LEFT JOIN review_cards rc ON rc.word_id = w.id
WHERE pi.pack_id = ?
  AND w.is_suspended = 0
  AND w.initialization_status <> 'READY'
ORDER BY CASE WHEN rc.word_id IS NULL THEN 0 ELSE 1 END ASC,
         pi.rank ASC, w.id ASC
LIMIT ?''',
          variables: <Variable<Object>>[
            Variable<String>(packId),
            Variable<int>(limit),
          ],
        )
        .get();
    return <int>[for (final row in rows) row.read<int>('id')];
  }

  /// 计算卸载一本词书前的精确词条影响。
  Future<WordPackUninstallImpact?> inspectUninstallImpact(String packId) async {
    final meta = await _db
        .customSelect(
          'SELECT name FROM word_packs WHERE id = ? LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(packId)],
        )
        .getSingleOrNull();
    if (meta == null) return null;
    final packVar = Variable<String>(packId);
    final row = await _db
        .customSelect(
          _uninstallImpactSql,
          variables: <Variable<Object>>[packVar, packVar, packVar, packVar],
        )
        .getSingle();
    return WordPackUninstallImpact(
      packId: packId,
      packName: meta.read<String>('name'),
      totalWords: row.read<int>('total_words'),
      personalKeptCount: row.read<int>('personal_kept'),
      sharedOtherPackCount: row.read<int>('shared_other'),
      removableUnlearnedCount: row.read<int>('removable_unlearned'),
      learnedOnlyInPackCount: row.read<int>('learned_only'),
    );
  }

  InstalledWordPackSummary _mapSummary(QueryRow row) =>
      InstalledWordPackSummary(
        id: row.read<String>('id'),
        slug: row.read<String>('slug'),
        name: row.read<String>('name'),
        category: WordPackCategory.fromWire(row.read<String>('category')),
        description: row.read<String>('description'),
        version: row.read<String>('version'),
        contentMode: WordPackContentMode.fromWire(
          row.read<String>('content_mode'),
        ),
        includeInDailyStudy: row.read<int>('include_in_daily_study') != 0,
        installedAt: row.read<int>('installed_at'),
        totalWords: row.read<int>('total_words'),
        masteredWords: row.read<int>('mastered_words'),
        learningWords: row.read<int>('learning_words'),
        readyWords: row.read<int>('ready_words'),
        partialWords: row.read<int>('partial_words'),
        pendingWords: row.read<int>('pending_words'),
      );
}
