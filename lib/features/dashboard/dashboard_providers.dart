/// 仪表盘的数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/study_models.dart';

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
