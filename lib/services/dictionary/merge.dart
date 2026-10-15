/// 词条内容的合并与状态判定。
///
/// 对应旧版 `modules/dictionary/merge.ts` 与 `content.ts` 的
/// `contentStatus` / `mergeDictionaryContent`。
///
/// 纯数据合并的实现在 `lib/data/dictionary/merge_content.dart`；
/// 这里负责把它包装成 [DictionaryContent] 视图，并补上「内容是否可用」
/// 的领域判断——那是服务层的语义，不属于数据形态。
library;

import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/merge_content.dart';
import 'package:lexiloop/domain/enums.dart';

/// 合并任意多个来源的内容。
///
/// 数组字段并集去重、对象字段标量取第一个非空，
/// 最后按 `definitionDuplicateThreshold` 对释义做二次去重。
DictionaryContent mergeDictionaryContent(List<DictionaryContent?> contents) =>
    DictionaryContent(
      mergeContentFields(<Map<String, Object?>?>[
        for (final content in contents) content?.fields,
      ]),
    );

/// 保留用户产出后与刷新内容合并（强制覆盖模式）。
///
/// 用户手工编辑的释义与手工添加的例句是用户资产，
/// 重新拉取词典内容时不能被冲掉。
DictionaryContent preserveUserContent(
  DictionaryContent existing,
  DictionaryContent refreshed,
) => mergeDictionaryContent(<DictionaryContent>[
  DictionaryContent(<String, Object?>{
    'definitions': <Object?>[
      for (final item in existing.records('definitions'))
        if (isUserProtectedItem('definitions', item)) item,
    ],
    'examples': <Object?>[
      for (final item in existing.records('examples'))
        if (isUserProtectedItem('examples', item)) item,
    ],
  }),
  refreshed,
]);

/// 内容完成状态。
///
/// 句子类词条必须同时有「含义」与「语法解析」才算完整：
/// 只有译文时判题可以工作但学习价值不足，因此是 `PARTIAL`。
InitializationStatus contentStatus(
  DictionaryContent content,
  LexicalContentType contentType,
) {
  if (contentType == LexicalContentType.sentence) {
    final summary = content.record('summary');
    if (!_hasSentenceMeaning(content, summary)) {
      return InitializationStatus.failed;
    }
    if (_hasSentenceAnalysis(content) || _nonEmpty(summary['translation'])) {
      return InitializationStatus.ready;
    }
    return InitializationStatus.partial;
  }
  if (content.records('definitions').isEmpty) {
    return InitializationStatus.failed;
  }
  return content.records('examples').isEmpty
      ? InitializationStatus.partial
      : InitializationStatus.ready;
}

bool _hasSentenceMeaning(
  DictionaryContent content,
  Map<String, Object?> summary,
) {
  final hasDefinition = content
      .records('definitions')
      .any((item) => _nonEmpty(item['text']));
  return hasDefinition ||
      _nonEmpty(summary['translation']) ||
      _nonEmpty(summary['shortDefinition']);
}

bool _hasSentenceAnalysis(DictionaryContent content) {
  final analysis = content.record('sentenceAnalysis');
  if (_nonEmpty(analysis['grammarPattern']) ||
      _nonEmpty(analysis['grammarExplanation'])) {
    return true;
  }
  return content.strings('grammarNotes').isNotEmpty ||
      content.records('keyExpressions').isNotEmpty ||
      content.records('similarExamples').isNotEmpty ||
      content.records('variations').isNotEmpty;
}

/// 合并音标字段（`pronunciations.phonetic` 或 `pronunciations.audio`）。
///
/// 只覆盖对应的那一个子字段，另一个保持不变——旧版把两者合成一个
/// `pronunciations` 字段处理，导致「只补音标」会把已有音频清掉。
List<Map<String, Object?>> mergePronunciationField({
  required List<Map<String, Object?>> existing,
  required List<Map<String, Object?>> incoming,
  required bool audio,
  required bool force,
}) {
  final key = audio ? 'audioUrl' : 'phonetic';
  final usable = <Map<String, Object?>>[
    for (final item in incoming)
      if (_nonEmpty(item[key])) item,
  ];
  final result = <Map<String, Object?>>[
    for (final item in existing) Map<String, Object?>.from(item),
  ];
  if (usable.isEmpty) return result;
  if (!force && result.any((item) => _nonEmpty(item[key]))) return result;
  if (force) {
    for (final item in result) {
      item[key] = null;
    }
  }
  for (final source in usable) {
    final accent = source['accent'];
    final target = _pickPronunciation(result, accent, audio);
    if (target == null) {
      result.add(
        Map<String, Object?>.from(source)
          ..[audio ? 'phonetic' : 'audioUrl'] = null,
      );
      continue;
    }
    target[key] = source[key];
    if (!_nonEmpty(target['source'])) target['source'] = source['source'];
  }
  return <Map<String, Object?>>[
    for (final item in result)
      if (_nonEmpty(item['phonetic']) || _nonEmpty(item['audioUrl'])) item,
  ];
}

Map<String, Object?>? _pickPronunciation(
  List<Map<String, Object?>> items,
  Object? accent,
  bool audio,
) {
  final key = audio ? 'audioUrl' : 'phonetic';
  for (final item in items) {
    if (item['accent'] == accent && !_nonEmpty(item[key])) return item;
  }
  for (final item in items) {
    if (item['accent'] == accent) return item;
  }
  return null;
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;
