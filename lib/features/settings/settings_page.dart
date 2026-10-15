/// 设置页。
///
/// **按 `AppSettings` 的分组拆成 6 个 tab**，每个 tab 一个独立组件文件。
/// 旧版设置页把 13 + 8 个回调 props 一次性传给一个大表单
/// （见 `docs/CLEAN_CODE_BASELINE.md`），任何一处改动都要动整条链路；
/// 这里每个分组只依赖 `appSettingsProvider` 与 `saveSettings`。
///
/// **「AI 模型」不在 `AppSettings` 的分组里**：那份配置刻意只存在于
/// `raw['llmConfig']`，但它仍然是用户必须能改的东西，因此单列一个 tab。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/ai/ai_settings_section.dart';
import 'package:lexiloop/features/settings/data_management_section.dart';
import 'package:lexiloop/features/settings/playback_section.dart';
import 'package:lexiloop/features/settings/providers_section.dart';
import 'package:lexiloop/features/settings/question_type_section.dart';
import 'package:lexiloop/features/settings/study_plan_section.dart';
import 'package:lexiloop/features/settings/vocabulary_section.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/error_retry_view.dart';

/// 设置页。
class SettingsPage extends ConsumerWidget {
  /// 创建设置页。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: settings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorRetryView(
            message: error is AppError ? error.message : '读取设置失败：$error',
            onRetry: () => ref.invalidate(appSettingsProvider),
          ),
          data: (value) => _SettingsTabs(settings: value),
        ),
      ),
    );
  }
}

class _SettingsTabs extends StatelessWidget {
  const new({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return DefaultTabController(
      length: _tabLabels.length,
      child: Column(
        children: <Widget>[
          const _SettingsHeader(),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: colors.accent,
            unselectedLabelColor: colors.secondaryLabel,
            indicatorColor: colors.accent,
            tabs: <Widget>[for (final label in _tabLabels) Tab(text: label)],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s16),
              child: TabBarView(
                children: <Widget>[
                  StudyPlanSection(settings: settings),
                  QuestionTypeSection(settings: settings),
                  PlaybackSection(settings: settings),
                  ProvidersSection(settings: settings),
                  VocabularySection(settings: settings),
                  AiSettingsSection(settings: settings),
                  const DataManagementSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s20,
        LexiSpace.s16,
        LexiSpace.s20,
        LexiSpace.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '设置',
            style: LexiType.page.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: LexiSpace.s4),
          Text(
            '所有改动即时生效，无需保存。',
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ),
    );
  }
}

/// tab 顺序与 `AppSettings` 的分组顺序一致，「AI 模型」紧随词汇设置——
/// 它同样是「与学习内容无关、但用户必须能改」的一组。
const List<String> _tabLabels = <String>[
  '学习计划',
  '题型',
  '播放',
  '数据源',
  '词汇与考试',
  'AI 模型',
  '数据管理',
];
