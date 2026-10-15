/// 有道词典获取弹窗。
///
/// 对应旧版
/// `src/app/(main)/words/[id]/components/youdao-preview-dialog.tsx`。
///
/// 四种状态各自成块：加载中 / 出错可重试 / 有道无内容（列出各次尝试的
/// 错误说明）/ 有内容（分区预览 + 应用方式 + 取消与确认）。
/// 每种状态都必须有出口——只给「加载中」而没有「关闭」，
/// 用户遇到慢请求时只能强杀应用。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/dialogs/apply_mode_selector.dart';
import 'package:lexiloop/features/word_detail/dialogs/word_content_preview.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 弹窗内容宽度。
const double youdaoDialogWidth = 560;

/// 有道词典获取弹窗。
class YoudaoPreviewDialog extends ConsumerStatefulWidget {
  /// 以词条 ID 与可选的应用后回调构造。
  const new({required this.wordId, this.onApplied, super.key});

  /// 词条 ID。
  final int wordId;

  /// 应用成功后的回调（用于刷新列表等外部状态）。
  final VoidCallback? onApplied;

  /// 以对话框形式打开。
  static Future<void> show(
    BuildContext context, {
    required int wordId,
    VoidCallback? onApplied,
  }) => showDialog<void>(
    context: context,
    builder: (context) =>
        YoudaoPreviewDialog(wordId: wordId, onApplied: onApplied),
  );

  @override
  ConsumerState<YoudaoPreviewDialog> createState() =>
      _YoudaoPreviewDialogState();
}

class _YoudaoPreviewDialogState extends ConsumerState<YoudaoPreviewDialog> {
  YoudaoPreviewResult? _preview;
  InitializationMode _mode = InitializationMode.fillMissingFields;
  String? _error;
  bool _busy = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    // 首帧就去拉预览：弹窗一打开就该看到「正在获取」，
    // 等一帧再发请求只会让加载态闪一下。
    unawaited(_load());
  }

  /// 拉取预览；失败时把错误显示在弹窗里并给出重试。
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await ref
          .read(wordDetailActionsProvider)
          .previewYoudao(widget.wordId);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = normalizeError(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 应用预览内容；成功后关闭弹窗并通知调用方。
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
            wordId: widget.wordId,
            content: preview.content,
            mode: _mode,
            attempts: preview.attempts,
          );
      if (!mounted) return;
      widget.onApplied?.call();
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
      title: const Text('有道词典获取'),
      content: SizedBox(
        width: youdaoDialogWidth,
        child: SingleChildScrollView(child: _body()),
      ),
    );
  }

  /// 按状态选择要展示的内容。
  Widget _body() {
    if (_busy) return const _LoadingView();
    final preview = _preview;
    if (preview == null) {
      return _ErrorView(
        message: _error ?? '有道词典获取失败',
        onClose: () => Navigator.of(context).pop(),
        onRetry: _load,
      );
    }
    if (!preview.hasContent) {
      return _NoContentView(preview: preview);
    }
    return _ContentView(
      preview: preview,
      mode: _mode,
      applying: _applying,
      error: _error,
      onModeChanged: (mode) => setState(() => _mode = mode),
      onClose: () => Navigator.of(context).pop(),
      onApply: _apply,
    );
  }
}

/// 加载中。
class _LoadingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(
            '正在从有道词典获取内容…',
            style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 获取失败：可关闭、可重试。
class _ErrorView extends StatelessWidget {
  const new({
    required this.message,
    required this.onClose,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      children: <Widget>[
        const SizedBox(height: 20),
        Icon(Icons.error_outline_rounded, size: 38, color: colors.danger),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.danger, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextButton(onPressed: onClose, child: const Text('关闭')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ],
    );
  }
}

/// 有道没有返回有效内容。
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
      children: <Widget>[
        const SizedBox(height: 20),
        Icon(Icons.menu_book_rounded, size: 38, color: colors.tertiaryLabel),
        const SizedBox(height: 10),
        Text(
          '有道词典未返回该词条的有效内容。',
          style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
        ),
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 有内容：分区预览 + 应用方式 + 取消与确认。
class _ContentView extends StatelessWidget {
  const new({
    required this.preview,
    required this.mode,
    required this.applying,
    required this.error,
    required this.onModeChanged,
    required this.onClose,
    required this.onApply,
  });

  final YoudaoPreviewResult preview;
  final InitializationMode mode;
  final bool applying;
  final String? error;
  final ValueChanged<InitializationMode> onModeChanged;
  final VoidCallback onClose;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WordContentPreview(content: preview.content),
        const SizedBox(height: 12),
        ApplyModeSelector(mode: mode, onChanged: onModeChanged),
        if (error != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(error!, style: TextStyle(color: colors.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: applying ? null : onClose,
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: applying ? null : onApply,
              child: Text(applying ? '应用中…' : '确认应用'),
            ),
          ],
        ),
      ],
    );
  }
}
