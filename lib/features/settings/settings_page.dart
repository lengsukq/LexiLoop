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
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_states.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
          data: (value) => _SettingsBody(settings: value),
        ),
      ),
    );
  }
}

/// 分类切换只影响展示，已打开分组保持表单与滚动状态。
class _SettingsBody extends StatefulWidget {
  const new({required this.settings});

  final AppSettings settings;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  int _selected = 0;
  bool _detail = false;
  final Set<int> _visited = <int>{0};

  void _open(int index) => setState(() {
    _selected = index;
    _visited.add(index);
    _detail = true;
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      return PopScope<Object?>(
        canPop: wide || !_detail,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && mounted) setState(() => _detail = false);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: LexiSpace.s16),
                child: PageHeader(
                  title: !wide && _detail ? _tabLabels[_selected] : '设置',
                  leading: !wide && _detail
                      ? IconButton(
                          tooltip: '设置分类',
                          onPressed: () => setState(() => _detail = false),
                          icon: const Icon(LucideIcons.arrowLeft),
                        )
                      : null,
                ),
              ),
              Expanded(child: wide ? _wideContent() : _compactContent()),
            ],
          ),
        ),
      );
    },
  );

  Widget _wideContent() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SizedBox(width: _categoryWidth, child: _categories(wide: true)),
      const SizedBox(width: LexiSpace.s24),
      Expanded(child: _content()),
    ],
  );

  Widget _compactContent() => IndexedStack(
    index: _detail ? 1 : 0,
    children: <Widget>[_categories(wide: false), _content()],
  );

  Widget _categories({required bool wide}) => ListView(
    children: <Widget>[
      for (var index = 0; index < _tabLabels.length; index++)
        ListTile(
          selected: wide && index == _selected,
          selectedTileColor: LexiTone.lavender.background(
            Theme.of(context).brightness,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LexiRadius.md),
          ),
          leading: _CategoryIcon(index: index),
          title: Text(_tabLabels[index], style: LexiType.body),
          trailing: wide ? null : const Icon(LucideIcons.chevronRight),
          onTap: () => _open(index),
        ),
      const SizedBox(height: LexiSpace.s24),
      const DisclosureSection(
        title: '关于词环',
        child: Text(
          'LexiLoop v1.0\n词条与学习记录保存在本机，使用 FSRS 安排复习。',
          style: LexiType.footnote,
        ),
      ),
    ],
  );

  Widget _content() => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: LexiLayout.readingMaxWidth),
      child: IndexedStack(
        index: _selected,
        children: <Widget>[
          for (var index = 0; index < _tabLabels.length; index++)
            if (_visited.contains(index))
              KeyedSubtree(key: ValueKey<int>(index), child: _section(index))
            else
              const SizedBox.shrink(),
        ],
      ),
    ),
  );

  Widget _section(int index) => switch (index) {
    0 => StudyPlanSection(settings: widget.settings),
    1 => QuestionTypeSection(settings: widget.settings),
    2 => PlaybackSection(settings: widget.settings),
    3 => ProvidersSection(settings: widget.settings),
    4 => VocabularySection(settings: widget.settings),
    5 => AiSettingsSection(settings: widget.settings),
    _ => const DataManagementSection(),
  };
}

class _CategoryIcon extends StatelessWidget {
  const new({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = _categorySymbols[index];
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(LexiSpace.s8),
      decoration: BoxDecoration(
        color: tone.background(brightness),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Icon(icon, size: 18, color: tone.foreground(brightness)),
    );
  }
}

const _categorySymbols = <(LexiTone, IconData)>[
  (LexiTone.mint, LucideIcons.calendarDays),
  (LexiTone.sky, LucideIcons.listChecks),
  (LexiTone.peach, LucideIcons.volume2),
  (LexiTone.sky, LucideIcons.bookOpen),
  (LexiTone.lavender, LucideIcons.graduationCap),
  (LexiTone.lavender, LucideIcons.sparkles),
  (LexiTone.peach, LucideIcons.database),
];

const List<String> _tabLabels = <String>[
  '学习计划',
  '题型',
  '播放',
  '数据源',
  '词汇与考试',
  'AI 模型',
  '数据管理',
];

const double _categoryWidth = 190;
