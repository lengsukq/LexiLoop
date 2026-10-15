/// 学习计划设置分组。
///
/// 三项每日配额 + 目标保持率。配额上限取自 `core/constants.dart`，
/// 界面不再自己写一遍数字。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';

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
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      children: <Widget>[
        SettingsSectionCard(
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
        ),
        const SizedBox(height: 12),
        SettingsSectionCard(
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
        ),
      ],
    );
  }
}

/// 保持率滑条的刻度数：按 0.01 一档。
final int _retentionSteps = ((maxRetentionRate - minRetentionRate) * 100)
    .round();
