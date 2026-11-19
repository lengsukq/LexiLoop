/// 学习计划设置分组。
///
/// 三项每日配额 + 目标保持率 + AI 重试遍数。配额上限取自
/// `core/constants.dart`，界面不再自己写一遍数字。
///
/// **为什么拆成三个私有卡片而不是一个 ListView**：分组信息（标题与说明）
/// 与控件是绑在一起的，拆开后 `build()` 只剩排版，滑条行也就能各自复用
/// `SettingsSliderRow` 而不必在一棵 80 行的树里排版。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/lexi_form_rows.dart';

/// 学习计划分组。
class StudyPlanSection extends ConsumerWidget {
  /// 以当前设置构造。
  const new({required this.settings, super.key});

  /// 当前设置。
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = settings.studyPlan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s4,
        LexiSpace.s12,
        LexiSpace.s4,
        LexiSpace.s24,
      ),
      children: <Widget>[
        _DailyQuotaCard(plan: plan),
        const SizedBox(height: LexiSpace.s12),
        _RetentionCard(plan: plan),
        const SizedBox(height: LexiSpace.s12),
        _AiRetryCard(plan: plan),
      ],
    );
  }
}

/// 每日配额卡片。
class _DailyQuotaCard extends ConsumerWidget {
  const new({required this.plan});

  final StudyPlanSettings plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSectionCard(
      title: '每日配额',
      subtitle: '配额决定每日队列的上限，不是必须完成的指标。',
      child: Column(
        children: <Widget>[
          SettingsSliderRow(
            key: const Key('studyPlanDailyNewWords'),
            label: '每日新词',
            valueText: '${plan.dailyNewWords} 个',
            value: plan.dailyNewWords.toDouble(),
            min: 0,
            max: maxDailyNewWords.toDouble(),
            divisions: maxDailyNewWords,
            onChangeEnd: (value) => saveSettings(ref, <String, Object?>{
              'dailyNewWords': value.round(),
            }),
          ),
          SettingsSliderRow(
            key: const Key('studyPlanDailyWrongWords'),
            label: '每日错词',
            valueText: '${plan.dailyWrongWordLimit} 个',
            value: plan.dailyWrongWordLimit.toDouble(),
            min: 0,
            max: maxDailyWrongWordLimit.toDouble(),
            divisions: maxDailyWrongWordLimit,
            onChangeEnd: (value) => saveSettings(ref, <String, Object?>{
              'dailyWrongWordLimit': value.round(),
            }),
          ),
          SettingsSliderRow(
            key: const Key('studyPlanDailyDueReview'),
            label: '每日到期复习',
            valueText: '${plan.dailyDueReviewLimit} 个',
            value: plan.dailyDueReviewLimit.toDouble(),
            min: 1,
            max: maxDailyDueReviewLimit.toDouble(),
            divisions: maxDailyDueReviewLimit - 1,
            onChangeEnd: (value) => saveSettings(ref, <String, Object?>{
              'dailyDueReviewLimit': value.round(),
            }),
          ),
        ],
      ),
    );
  }
}

/// 目标保持率卡片。
class _RetentionCard extends ConsumerWidget {
  const new({required this.plan});

  final StudyPlanSettings plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSectionCard(
      title: '目标保持率',
      subtitle: 'FSRS 按这个保持率安排复习间隔：越高越密集，越低越省时间。',
      child: SettingsSliderRow(
        key: const Key('studyPlanRetention'),
        label: '目标保持率',
        valueText: '${(plan.targetRetentionRate * 100).round()}%',
        value: plan.targetRetentionRate,
        min: minRetentionRate,
        max: maxRetentionRate,
        divisions: _retentionSteps,
        onChangeEnd: (value) => saveSettings(ref, <String, Object?>{
          'targetRetentionRate': double.parse(value.toStringAsFixed(2)),
        }),
      ),
    );
  }
}

/// AI 重试遍数卡片。
class _AiRetryCard extends ConsumerWidget {
  const new({required this.plan});

  final StudyPlanSettings plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSectionCard(
      title: 'AI 重试遍数',
      subtitle: _aiRetryExplanation,
      child: SettingsSliderRow(
        key: const Key('studyPlanAiRetryCount'),
        label: 'AI 重试遍数',
        valueText: '${plan.aiRetryCount} 遍',
        value: plan.aiRetryCount.toDouble(),
        min: aiRetryCountFloor.toDouble(),
        max: aiRetryCountCeiling.toDouble(),
        divisions: aiRetryCountCeiling - aiRetryCountFloor,
        onChangeEnd: (value) =>
            saveSettings(ref, <String, Object?>{'aiRetryCount': value.round()}),
      ),
    );
  }
}

/// AI 重试遍数的说明文案。
///
/// **为什么必须写清楚「遍」而不是「次」**：这里的重试单位是**整条候选链**
/// （主模型 → 备用模型 → 备用提供方）重放一遍，不是单个模型重试一次。
/// 写成「失败重试 3 次」会让用户以为请求数变成 4 倍，实际是最多 3 遍、
/// 每遍按三层降级依次尝试。
const String _aiRetryExplanation =
    'AI 任务失败时把整条候选链（主模型 → 备用模型 → 备用提供方）重放几遍 '
    '（1 遍就是只跑一次、失败即放弃），网络不稳时可调高，但每遍都要真实计费。 '
    '作用于词典补全、例句翻译、助记与每日建议； 0 与 1 效果相同，候选链至少跑一遍。';

/// 保持率滑条的刻度数：按 0.01 一档。
final int _retentionSteps = ((maxRetentionRate - minRetentionRate) * 100)
    .round();
