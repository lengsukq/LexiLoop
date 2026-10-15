/// 初始化配置器的字段目录与预设。
///
/// 字段不是「内容模型里有哪些列」，而是「词典管线能真正填出来什么」：
/// 只有出现在某个 provider 的能力表里的字段才允许勾选，勾了管线填不出的
/// 字段只会让一次初始化白跑一趟请求，最后以「部分完成」收场。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/dictionary/provider.dart';

/// 逻辑字段名 → 中文名。
///
/// **来源**：[providerCapabilities] 的五个能力键逐条对应，
/// 与旧版 `initialization-configurator.tsx` 的 `FIELD_LABELS` 同名同义。
/// 音标与音频是两个独立条目：它们存在同一张 `pronunciations` 表里，
/// 但请求、判定、合并都是分开做的（见 [phoneticField] 与 [audioField]）。
const Map<String, String> initializationFieldLabels = <String, String>{
  definitionsField: '释义',
  phoneticField: '音标',
  audioField: '真人音频',
  'examples': '例句',
  'phrases': '搭配与短语',
  'forms': '词形变化',
  'synonyms': '近义词',
  'antonyms': '反义词',
  'wordFamily': '同根词',
  'confusedWords': '易混词',
  'roots': '词根',
  'affixes': '词缀',
  'tags': '标签',
  summaryField: '概要',
  'learning': '助记与学习提示',
  'sentenceAnalysis': '句子分析',
};

/// 字段的中文名；未登记的字段名原样返回。
String initializationFieldLabel(String field) =>
    initializationFieldLabels[field] ?? field;

/// 一组字段（勾选时的分区）。
///
/// 分区沿用旧版的 `FIELD_GROUPS`：按「学习者什么时候会去看它」分组，
/// 而不是按字段名排序——后者会让最常用的音标和释义沉到列表末尾。
class ConfiguratorFieldGroup {
  /// 以分组名与字段列表构造。
  const new({required this.label, required this.fields});

  /// 分组名。
  final String label;

  /// 该组包含的字段。
  final List<String> fields;
}

/// 勾选面板的三组字段。
const List<ConfiguratorFieldGroup> configuratorFieldGroups =
    <ConfiguratorFieldGroup>[
      ConfiguratorFieldGroup(
        label: '基础信息',
        fields: <String>[definitionsField, phoneticField, audioField, 'forms'],
      ),
      ConfiguratorFieldGroup(
        label: '学习内容',
        fields: <String>[
          'examples',
          'phrases',
          'synonyms',
          'antonyms',
          'wordFamily',
          'confusedWords',
        ],
      ),
      ConfiguratorFieldGroup(
        label: '扩展内容',
        fields: <String>[
          'roots',
          'affixes',
          'tags',
          summaryField,
          'learning',
          'sentenceAnalysis',
        ],
      ),
    ];

/// 一个初始化预设。
///
/// **为什么保留预设**：可选字段有 16 个，逐个勾选的成本远高于「先点一下，
/// 再微调」。旧版有四个预设，本版沿用同一组选择。
class ConfiguratorPreset {
  /// 以名称、说明、字段与图标构造。
  const new({
    required this.label,
    required this.description,
    required this.fields,
    required this.icon,
    this.youdaoOnly = false,
  });

  /// 预设名。
  final String label;

  /// 一句话说明（做了什么、适合什么时候用）。
  final String description;

  /// 预设选中的字段。
  final List<String> fields;

  /// 预设图标（Material 图标，不含表情符号）。
  final IconData icon;

  /// 是否把来源锁死为有道词典。
  ///
  /// 锁死时来源与策略都不再可改：任务里存的来源列表只有一项，
  /// 并行合并与优先级回退对它没有区别，留着两个可点却不生效的控件
  /// 只会误导用户。
  final bool youdaoOnly;
}

/// 「仅补音标」预设的字段。
const List<String> phoneticOnlyFields = <String>[phoneticField];

/// 「基础词典信息」预设的字段。
const List<String> basicDictionaryFields = <String>[
  definitionsField,
  phoneticField,
  audioField,
  'forms',
];

/// 「仅有道词典」预设的字段。
///
/// 比旧版多勾了真人音频：有道的能力表里有 `pronunciations.audio`，
/// 而这份预设的意义正是「只认有道的权威内容」，少勾一项会让它的
/// 覆盖范围比用户预期窄。
const List<String> youdaoDictionaryFields = <String>[
  definitionsField,
  phoneticField,
  audioField,
  'examples',
  'phrases',
  'forms',
  summaryField,
];

/// 全部可选字段（展平 [configuratorFieldGroups]）。
final List<String> allConfiguratorFields = <String>[
  for (final group in configuratorFieldGroups) ...group.fields,
];

/// 四个预设（顺序即展示顺序）。
///
/// 「完整初始化」直接等于全部字段，因此这份列表不能是 const：
/// 字段目录以后增删时，这个预设会自己跟着变，不需要再改一处。
final List<ConfiguratorPreset> configuratorPresets = <ConfiguratorPreset>[
  const ConfiguratorPreset(
    label: '仅补音标',
    description: '适合新配置词典后补齐音标',
    fields: phoneticOnlyFields,
    icon: Icons.record_voice_over,
  ),
  const ConfiguratorPreset(
    label: '基础词典信息',
    description: '释义、音标、音频和词形',
    fields: basicDictionaryFields,
    icon: Icons.menu_book,
  ),
  ConfiguratorPreset(
    label: '完整初始化',
    description: '生成完整学习内容',
    fields: allConfiguratorFields,
    icon: Icons.auto_awesome,
  ),
  const ConfiguratorPreset(
    label: '有道词典',
    description: '仅使用有道词典的权威内容',
    fields: youdaoDictionaryFields,
    icon: Icons.menu_book_outlined,
    youdaoOnly: true,
  ),
];

/// 与当前选择完全一致的预设；没有匹配时返回 `null`。
///
/// 比较忽略顺序：勾选的先后不该影响「这是哪个预设」的判定，
/// 否则用户先勾释义再勾音标（等于勾了音标）也会被判成自定义。
ConfiguratorPreset? activeConfiguratorPreset(
  List<String> fields, {
  required bool youdaoOnly,
}) {
  for (final preset in configuratorPresets) {
    if (preset.youdaoOnly != youdaoOnly) continue;
    if (fields.length != preset.fields.length) continue;
    if (fields.every(preset.fields.contains)) return preset;
  }
  return null;
}
