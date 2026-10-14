/// 词条列表的状态与数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/backup_service.dart';

/// 每页条数。
const int wordPageSize = 40;

/// 词条查询数据源。
final Provider<WordDao> wordDaoProvider = Provider<WordDao>(
  (ref) => WordDao(ref.watch(databaseProvider)),
);

/// 备份导入服务。
final Provider<BackupService> backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(BackupImporter(ref.watch(databaseProvider))),
);

/// 当前列表的查询条件。
class WordQueryNotifier extends Notifier<WordQuery> {
  @override
  WordQuery build() => const WordQuery();

  /// 更新关键词搜索，并回到第一页。
  void setSearch(String search) {
    state = WordQuery(
      search: search,
      masteryLevel: state.masteryLevel,
      initializationStatus: state.initializationStatus,
      limit: state.limit,
    );
  }

  /// 切换掌握等级筛选（传 `null` 表示不筛选）。
  void setMasteryLevel(MasteryLevel? level) {
    state = WordQuery(
      search: state.search,
      masteryLevel: level,
      initializationStatus: state.initializationStatus,
      limit: state.limit,
    );
  }

  /// 切换初始化状态筛选（传 `null` 表示不筛选）。
  void setInitializationStatus(InitializationStatus? status) {
    state = WordQuery(
      search: state.search,
      masteryLevel: state.masteryLevel,
      initializationStatus: status,
      limit: state.limit,
    );
  }

  /// 翻到指定页（0 起）。
  void goToPage(int page) {
    state = WordQuery(
      search: state.search,
      masteryLevel: state.masteryLevel,
      initializationStatus: state.initializationStatus,
      limit: state.limit,
      offset: page * state.limit,
    );
  }
}

/// 查询条件提供者。
final NotifierProvider<WordQueryNotifier, WordQuery> wordQueryProvider =
    NotifierProvider<WordQueryNotifier, WordQuery>(WordQueryNotifier.new);

/// 当前页的词条列表。
final FutureProvider<List<WordListEntry>> wordListProvider =
    FutureProvider<List<WordListEntry>>((ref) {
      final query = ref.watch(wordQueryProvider);
      return ref.watch(wordDaoProvider).list(query);
    });

/// 符合当前筛选条件的词条总数。
final FutureProvider<int> wordCountProvider = FutureProvider<int>((ref) {
  final query = ref.watch(wordQueryProvider);
  return ref.watch(wordDaoProvider).count(query);
});

/// 按掌握等级的词条分布。
final FutureProvider<Map<MasteryLevel, int>> masterySummaryProvider =
    FutureProvider<Map<MasteryLevel, int>>(
      (ref) => ref.watch(wordDaoProvider).countByMastery(),
    );
