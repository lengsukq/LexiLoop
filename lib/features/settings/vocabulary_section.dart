/// 词汇水平与考试目标设置分组。
///
/// 水平是单选（含「不限定」），考试目标是多选且**不含** `AUTO`——
/// 旧版把 AUTO 也列进多选，结果「不限定 + 四级 + 六级」同时成立，
/// 语义自相矛盾。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词汇水平分组。
class VocabularySection extends ConsumerWidget {
  /// 以当前设置构造。
  const new({required this.settings, super.key});

  /// 当前设置。
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s4,
        LexiSpace.s12,
        LexiSpace.s4,
        LexiSpace.s24,
      ),
      children: <Widget>[
        SettingsSectionCard(
          title: '词汇水平',
          subtitle: '用于 AI 生成内容时选择难度口径，不影响已有词条。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final level in VocabularyLevel.values)
                _LevelOption(
                  level: level,
                  selected: settings.vocabularyLevel == level,
                  onTap: () => saveSettings(ref, <String, Object?>{
                    'vocabularyLevel': level.wire,
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: LexiSpace.s12),
        SettingsSectionCard(
          title: '考试目标',
          subtitle: '可多选，用于统计与推荐；「不限定」不作为目标。',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final level in _examLevels)
                FilterChip(
                  key: Key('examTarget-${level.wire}'),
                  label: Text(_examLabel(level)),
                  selected: settings.examTargets.contains(level),
                  onSelected: (selected) => _toggleTarget(ref, level, selected),
                ),
              if (settings.examTargets.isEmpty)
                Text(
                  '当前未选择任何考试目标。',
                  style: LexiType.footnote.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleTarget(WidgetRef ref, VocabularyLevel level, bool selected) {
    final targets = <VocabularyLevel>[...settings.examTargets];
    if (selected) {
      if (!targets.contains(level)) targets.add(level);
    } else {
      targets.remove(level);
    }
    unawaited(
      saveSettings(ref, <String, Object?>{
        'examTargets': targets.map((item) => item.wire).toList(),
      }),
    );
  }
}

class _LevelOption extends StatelessWidget {
  const new({required this.level, required this.selected, required this.onTap});

  final VocabularyLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s6),
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: LexiTint.tint)
            : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s10,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? LucideIcons.circleDot : LucideIcons.circle,
                  size: 17,
                  color: selected ? colors.accent : colors.tertiaryLabel,
                ),
                const SizedBox(width: LexiSpace.s10),
                Text(
                  vocabularyLevelLabel(level),
                  style: LexiType.body.copyWith(
                    color: selected ? colors.accent : colors.label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 可选为考试目标的档位（不含「不限定」）。
const List<VocabularyLevel> _examLevels = <VocabularyLevel>[
  VocabularyLevel.cet4,
  VocabularyLevel.cet6,
  VocabularyLevel.ky,
  VocabularyLevel.ielts,
  VocabularyLevel.toefl,
];

/// 词汇水平的中文名。
String vocabularyLevelLabel(VocabularyLevel level) => switch (level) {
  VocabularyLevel.auto => '不限定',
  VocabularyLevel.cet4 => '大学英语四级（CET4）',
  VocabularyLevel.cet6 => '大学英语六级（CET6）',
  VocabularyLevel.ky => '考研（KY）',
  VocabularyLevel.ielts => '雅思（IELTS）',
  VocabularyLevel.toefl => '托福（TOEFL）',
};

/// 考试目标的短标签。
String _examLabel(VocabularyLevel level) => switch (level) {
  VocabularyLevel.cet4 => 'CET4',
  VocabularyLevel.cet6 => 'CET6',
  VocabularyLevel.ky => '考研',
  VocabularyLevel.ielts => '雅思',
  VocabularyLevel.toefl => '托福',
  VocabularyLevel.auto => '不限定',
};
