/// 数据检查点的查询。
///
/// **为什么需要它**：自动备份按周期醒来，但「周期到了」不等于「值得再传一份」。
/// 一份 27MB 的备份天天上传，内容却和昨天完全一样，是纯粹的浪费。
/// 检查点用两个极便宜的聚合值回答「库里的学习数据变了没有」。
///
/// **为什么用 `review_logs.created_at` 的最大值**：它是**只增不改**的作答流水，
/// 每次作答都会追加一行，因此最大值变化 ⟺ 有新作答。不选 `words.updated_at`：
/// 该列只在词条本身被改时更新，改一次学习进度并不会动它。
///
/// **为什么还要带上词条数**：只比作答时间的话，导入/删除词条
/// （没有产生作答）不会让检查点变化，于是自动备份会漏掉这批变化。
library;

import 'package:lexiloop/data/db/database.dart';

/// 学习数据的检查点。
///
/// 用记录类型而不是自定义类：它只是两个数字的临时组合，
/// 不参与序列化，也不该有行为。
typedef DataCheckpoint = ({int lastReviewAt, int wordCount});

/// 数据检查点查询。
class BackupCheckpointDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 读取当前检查点。
  ///
  /// 两条聚合都是一次全表扫描的元数据查询（SQLite 对 `MAX`/`COUNT`
  /// 走索引或行计数），比导出整份备份便宜若干个数量级。
  Future<DataCheckpoint> current() async {
    final reviewRow = await _db
        .customSelect('SELECT MAX(created_at) AS latest FROM review_logs')
        .getSingle();
    final wordRow = await _db
        .customSelect('SELECT COUNT(*) AS total FROM words')
        .getSingle();
    return (
      lastReviewAt: reviewRow.read<int?>('latest') ?? 0,
      wordCount: wordRow.read<int>('total'),
    );
  }
}

/// 把检查点写成可比较、可持久化的字符串。
///
/// 形如 `1792069100000:1417`。选字符串而不是结构体：它被写进
/// `settings` 表的 JSON 值里，字符串的比较与往返都不会有精度问题。
String checkpointWire(DataCheckpoint checkpoint) =>
    '${checkpoint.lastReviewAt}:${checkpoint.wordCount}';
