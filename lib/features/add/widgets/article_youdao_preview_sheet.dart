/// 文章候选词的即时有道查词预览弹窗。
///
/// 不写入词库：让用户在导入前即可确认有道词典给出的音标、中文释义与双语例句，
/// 兑现「LLM 仅负责分词、查词走有道接口」的透明闭环。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 弹出指定词条的有道查词预览。
Future<void> showArticleYoudaoPreview(
  BuildContext context, {
  required String term,
  String? surfaceForm,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      ArticleYoudaoPreviewSheet(term: term, surfaceForm: surfaceForm),
);

/// 有道即时查词预览弹窗正文。
class ArticleYoudaoPreviewSheet extends ConsumerStatefulWidget {
  /// 以词条原形与可选原文变形构造。
  const new({required this.term, this.surfaceForm, super.key});

  /// 词条原形。
  final String term;

  /// 原文变形词（可选）。
  final String? surfaceForm;

  @override
  ConsumerState<ArticleYoudaoPreviewSheet> createState() =>
      _ArticleYoudaoPreviewSheetState();
}

class _ArticleYoudaoPreviewSheetState
    extends ConsumerState<ArticleYoudaoPreviewSheet> {
  Future<DictionaryLookupResult>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = ref
          .read(articleWizardProvider.notifier)
          .previewWordWithYoudao(widget.term);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s20,
        LexiSpace.s16,
        LexiSpace.s20,
        LexiSpace.s24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SheetHeader(term: widget.term, surfaceForm: widget.surfaceForm),
            const SizedBox(height: LexiSpace.s12),
            Flexible(
              child: FutureBuilder<DictionaryLookupResult>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingView();
                  }
                  if (snapshot.hasError) {
                    final error = snapshot.error;
                    final text = error is AppError
                        ? (error.details is String
                              ? error.details! as String
                              : error.message)
                        : '$error';
                    return _ErrorView(message: text, onRetry: _load);
                  }
                  final content = snapshot.data?.content;
                  if (content == null ||
                      content.records('definitions').isEmpty) {
                    return _ErrorView(
                      message: '有道词典暂未返回该词的中文释义。',
                      onRetry: _load,
                      tone: colors.secondaryLabel,
                    );
                  }
                  return _ContentView(content: content);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const new({required this.term, this.surfaceForm});

  final String term;
  final String? surfaceForm;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: LexiSpace.s8,
            runSpacing: LexiSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                term,
                style: LexiType.title2.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (surfaceForm != null)
                Text(
                  '← $surfaceForm',
                  style: LexiType.footnote.copyWith(
                    color: colors.tertiaryLabel,
                  ),
                ),
              const LexiBadge(label: '有道词典预览', tone: LexiBadgeTone.accent),
            ],
          ),
        ),
        IconButton(
          tooltip: '关闭',
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: LexiSpace.s24),
    child: Row(
      children: <Widget>[
        const SizedBox(
          width: LexiSpace.s20,
          height: LexiSpace.s20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: LexiSpace.s12),
        Text(
          '正在通过有道词典查询释义与音标…',
          style: LexiType.body.copyWith(
            color: context.lexiColors.secondaryLabel,
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const new({required this.message, required this.onRetry, this.tone});

  final String message;
  final VoidCallback onRetry;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: LexiSpace.s16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          message,
          style: LexiType.body.copyWith(
            color: tone ?? context.lexiColors.danger,
          ),
        ),
        const SizedBox(height: LexiSpace.s12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(LucideIcons.refreshCw, size: 15),
          label: const Text('重试查询'),
        ),
      ],
    ),
  );
}

class _ContentView extends StatelessWidget {
  const new({required this.content});

  final DictionaryContent content;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final phonetics = content.records('pronunciations');
    final definitions = content.records('definitions');
    final examples = content.records('examples').take(3).toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (phonetics.isNotEmpty) ...<Widget>[
            Wrap(
              spacing: LexiSpace.s8,
              runSpacing: LexiSpace.s4,
              children: <Widget>[
                for (final item in phonetics)
                  if (_text(item['phonetic']).isNotEmpty)
                    LexiBadge(
                      label:
                          '${_accentLabel(item['accent'])} '
                          '${_text(item['phonetic'])}',
                    ),
              ],
            ),
            const SizedBox(height: LexiSpace.s12),
          ],
          Text(
            '释义',
            style: LexiType.footnote.copyWith(
              color: colors.secondaryLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s6),
          for (final item in definitions)
            if (_text(item['text']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: LexiSpace.s4),
                child: Text(
                  _definitionLine(item),
                  style: LexiType.body.copyWith(color: colors.label),
                ),
              ),
          if (examples.isNotEmpty) ...<Widget>[
            const SizedBox(height: LexiSpace.s12),
            Text(
              '有道例句',
              style: LexiType.footnote.copyWith(
                color: colors.secondaryLabel,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LexiSpace.s6),
            for (final item in examples) _ExampleItem(item: item),
          ],
        ],
      ),
    );
  }
}

class _ExampleItem extends StatelessWidget {
  const new({required this.item});

  final Map<String, Object?> item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final sentence = _text(item['sentence']);
    final translation = _text(item['translation']);
    if (sentence.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(sentence, style: LexiType.body.copyWith(color: colors.label)),
          if (translation.isNotEmpty)
            Text(
              translation,
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            ),
        ],
      ),
    );
  }
}

String _accentLabel(Object? value) => switch ('${value ?? ''}'.toUpperCase()) {
  'UK' => '英',
  'US' => '美',
  _ => '音',
};

String _definitionLine(Map<String, Object?> item) {
  final pos = _text(item['partOfSpeech']);
  final text = _text(item['text']);
  return pos.isEmpty ? text : '$pos. $text';
}

String _text(Object? value) => value is String ? value.trim() : '';
