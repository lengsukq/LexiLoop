/// 词书包元信息与词条归属关联表（Schema v2 新增）。
///
/// 词书包与个人词库共用唯一词条主表 `words`（以归一化词形 + 语向唯一），
/// 通过 `words.is_personal` + `word_pack_items` 多对多关联实现：
/// - 同一词条可同时属于个人词库与多本词书，共享同一套 FSRS 复习进度；
/// - 卸载词书时精确识别个人词、其他词书共享词、以及可清理的未学词条。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/tables/word_tables.dart';

/// 已安装的词书包。
@DataClassName('WordPackRow')
class WordPacks extends Table {
  @override
  String get tableName => 'word_packs';

  /// 稳定词书 ID（如 `cet4`、`ielts`、`oxford-3000`）。
  TextColumn get id => text()();

  /// URL/路由友好的唯一短名。
  TextColumn get slug => text().unique()();

  /// 面向用户展示的词书名称。
  TextColumn get name => text()();

  /// 词书分类（`FOUNDATION` / `EXAM_CN` / `EXAM_INTL` / `CUSTOM`）。
  TextColumn get category => text().withDefault(const Constant('CUSTOM'))();

  /// 简介。
  TextColumn get description => text().withDefault(const Constant(''))();

  /// 词书数据版本号（如 `2026.1`）。
  TextColumn get version => text()();

  /// 载荷预初始化等级（`FULL_YOUDAO` / `ECDICT_BASE` / `WORDLIST_ONLY`）。
  TextColumn get contentMode =>
      text().withDefault(const Constant('ECDICT_BASE'))();

  /// 词书声明的词条数量。
  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  /// 是否纳入「今日每日学习计划」。默认关闭，不打扰个人生词节奏。
  BoolColumn get includeInDailyStudy =>
      boolean().withDefault(const Constant(false))();

  /// 词书包原始文件的 SHA-256 校验值。
  TextColumn get sha256 => text().withDefault(const Constant(''))();

  /// 下载来源地址（本地导入时为 `null`）。
  TextColumn get sourceUrl => text().nullable()();

  /// 安装时间戳（epoch 毫秒）。
  IntColumn get installedAt => integer()();

  /// 最近更新时间戳（epoch 毫秒）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 词书包与词条的多对多归属关系。
@DataClassName('WordPackItemRow')
class WordPackItems extends Table {
  @override
  String get tableName => 'word_pack_items';

  /// 所属词书 ID（删除词书时级联清理归属关系）。
  TextColumn get packId =>
      text().references(WordPacks, #id, onDelete: KeyAction.cascade)();

  /// 词条 ID（删除词条时级联清理归属关系）。
  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();

  /// 词书内部排序号（按词频或官方考纲顺序，从 1 起）。
  IntColumn get rank => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{packId, wordId};
}
