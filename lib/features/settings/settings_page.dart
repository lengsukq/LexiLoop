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
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_states.dart';

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
          error: (error, _) => PageErrorState(
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
          const Padding(
            padding: EdgeInsets.fromLTRB(
              LexiSpace.s20,
              LexiSpace.s16,
              LexiSpace.s20,
              LexiSpace.s10,
            ),
            // 副标题此前是「所有改动即时生效，无需保存」——一句应用无法
            // 兑现的承诺：写库可能失败，而失败在收敛前是静默的。
            // 现在失败会弹提示并让开关回弹（见 `settings_providers.dart`
            // 的 `saveSettings`），所以这句可以老实换成「这一页能做什么」。
            child: PageHeader(
              title: '设置',
              subtitle: '逐项改动即时保存；保存失败会提示，并把开关恢复原值。',
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: colors.accent,
            unselectedLabelColor: colors.secondaryLabel,
            indicatorColor: colors.accent,
            tabs: <Widget>[for (final label in _tabLabels) Tab(text: label)],
          ),
          // **设置页收窄到一列**：整页铺满 1040 时，每张卡片右侧都有一半
          // 是空的，而控件（滑条、开关）只占左侧一小段——卡片看起来像没画完。
          // 表单类页面本来就不该铺满宽屏。
          // 左对齐而不是居中：这样内容左缘与上方的 tab 条对齐。
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LexiLayout.readingMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LexiSpace.s16,
                  ),
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
            ),
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
