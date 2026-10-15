/// 有道预览内容的展示。
///
/// 对应旧版
/// `src/app/(main)/words/[id]/components/youdao-preview-dialog.tsx` 的
/// `PreviewContent` 与 `formLabel`。
///
/// **为什么抽成独立组件**：预览弹窗与编辑词条弹窗都要展示同一份内容
/// （旧版正是让编辑弹窗 import 预览弹窗里的 `PreviewContent`），
/// 各写一遍会让「预览里能看到什么」在两个入口之间漂移。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 预览区的最大高度。
///
/// 与旧版的 `max-h-[45vh]` 对应：弹窗要让用户一眼看到「内容是什么」，
/// 同时把「应用方式」与确认按钮留在视野里。
const double previewMaxHeight = 380;

/// 词形变化类型的中文名。
///
/// 与旧版 `formLabel` 的映射逐条一致；未收录的类型直接回显原值，
/// 而不是显示空白——出现新类型时至少要能看出它是什么。
String formLabel(String type) => switch (type) {
  'PLURAL' => '复数',
  'THIRD_PERSON' => '三单',
  'PRESENT_PARTICIPLE' => '现在分词',
  'PAST' => '过去式',
  'PAST_PARTICIPLE' => '过去分词',
  'COMPARATIVE' => '比较级',
  'SUPERLATIVE' => '最高级',
  _ => type,
};

/// 一份词典内容的只读预览。
///
/// 六个分区按「翻译摘要 → 音标 → 释义 → 例句 → 短语 → 词形」排列：
/// 与用户判断「这次抓取值不值得应用」的视线顺序一致，空分区整块不出现。
class WordContentPreview extends StatelessWidget {
  /// 以内容构造。
  const new({required this.content, super.key});

  /// 待预览的内容。
  final DictionaryContent content;

  @override
  Widget build(BuildContext context) {
    final summary = _text(content.record('summary')['translation']);
    final pronunciations = content.records('pronunciations');
    final definitions = content.records('definitions');
    final examples = content.records('examples');
    final phrases = content.records('phrases');
    final forms = content.records('forms');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: previewMaxHeight),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (summary != null) _TranslationSummary(text: summary),
            if (pronunciations.isNotEmpty) _PhoneticRow(items: pronunciations),
            if (definitions.isNotEmpty)
              PreviewSection(
                label: '释义',
                children: <Widget>[
                  for (final item in definitions) _DefinitionTile(item: item),
                ],
              ),
            if (examples.isNotEmpty)
              PreviewSection(
                label: '例句',
                children: <Widget>[
                  for (final item in examples) _ExampleTile(item: item),
                ],
              ),
            if (phrases.isNotEmpty)
              PreviewSection(
                label: '短语搭配',
                children: <Widget>[_PhraseRow(items: phrases)],
              ),
            if (forms.isNotEmpty)
              PreviewSection(
                label: '词形变化',
                children: <Widget>[_FormRow(items: forms)],
              ),
          ],
        ),
      ),
    );
  }
}

/// 预览里的一个分区：小标题 + 若干条目。
class PreviewSection extends StatelessWidget {
  /// 以标题与条目构造。
  const new({required this.label, required this.children, super.key});

  /// 分区标题。
  final String label;

  /// 分区内容。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colors.tertiaryLabel,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// 翻译摘要高亮块。
class _TranslationSummary extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '翻译摘要',
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              color: colors.label,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 音标徽标行。
class _PhoneticRow extends StatelessWidget {
  const new({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final item in items)
            DetailChip(
              text:
                  '${_accentLabel(item['accent'])} /${_text(item['phonetic']) ?? ''}/',
            ),
        ],
      ),
    );
  }
}

/// 一条释义。
class _DefinitionTile extends StatelessWidget {
  const new({required this.item});

  final Map<String, Object?> item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final partOfSpeech = _text(item['partOfSpeech']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.label.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (partOfSpeech != null) ...<Widget>[
            DetailChip(text: partOfSpeech),
            const SizedBox(height: 4),
          ],
          Text(
            _text(item['text']) ?? '',
            style: TextStyle(color: colors.label, fontSize: 13.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 一条例句。
class _ExampleTile extends StatelessWidget {
  const new({required this.item});

  final Map<String, Object?> item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final translation = _text(item['translation']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.accent, width: 3)),
        color: colors.label.withValues(alpha: 0.03),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _text(item['sentence']) ?? '',
            style: TextStyle(
              color: colors.label,
              fontSize: 13.5,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
          if (translation != null)
            Text(
              translation,
              style: TextStyle(
                color: colors.secondaryLabel,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}

/// 短语徽标行。
class _PhraseRow extends StatelessWidget {
  const new({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final item in items) DetailChip(text: _phraseLabel(item)),
      ],
    );
  }
}

/// 词形变化徽标行。
class _FormRow extends StatelessWidget {
  const new({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final item in items)
          DetailChip(
            text:
                '${formLabel(_text(item['type']) ?? '')}: '
                '${_text(item['value']) ?? ''}',
          ),
      ],
    );
  }
}

String _phraseLabel(Map<String, Object?> item) {
  final phrase = _text(item['phrase']) ?? '';
  final translation = _text(item['translation']);
  return translation == null ? phrase : '$phrase · $translation';
}

String _accentLabel(Object? accent) => accent == 'UK' ? '英' : '美';

/// 取可空文本；非字符串或空白返回 `null`。
String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
