/// 题型设置分组。
///
/// 8 种题型按「看词认义 / 拼写输出 / 听力训练 / 语境运用」分 4 组展示，
/// 每组一个子卡片，内含各题型的开关、权重滑条与权重占比。
/// 顶部是 4 个权重预设（旧版 `question-type-settings.tsx:31-36`）、
/// 一条 100% 占比条与「重置均衡」。
///
/// **「至少启用一种」在界面层提前拦截**：`QuestionTypeConfig.normalized`
/// 会在全部关闭时整体回退到默认配置，但那是兜底——如果界面允许用户把
/// 最后一个开关关掉再默默恢复默认，用户会看到「我关掉的又自己开了」。
/// 因此这里直接拒绝保存并给出提示。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 题型分组。
class QuestionTypeSection extends ConsumerStatefulWidget {
  /// 以当前设置构造。
  const new({required this.settings, super.key});

  /// 当前设置。
  final AppSettings settings;

  @override
  ConsumerState<QuestionTypeSection> createState() =>
      _QuestionTypeSectionState();
}

class _QuestionTypeSectionState extends ConsumerState<QuestionTypeSection> {
  late Map<QuestionType, QuestionTypeSetting> _draft = _draftOf(
    widget.settings,
  );

  /// 上一次操作是否因为「全部关闭」被拒绝。
  bool _blocked = false;

  @override
  void didUpdateWidget(QuestionTypeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 设置被外部改写（如恢复默认、备份导入）时同步草稿。
    if (!_sameConfig(oldWidget.settings, widget.settings)) {
      _draft = _draftOf(widget.settings);
      _blocked = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final config = QuestionTypeConfig(_draft);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s4,
        LexiSpace.s12,
        LexiSpace.s4,
        LexiSpace.s24,
      ),
      children: <Widget>[
        if (_blocked) ...<Widget>[
          SettingsNotice(
            key: const Key('questionTypeBlockedNotice'),
            message: '至少要启用一种题型，否则学习时会抽不出题目。本次改动未保存。',
            color: colors.danger,
          ),
          const SizedBox(height: LexiSpace.s12),
        ],
        SettingsSectionCard(
          title: '题型开关与权重',
          subtitle: '权重决定该题型被抽中的相对概率；色条是各题型当前的实际占比。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _PresetBar(onApply: _applyPreset, onReset: _resetBalanced),
              const SizedBox(height: LexiSpace.s12),
              _ShareBar(config: config),
              const SizedBox(height: LexiSpace.s12),
              for (final group in _typeGroups)
                _TypeGroupCard(
                  group: group,
                  config: config,
                  onToggle: _toggle,
                  onWeightEnd: _setWeight,
                ),
              const SizedBox(height: LexiSpace.s2),
              Text(
                _availabilityHint,
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggle(QuestionType type, {required bool enabled}) {
    final next = Map<QuestionType, QuestionTypeSetting>.of(_draft);
    final current = next[type] ?? defaultQuestionTypeSetting;
    next[type] = QuestionTypeSetting(enabled: enabled, weight: current.weight);

    final config = QuestionTypeConfig(next);
    if (!config.hasEnabledType) {
      setState(() => _blocked = true);
      return;
    }
    _commit(config);
  }

  void _setWeight(QuestionType type, double weight) {
    final next = Map<QuestionType, QuestionTypeSetting>.of(_draft);
    final current = next[type] ?? defaultQuestionTypeSetting;
    next[type] = QuestionTypeSetting(
      enabled: current.enabled,
      weight: weight.round(),
    );
    _commit(QuestionTypeConfig(next));
  }

  void _applyPreset(QuestionTypeWeightPreset preset) {
    _commit(preset.applyTo(QuestionTypeConfig(_draft)));
  }

  void _resetBalanced() {
    // 「重置均衡」比「均衡」预设多一步：它还把被关掉的题型重新打开。
    // 用户能按的按钮只有一个，就该是那个真正回到出厂状态的。
    _commit(QuestionTypeConfig.defaults);
  }

  void _commit(QuestionTypeConfig config) {
    setState(() {
      _draft = _draftOfConfig(config);
      _blocked = false;
    });
    _persist(config);
  }

  void _persist(QuestionTypeConfig config) {
    unawaited(
      saveSettings(ref, <String, Object?>{
        'questionTypeConfig': config.normalized.toJson(),
      }),
    );
  }
}

/// 预设按钮行：4 个预设 + 「重置均衡」。
class _PresetBar extends StatelessWidget {
  const new({required this.onApply, required this.onReset});

  final void Function(QuestionTypeWeightPreset preset) onApply;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final preset in questionTypeWeightPresets)
                ActionChip(
                  key: Key('questionTypePreset-${preset.id}'),
                  label: Text(preset.label),
                  onPressed: () => onApply(preset),
                ),
            ],
          ),
        ),
        const SizedBox(width: LexiSpace.s8),
        OutlinedButton.icon(
          key: const Key('questionTypeResetBalanced'),
          onPressed: onReset,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text('重置均衡'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.secondaryLabel,
            side: BorderSide(color: colors.borderDefault),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

/// 权重占比总览条：各启用题型按占比切分，合计 100%。
class _ShareBar extends StatelessWidget {
  const new({required this.config});

  final QuestionTypeConfig config;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final shares = config.sharePercents();

    return ClipRRect(
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: SizedBox(
        height: LexiSpace.s8,
        child: Row(
          // 必须 stretch：`ColoredBox` 没有子节点，默认的 center 会把它量成 0 高。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final type in QuestionType.values)
              if (config.sharePercentOf(type) > 0)
                Expanded(
                  flex: _flexOf(shares[type.index]),
                  child: ColoredBox(color: questionTypeColor(colors, type)),
                ),
          ],
        ),
      ),
    );
  }
}

/// 百分比换算成 `Expanded.flex`。
///
/// **为什么乘 100**：`flex` 是整数，2% 与 2.4% 都会截断成 2，8 个题型各截一次
/// 足以让色条明显短于轨道；放大 100 倍后误差落在 1/100 百分比以下，
/// 肉眼与截图都看不出来。
int _flexOf(double percent) => (percent * 100).round().clamp(1, _flexCeiling);

/// `flex` 上限：防止某个题型独占时把其余段挤成 0 宽。
const int _flexCeiling = 100000;

/// 一个题型分组。
class _TypeGroupCard extends StatelessWidget {
  const new({
    required this.group,
    required this.config,
    required this.onToggle,
    required this.onWeightEnd,
  });

  final _TypeGroup group;
  final QuestionTypeConfig config;
  final void Function(QuestionType type, {required bool enabled}) onToggle;
  final void Function(QuestionType type, double weight) onWeightEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final enabledCount = group.types.where(config.isEnabled).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                group.label,
                style: LexiType.footnote.copyWith(
                  color: colors.secondaryLabel,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$enabledCount/${group.types.length} 已启用',
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
            ],
          ),
          for (final type in group.types)
            _QuestionTypeRow(
              type: type,
              config: config,
              onToggle: onToggle,
              onWeightEnd: onWeightEnd,
            ),
        ],
      ),
    );
  }
}

class _QuestionTypeRow extends StatelessWidget {
  const new({
    required this.type,
    required this.config,
    required this.onToggle,
    required this.onWeightEnd,
  });

  final QuestionType type;
  final QuestionTypeConfig config;
  final void Function(QuestionType type, {required bool enabled}) onToggle;
  final void Function(QuestionType type, double weight) onWeightEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final enabled = config.isEnabled(type);
    final share = config.sharePercentOf(type).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: questionTypeColor(colors, type),
                  borderRadius: BorderRadius.circular(LexiRadius.pill),
                ),
              ),
              const SizedBox(width: LexiSpace.s6),
              Expanded(
                child: Text(
                  questionTypeLabel(type),
                  style: LexiType.body.copyWith(
                    color: enabled ? colors.label : colors.tertiaryLabel,
                  ),
                ),
              ),
              Text(
                enabled ? '$share%' : '未启用',
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
              Switch(
                key: Key('questionTypeSwitch-${type.wire}'),
                value: enabled,
                onChanged: (value) => onToggle(type, enabled: value),
              ),
            ],
          ),
          Text(
            questionTypeHint(type),
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
          SettingsSliderRow(
            key: Key('questionTypeWeight-${type.wire}'),
            label: '权重',
            value: config.weightOf(type),
            min: minQuestionTypeWeight.toDouble(),
            max: maxQuestionTypeWeight.toDouble(),
            divisions: maxQuestionTypeWeight - minQuestionTypeWeight,
            onChangeEnd: (value) => onWeightEnd(type, value),
          ),
        ],
      ),
    );
  }
}

/// 一个题型分组。
class _TypeGroup {
  const new({required this.label, required this.types});

  final String label;
  final List<QuestionType> types;
}

/// 分组顺序取自旧版 `question-type-settings.tsx:129-138` 的 `GROUPS`：
/// 按「认词 → 输出 → 听辨 → 语境」的学习顺序，而不是按枚举顺序。
const List<_TypeGroup> _typeGroups = <_TypeGroup>[
  _TypeGroup(
    label: '看词认义',
    types: <QuestionType>[
      QuestionType.enToZh,
      QuestionType.enToZhChoice,
      QuestionType.zhToEnChoice,
    ],
  ),
  _TypeGroup(
    label: '拼写输出',
    types: <QuestionType>[QuestionType.zhToEnSpelling, QuestionType.letterBank],
  ),
  _TypeGroup(
    label: '听力训练',
    types: <QuestionType>[
      QuestionType.listeningChoice,
      QuestionType.listeningSpelling,
    ],
  ),
  _TypeGroup(label: '语境运用', types: <QuestionType>[QuestionType.clozeSentence]),
];

/// 题型可用性提示：两类题型有前置条件，用户不设预期会以为设置没生效。
const String _availabilityHint =
    '完形填空需要例句，字母拼词仅对 3–14 个纯字母的单词生效； '
    '词条不满足条件时会自动改用同组其他题型。';

Map<QuestionType, QuestionTypeSetting> _draftOf(AppSettings settings) =>
    _draftOfConfig(settings.questionTypeConfig);

Map<QuestionType, QuestionTypeSetting> _draftOfConfig(
  QuestionTypeConfig config,
) => <QuestionType, QuestionTypeSetting>{
  for (final type in QuestionType.values)
    type: QuestionTypeSetting(
      enabled: config.isEnabled(type),
      weight: config.weightOf(type).round(),
    ),
};

/// 两份设置里的题型配置是否等价（按序列化结果比对，避免实例身份比较）。
bool _sameConfig(AppSettings oldSettings, AppSettings newSettings) {
  final before = oldSettings.questionTypeConfig.toJson();
  final after = newSettings.questionTypeConfig.toJson();
  if (before.length != after.length) return false;
  for (final entry in before.entries) {
    final left = entry.value;
    final right = after[entry.key];
    if (left is! Map || right is! Map) return false;
    if (left['enabled'] != right['enabled'] ||
        left['weight'] != right['weight']) {
      return false;
    }
  }
  return true;
}

/// 题型的中文名。
String questionTypeLabel(QuestionType type) => switch (type) {
  QuestionType.enToZh => '英译中（自评）',
  QuestionType.enToZhChoice => '英译中（选择）',
  QuestionType.zhToEnChoice => '中译英（选择）',
  QuestionType.zhToEnSpelling => '中译英（拼写）',
  QuestionType.listeningSpelling => '听音拼写',
  QuestionType.clozeSentence => '例句填空',
  QuestionType.listeningChoice => '听音选择',
  QuestionType.letterBank => '字母拼词',
};

/// 题型的适用条件说明。
///
/// 前两种题型有硬性前置条件（需要例句 / 需要纯字母词），不说清楚用户会
/// 以为「开了却一道都没抽到」是 bug。
String questionTypeHint(QuestionType type) => switch (type) {
  QuestionType.enToZh => '看英文判断是否认识',
  QuestionType.enToZhChoice => '看英文选释义',
  QuestionType.zhToEnChoice => '看释义选英文',
  QuestionType.zhToEnSpelling => '看释义拼写英文',
  QuestionType.listeningSpelling => '听发音拼写',
  QuestionType.clozeSentence => '例句挖空，需要词条带例句',
  QuestionType.listeningChoice => '听发音选词',
  QuestionType.letterBank => '打乱字母拼回，仅限 3–14 个纯字母',
};

/// 题型在占比条与圆点上的颜色。
///
/// **为什么按枚举下标轮转色相而不是写死 8 个色值**：旧版在组件里写死了 8 个
/// hex（`SEG_COLORS`），换主题时这套色板不会跟着变。以 `accent` 的色相为起点
/// 均匀轮转，明暗两套色板都能拿到对比度合适的颜色，且新增题型不用补色值。
Color questionTypeColor(LexiColors colors, QuestionType type) {
  final base = HSVColor.fromColor(colors.accent);
  final step = hueSpan / QuestionType.values.length;
  return HSVColor.fromAHSV(
    1,
    (base.hue + type.index * step) % hueSpan,
    base.saturation,
    base.value,
  ).toColor();
}

/// 一整圈色相（度）。
const double hueSpan = 360;
