/// 编辑词条弹窗：改词条文本 + 用新文本重取有道内容 + 应用。
///
/// 对应旧版
/// `src/app/(main)/words/[id]/components/edit-word-dialog.tsx`。
///
/// **为什么改文本必须先取内容**：词条文本与内容是同一件事的两面——改了
/// 「apple」却留着「苹果」的释义，判题会立刻出错。旧版因此把「保存」按钮
/// 换成「有道词典初始化」：只有拿到新文本对应的内容并应用成功，词条才会
/// 真正变化。这个约束在界面上要写明，否则用户会以为按钮坏了。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/dialogs/apply_mode_selector.dart';
import 'package:lexiloop/features/word_detail/dialogs/word_content_preview.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 弹窗内容宽度。
const double editWordDialogWidth = 560;

/// 编辑词条弹窗的输入。
///
/// 打包成一个值对象而不是六个参数：详情页与词库列表页都要打开这个弹窗，
/// 而它们手上分别是 `WordDetail` 与 `WordListEntry` 两个不同的类型，
/// 值对象让两边都只需要构造一次、也只需要记住一份字段清单。
class EditWordTarget {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.term,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
  });

  /// 词条 ID。
  final int wordId;

  /// 当前词条文本。
  final String term;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 内容类型。
  final LexicalContentType contentType;
}

/// 编辑词条弹窗。
class EditWordDialog extends ConsumerStatefulWidget {
  /// 以编辑目标与保存回调构造。
  const new({required this.target, this.onSaved, super.key});

  /// 待编辑的词条。
  final EditWordTarget target;

  /// 应用成功后的回调（用于刷新列表等外部状态）。
  final VoidCallback? onSaved;

  /// 以对话框形式打开。
  static Future<void> show(
    BuildContext context, {
    required EditWordTarget target,
    VoidCallback? onSaved,
  }) => showDialog<void>(
    context: context,
    builder: (context) => EditWordDialog(target: target, onSaved: onSaved),
  );

  @override
  ConsumerState<EditWordDialog> createState() => _EditWordDialogState();
}

class _EditWordDialogState extends ConsumerState<EditWordDialog> {
  late final TextEditingController _term = TextEditingController(
    text: widget.target.term,
  );
  YoudaoPreviewResult? _preview;
  InitializationMode _mode = InitializationMode.fillMissingFields;
  String? _error;
  bool _busy = false;
  bool _applying = false;

  @override
  void dispose() {
    _term.dispose();
    super.dispose();
  }

  /// 文本是否真的变了。
  ///
  /// 与旧版的 `termChanged = term.trim() !== initialTerm` 逐字对应；
  /// 只用于提示文案，不影响是否允许取内容——文本没变也可以重新抓一次。
  bool get _termChanged => _term.text.trim() != widget.target.term;

  /// 用当前文本拉一次有道预览（不写库）。
  Future<void> _load() async {
    final term = _term.text.trim();
    if (term.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await ref
          .read(wordDetailActionsProvider)
          .previewYoudao(widget.target.wordId, termOverride: term);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = normalizeError(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 应用内容并保存词条文本。
  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null || !preview.hasContent) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await ref
          .read(wordDetailActionsProvider)
          .applyYoudao(
            wordId: widget.target.wordId,
            content: preview.content,
            mode: _mode,
            attempts: preview.attempts,
            newTerm: _term.text.trim(),
          );
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = normalizeError(error).message);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑词条'),
      content: SizedBox(
        width: editWordDialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _TermField(
                controller: _term,
                enabled: !_busy && !_applying,
                onChanged: () => setState(() {
                  _preview = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 6),
              _TargetMeta(target: widget.target, termChanged: _termChanged),
              const SizedBox(height: 10),
              const _SaveAfterFetchHint(),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: LexiType.footnote.copyWith(
                    color: context.lexiColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _Footer(
                busy: _busy,
                applying: _applying,
                canFetch: _term.text.trim().isNotEmpty,
                onClose: () => Navigator.of(context).pop(),
                onFetch: _load,
              ),
              ..._previewSections(),
            ],
          ),
        ),
      ),
    );
  }

  /// 预览结果对应的后续内容（无内容提示或内容 + 应用方式 + 确认）。
  List<Widget> _previewSections() {
    final preview = _preview;
    if (preview == null || _busy) return const <Widget>[];
    if (!preview.hasContent) return <Widget>[_NoContentView(preview: preview)];
    return <Widget>[
      const SizedBox(height: 12),
      WordContentPreview(content: preview.content),
      const SizedBox(height: 12),
      ApplyModeSelector(
        mode: _mode,
        onChanged: (mode) => setState(() => _mode = mode),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          TextButton(
            onPressed: _applying ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _applying ? null : _apply,
            child: Text(_applying ? '应用中…' : '确认应用并保存词条'),
          ),
        ],
      ),
    ];
  }
}

/// 词条文本输入框。
class _TermField extends StatelessWidget {
  const new({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLength: termMaxLength,
      onChanged: (_) => onChanged(),
      decoration: const InputDecoration(
        labelText: '词条文本',
        hintText: '输入修改后的词条文本',
      ),
    );
  }
}

/// 语言方向、内容类型与「文本是否已修改」的提示。
class _TargetMeta extends StatelessWidget {
  const new({required this.target, required this.termChanged});

  final EditWordTarget target;
  final bool termChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final suffix = termChanged ? '（已修改，需重新初始化内容）' : '（文本未变化，可重新获取内容）';
    return Text(
      '${languageLabel(target.sourceLanguage)} → '
      '${languageLabel(target.targetLanguage)} · '
      '${contentTypeLabel(target.contentType)}$suffix',
      style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
    );
  }
}

/// 「保存发生在取到内容之后」的说明。
class _SaveAfterFetchHint extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '修改词条后需点击「有道词典初始化」获取新内容并确认应用，'
        '成功后才保存词条文本；未初始化前词条不会发生变化。',
        style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      ),
    );
  }
}

/// 取消与「有道词典初始化」按钮。
class _Footer extends StatelessWidget {
  const new({
    required this.busy,
    required this.applying,
    required this.canFetch,
    required this.onClose,
    required this.onFetch,
  });

  final bool busy;
  final bool applying;
  final bool canFetch;
  final VoidCallback onClose;
  final VoidCallback onFetch;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          onPressed: busy || applying ? null : onClose,
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: !canFetch || busy || applying ? null : onFetch,
          child: Text(busy ? '获取中…' : '有道词典初始化'),
        ),
      ],
    );
  }
}

/// 有道没有返回内容时的提示：此时不能保存词条文本。
class _NoContentView extends StatelessWidget {
  const new({required this.preview});

  final YoudaoPreviewResult preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final messages = <String>[
      for (final attempt in preview.attempts)
        if (attempt.errorMessage != null) attempt.errorMessage!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 12),
        Text(
          '有道词典未返回该词条的有效内容，暂不能保存修改。',
          style: LexiType.body.copyWith(color: colors.secondaryLabel),
        ),
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            ),
          ),
      ],
    );
  }
}
