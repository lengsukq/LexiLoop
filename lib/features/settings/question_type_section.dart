/// 题型设置分组。
///
/// 8 种题型各一个开关 + 权重滑条。
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      children: <Widget>[
        if (_blocked) ...<Widget>[
          SettingsNotice(
            key: const Key('questionTypeBlockedNotice'),
            message: '至少要启用一种题型，否则学习时会抽不出题目。本次改动未保存。',
            color: colors.danger,
          ),
          const SizedBox(height: 12),
        ],
        SettingsSectionCard(
          title: '题型开关与权重',
          subtitle: '权重决定该题型被抽中的相对概率；权重 1 与权重 10 的比例是 1:10。',
          child: Column(
            children: <Widget>[
              for (final type in QuestionType.values)
                _QuestionTypeRow(
                  type: type,
                  setting: _draft[type] ?? defaultQuestionTypeSetting,
                  onToggle: (enabled) => _toggle(type, enabled: enabled),
                  onWeightEnd: (weight) => _setWeight(type, weight),
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
    setState(() {
      _draft = next;
      _blocked = false;
    });
    _persist(config);
  }

  void _setWeight(QuestionType type, double weight) {
    final next = Map<QuestionType, QuestionTypeSetting>.of(_draft);
    final current = next[type] ?? defaultQuestionTypeSetting;
    next[type] = QuestionTypeSetting(
      enabled: current.enabled,
      weight: weight.round(),
    );
    setState(() => _draft = next);
    _persist(QuestionTypeConfig(next));
  }

  void _persist(QuestionTypeConfig config) {
    unawaited(
      saveSettings(ref, <String, Object?>{
        'questionTypeConfig': config.normalized.toJson(),
      }),
    );
  }
}

class _QuestionTypeRow extends StatelessWidget {
  const new({
    required this.type,
    required this.setting,
    required this.onToggle,
    required this.onWeightEnd,
  });

  final QuestionType type;
  final QuestionTypeSetting setting;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onWeightEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  questionTypeLabel(type),
                  style: TextStyle(
                    color: setting.enabled
                        ? colors.label
                        : colors.tertiaryLabel,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Switch(
                key: Key('questionTypeSwitch-${type.wire}'),
                value: setting.enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          SettingsSliderRow(
            key: Key('questionTypeWeight-${type.wire}'),
            label: '权重',
            value: setting.weight.toDouble(),
            min: minQuestionTypeWeight.toDouble(),
            max: maxQuestionTypeWeight.toDouble(),
            divisions: maxQuestionTypeWeight - minQuestionTypeWeight,
            onChangeEnd: onWeightEnd,
          ),
        ],
      ),
    );
  }
}

Map<QuestionType, QuestionTypeSetting> _draftOf(AppSettings settings) {
  final config = settings.questionTypeConfig;
  return <QuestionType, QuestionTypeSetting>{
    for (final type in QuestionType.values)
      type: QuestionTypeSetting(
        enabled: config.isEnabled(type),
        weight: config.weightOf(type).round(),
      ),
  };
}

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
