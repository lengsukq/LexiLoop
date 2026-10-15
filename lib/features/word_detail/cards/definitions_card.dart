/// 释义卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 释义卡片：按语言分组，标注词性与来源，并允许用户写一条自己的释义。
///
/// 调用方保证 [definitions] 非空，否则整卡不显示。
class DefinitionsCard extends ConsumerWidget {
  /// 以词条 ID 与释义列表构造。
  const new({required this.wordId, required this.definitions, super.key});

  /// 词条 ID；写操作与预填都要靠它。
  final int wordId;

  /// 释义列表。
  final List<DefinitionValue> definitions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = _groupByLanguage(definitions);
    return SectionCard(
      title: '释义',
      icon: Icons.menu_book_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final entry in groups.entries) ...<Widget>[
            _LanguageGroup(language: entry.key, items: entry.value),
            if (entry.key != groups.keys.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 10),
          _ManualDefinitionEditor(
            wordId: wordId,
            existing: _userAuthored(definitions),
          ),
        ],
      ),
    );
  }
}

/// 找出用户自己写的那条释义（按 [DefinitionValue.isUserEdited] 判定）。
///
/// 与 `WordEditService.updateManualDefinition` 用的是同一个标记，
/// 因此编辑框预填的一定是那条会被「保存释义」替换掉的——预填错一条，
/// 用户改两句就等于把别人的释义顶掉了。
DefinitionValue? _userAuthored(List<DefinitionValue> items) {
  for (final item in items) {
    if (item.isUserEdited) return item;
  }
  return null;
}

/// 按语言分组，保留首次出现的顺序。
///
/// 刻意不按 key 排序：释义顺序应与词典返回顺序一致，
/// 排序会把英文释义挪到中文前面，与词条的目标语言不符。
Map<String, List<DefinitionValue>> _groupByLanguage(
  List<DefinitionValue> items,
) {
  final groups = <String, List<DefinitionValue>>{};
  for (final item in items) {
    groups.putIfAbsent(item.language, () => <DefinitionValue>[]).add(item);
  }
  return groups;
}

class _LanguageGroup extends StatelessWidget {
  const new({required this.language, required this.items});

  final String language;
  final List<DefinitionValue> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          language.isEmpty ? '未标注语言' : languageLabel(language),
          style: TextStyle(
            color: colors.secondaryLabel,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in items) ...<Widget>[
          DetailBullet(item.text, note: _annotation(item)),
          if (item.usageNote != null)
            DetailBullet(item.usageNote!, note: '用法提示'),
        ],
      ],
    );
  }

  /// 「词性 · 语体 · 来源 · 已编辑」标注；全都缺时返回 `null`。
  String? _annotation(DefinitionValue item) {
    final parts = <String>[
      if (item.partOfSpeech != null) item.partOfSpeech!,
      if (item.register != null) item.register!,
      if (item.source != null) item.source!,
      if (item.isUserEdited) '已编辑',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// 手工释义编辑器：多行输入 + 「保存释义」。
///
/// 单独成组件是因为它自带 `TextEditingController` 与「保存中」状态；
/// 塞进卡片主体会让父级同时管分组、排版与输入，滚出屏幕后草稿也会跟着丢。
class _ManualDefinitionEditor extends ConsumerStatefulWidget {
  const new({required this.wordId, required this.existing});

  final int wordId;
  final DefinitionValue? existing;

  @override
  ConsumerState<_ManualDefinitionEditor> createState() =>
      _ManualDefinitionEditorState();
}

class _ManualDefinitionEditorState
    extends ConsumerState<_ManualDefinitionEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.existing?.text ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.existing?.text ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          key: manualDefinitionFieldKey,
          controller: _controller,
          maxLines: _editorMaxLines,
          minLines: _editorMinLines,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: '用自己的话写一条释义（留空则清除）',
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            FilledButton.tonal(
              onPressed: _busy ? null : _save,
              child: Text(saved.isEmpty ? '保存释义' : '更新释义'),
            ),
            if (saved.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy ? null : _clear,
                child: const Text('清除我的释义'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 保存当前输入的释义；与已存内容一致时直接返回。
  Future<void> _save() async {
    if (_controller.text.trim() == (widget.existing?.text ?? '')) return;
    await _write(_controller.text);
  }

  /// 撤掉用户手工撰写的那条释义。
  Future<void> _clear() async {
    _controller.clear();
    await _write('');
  }

  /// 落库并刷新；失败时把原因回显，而不是静默吞掉。
  ///
  /// 用户输入的往往是他刚想起来的一个好释义，保存失败却不告诉他，
  /// 等于让他白写一遍——他不会怀疑是保存坏了，只会更怀疑自己写错了。
  Future<void> _write(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(wordDetailActionsProvider)
          .updateManualDefinition(widget.wordId, text);
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// 手工释义输入框的定位键；理由同 `note_card.dart` 的 `noteFieldKey`。
const Key manualDefinitionFieldKey = Key('word-detail-manual-definition-field');

/// 输入框的最小行数：够写一句完整释义，又不至于把卡片撑到一屏。
const int _editorMinLines = 2;

/// 输入框的最大行数；超出后改为内部滚动。
const int _editorMaxLines = 6;
