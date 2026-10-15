/// 仪表盘的数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/suggestion_service.dart';

/// 仪表盘使用的「现在」。
///
/// 抽成提供者是为了可测：测试覆写它之后，「今日到期」「今日已答」
/// 「连续天数」这些与时钟相关的断言才能稳定复现，而不必迁就真实时间。
final Provider<int> dashboardNowProvider = Provider<int>(
  (ref) => DateTime.now().millisecondsSinceEpoch,
);

/// 今日学习计划（到期复习 / 错词 / 新词的计划数与可用数、预估耗时）。
final FutureProvider<DailyStudyPlan> dailyPlanProvider =
    FutureProvider<DailyStudyPlan>(
      (ref) => ref
          .watch(studyServiceProvider)
          .dailyPlan(now: ref.watch(dashboardNowProvider)),
    );

/// 全局概览（总词数、掌握分布、到期、错词、今日已答、连续天数、新词）。
///
/// 这里直接构造 [WordDetailDao] 而不再包一层提供者：详情页已经有一个
/// 同类型提供者，若从那边取会形成「详情 ↔ 仪表盘」的相互依赖；
/// DAO 本身无状态且构造是 `const`，直接构造没有额外成本。
final FutureProvider<DashboardOverview> dashboardOverviewProvider =
    FutureProvider<DashboardOverview>(
      (ref) =>
          WordDetailDao(ref.watch(databaseProvider))
              .overview(ref.watch(dashboardNowProvider)),
    );

/// 每日建议服务的提供者。
final Provider<SuggestionService> suggestionServiceProvider =
    Provider<SuggestionService>(
      (ref) => SuggestionService(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
      ),
    );

/// 今日建议。
///
/// 读不到当天建议时**由服务自己生成并落库**（`SuggestionService.today`），
/// 因此界面不需要区分「已有」与「首次生成」两条路径。
final AsyncNotifierProvider<DailySuggestionController, DailySuggestion?>
dailySuggestionProvider =
    AsyncNotifierProvider<DailySuggestionController, DailySuggestion?>(
      DailySuggestionController.new,
    );

/// 今日建议的加载与重新生成。
class DailySuggestionController extends AsyncNotifier<DailySuggestion?> {
  @override
  Future<DailySuggestion?> build() => ref
      .watch(suggestionServiceProvider)
      .today(now: ref.watch(dashboardNowProvider));

  /// 重新生成（用户主动触发，会走一次 AI 调用）。
  Future<void> regenerate() async {
    state = const AsyncValue<DailySuggestion?>.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(suggestionServiceProvider)
          .generate(now: ref.read(dashboardNowProvider)),
    );
  }
}
