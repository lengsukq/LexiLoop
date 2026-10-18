/// 手动添加页的「词典批量预览」面板。
///
/// 对应旧版 `components/add/manual-tab.tsx`：多行文本域、内容类型 / 原语言 /
/// 目标语言三个下拉、逐行并发预览与逐行确认。快捷键 ⌘/Ctrl + Enter 触发预览。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/add/manual_batch_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/features/add/widgets/manual_batch_row_card.dart';
import 'package:lexiloop/services/manual_preview_service.dart';
import 'package:lexiloop/ui/feedback/confirm_dialog.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词典批量预览面板。
class ManualBatchPanel extends ConsumerStatefulWidget {
  /// 以键构造。
  const new({super.key});

  @override
  ConsumerState<ManualBatchPanel> createState() => _ManualBatchPanelState();
}

class _ManualBatchPanelState extends ConsumerState<ManualBatchPanel> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: ref.read(manualBatchProvider).text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 单向的「输入框 → 提供者」不够：快捷填入与「继续添加」都是从提供者侧
    // 改文本，输入框必须跟着变，否则按钮看起来是坏的。
    ref.listen<ManualBatchState>(manualBatchProvider, _syncText);
    final state = ref.watch(manualBatchProvider);
    final notifier = ref.read(manualBatchProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _BatchInputCard(controller: _text, state: state, notifier: notifier),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: panelGap),
          _ErrorBanner(message: state.error!),
        ],
        if (state.hasBatch) ...<Widget>[
          const SizedBox(height: panelGap),
          _BatchProgress(state: state),
          const SizedBox(height: panelGap),
          for (var i = 0; i < state.rows.length; i += 1)
            ManualBatchRowCard(
              entry: ManualBatchEntry(index: i, row: state.rows[i]),
              expanded: state.expandedIndex == i,
              busy: state.busy,
              onToggle: () => notifier.toggleExpanded(i),
              onConfirm: () => unawaited(notifier.confirmRow(i)),
            ),
          _BatchFooter(
            state: state,
            onConfirmAll: () =>
                unawaited(_confirmAllWithDialog(context, notifier, state)),
            onReset: notifier.reset,
          ),
        ],
      ],
    );
  }

  /// 把提供者里的文本同步回输入框，光标停在末尾。
  void _syncText(ManualBatchState? previous, ManualBatchState next) {
    if (next.text == _text.text) return;
    _text.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.text.length),
    );
  }
}

/// 输入卡片：快捷填入、文本域、计数、三个下拉与预览按钮。
class _BatchInputCard extends StatelessWidget {
  const new({
    required this.controller,
    required this.state,
    required this.notifier,
  });

  final TextEditingController controller;
  final ManualBatchState state;
  final ManualBatchController notifier;

  /// 生成预览（按钮与快捷键共用）。
  void _preview() => unawaited(notifier.preview());

  @override
  Widget build(BuildContext context) {
    return Surface(
      tone: LexiTone.mint,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(inputCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _QuickFillRow(onFill: notifier.setText),
          const SizedBox(height: batchFieldGap),
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _preview,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _preview,
            },
            child: TextField(
              key: const Key('manualBatchText'),
              controller: controller,
              minLines: batchMinLines,
              maxLines: batchMaxLines,
              onChanged: notifier.setText,
              decoration: const InputDecoration(hintText: batchHintText),
            ),
          ),
          const SizedBox(height: counterGap),
          _CounterRow(state: state),
          const SizedBox(height: batchFieldGap),
          _OptionsRow(state: state, notifier: notifier),
          const SizedBox(height: batchFieldGap),
          _PreviewRow(state: state, onPreview: _preview),
        ],
      ),
    );
  }
}

/// 快捷填入一行示例。
class _QuickFillRow extends StatelessWidget {
  const new({required this.onFill});

  final ValueChanged<String> onFill;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          '快捷填入：',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        for (final sample in _batchSamples)
          ActionChip(
            key: Key('manualBatchQuick${sample.key}'),
            label: Text(sample.label),
            onPressed: () => onFill(sample.text),
          ),
      ],
    );
  }
}

/// 行数与字符数计数。
class _CounterRow extends StatelessWidget {
  const new({required this.state});

  final ManualBatchState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final lineCount = manualBatchLines(state.text).length;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            <String>[
              '已输入 $lineCount 行，最多 $manualBatchMaxRows 行。',
              '类型、原语言、目标语言会应用到每一行。',
            ].join(),
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
        ),
        const SizedBox(width: LexiSpace.s8),
        Text(
          '${state.text.length}/$manualBatchMaxTotalChars',
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

/// 内容类型 / 原语言 / 目标语言三个下拉。
class _OptionsRow extends StatelessWidget {
  const new({required this.state, required this.notifier});

  final ManualBatchState state;
  final ManualBatchController notifier;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _LabeledField(
        label: '内容类型',
        child: DropdownButton<LexicalContentType?>(
          key: const Key('manualBatchContentType'),
          value: state.contentType,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          hint: const Text('自动判断'),
          items: <DropdownMenuItem<LexicalContentType?>>[
            const DropdownMenuItem<LexicalContentType?>(child: Text('自动判断')),
            for (final type in LexicalContentType.values)
              DropdownMenuItem<LexicalContentType?>(
                value: type,
                child: Text(articleEntryTypeLabel(type)),
              ),
          ],
          onChanged: notifier.setContentType,
        ),
      ),
      const SizedBox(height: batchFieldGap),
      Row(
        children: <Widget>[
          Expanded(
            child: _LabeledField(
              label: '原语言',
              child: _LanguageDropdown(
                fieldKey: const Key('manualBatchSourceLanguage'),
                value: state.sourceLanguage,
                onChanged: notifier.setSourceLanguage,
              ),
            ),
          ),
          const SizedBox(width: LexiSpace.s10),
          Expanded(
            child: _LabeledField(
              label: '目标语言',
              child: _LanguageDropdown(
                fieldKey: const Key('manualBatchTargetLanguage'),
                value: state.targetLanguage,
                onChanged: notifier.setTargetLanguage,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 批量预览可选语言的下拉。
class _LanguageDropdown extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    key: fieldKey,
    value: value,
    isExpanded: true,
    underline: const SizedBox.shrink(),
    items: <DropdownMenuItem<String>>[
      for (final code in manualBatchLanguageCodes)
        DropdownMenuItem<String>(
          value: code,
          child: Text('${manualBatchLanguageLabel(code)}（$code）'),
        ),
    ],
    onChanged: (selected) {
      if (selected != null) onChanged(selected);
    },
  );
}

/// 预览按钮与说明文案。
class _PreviewRow extends StatelessWidget {
  const new({required this.state, required this.onPreview});

  final ManualBatchState state;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final empty = manualBatchLines(state.text).isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          <String>[
            '生成预览会先查有道词典，识别不出短语或句子时自动用 AI 兜底，',
            '不会创建正式词条。确认后才会写入词库。',
          ].join(),
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
        const SizedBox(height: LexiSpace.s8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('manualBatchPreview'),
            onPressed: empty || state.busy ? null : onPreview,
            icon: state.previewing
                ? const SizedBox(
                    width: LexiSpace.s14,
                    height: LexiSpace.s14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.sparkles, size: 16),
            label: Text(state.hasBatch ? '重新生成预览' : '生成预览'),
          ),
        ),
      ],
    );
  }
}

/// 逐行进度 / 结果概览。
class _BatchProgress extends StatelessWidget {
  const new({required this.state});

  final ManualBatchState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    if (state.previewing) {
      return Row(
        key: const Key('manualBatchProgress'),
        children: <Widget>[
          const SizedBox(
            width: LexiSpace.s14,
            height: LexiSpace.s14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(
              '正在逐行查询词典，请稍候…（${state.previewDone}/${state.rows.length}）',
              style: LexiType.footnote.copyWith(color: colors.accentText),
            ),
          ),
        ],
      );
    }
    return Text(
      key: const Key('manualBatchProgress'),
      <String>[
        '${state.successCount} 行成功 · 共 ${state.rows.length} 行，',
        '确认后才会写入正式词库。',
      ].join(),
      style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
    );
  }
}

/// 面板底部：全部确认，或「已全部加入」。
class _BatchFooter extends StatelessWidget {
  const new({
    required this.state,
    required this.onConfirmAll,
    required this.onReset,
  });

  final ManualBatchState state;
  final VoidCallback onConfirmAll;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => state.allConfirmed
      ? _AllConfirmedCard(state: state, onReset: onReset)
      : _ConfirmAllCard(state: state, onConfirmAll: onConfirmAll);
}

/// 「全部确认加入」卡片。
class _ConfirmAllCard extends StatelessWidget {
  const new({required this.state, required this.onConfirmAll});

  final ManualBatchState state;
  final VoidCallback onConfirmAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(inputCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '确认后才会写入正式词库',
            style: LexiType.callout.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s4),
          Text(
            '确认不会再次查询词典；也可以先逐行展开详情再确认。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s10),
          FilledButton.icon(
            key: const Key('manualBatchConfirmAll'),
            onPressed: state.pendingCount == 0 || state.busy
                ? null
                : onConfirmAll,
            icon: const Icon(LucideIcons.circleCheck, size: 16),
            label: Text('全部确认加入（${state.pendingCount}）'),
          ),
        ],
      ),
    );
  }
}

/// 全部确认完成后的回执。
class _AllConfirmedCard extends StatelessWidget {
  const new({required this.state, required this.onReset});

  final ManualBatchState state;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(inputCardPadding),
      child: Column(
        key: const Key('manualBatchAllConfirmed'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(LucideIcons.circleCheck, color: colors.success, size: 18),
              const SizedBox(width: LexiSpace.s8),
              Text(
                '已全部加入词库',
                style: LexiType.callout.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: LexiSpace.s4),
          Text(
            '共确认 ${state.successCount} 个词条，词典预览内容已经正式保存。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s10),
          FilledButton(
            key: const Key('manualBatchReset'),
            onPressed: onReset,
            child: const Text('继续添加'),
          ),
        ],
      ),
    );
  }
}

/// 面板级错误提示。
class _ErrorBanner extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      key: const Key('manualBatchError'),
      padding: const EdgeInsets.all(LexiSpace.s12),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(LucideIcons.circleAlert, size: 17, color: colors.danger),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(
              message,
              style: LexiType.body.copyWith(color: colors.dangerText),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带标签的字段。
class _LabeledField extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        label,
        style: LexiType.footnote.copyWith(
          color: context.lexiColors.secondaryLabel,
        ),
      ),
      const SizedBox(height: LexiSpace.s2),
      child,
    ],
  );
}

/// 一个「快捷填入」示例。
class _BatchSample {
  /// 以标识、按钮文案与示例文本构造。
  const new({required this.key, required this.label, required this.text});

  /// 用于生成组件 Key 的标识。
  final String key;

  /// 按钮文案。
  final String label;

  /// 填入文本域的示例内容。
  final String text;
}

/// 三个快捷填入示例（与旧版 `manual-tab.tsx` 逐字一致）。
const List<_BatchSample> _batchSamples = <_BatchSample>[
  _BatchSample(
    key: 'Word',
    label: '+ 单词示例',
    text: 'serendipity\nresilient\nmeticulous',
  ),
  _BatchSample(
    key: 'Phrase',
    label: '+ 短语示例',
    text: 'bring up\ntake for granted\ncome across',
  ),
  _BatchSample(
    key: 'Sentence',
    label: '+ 句子示例',
    text: 'Practice makes perfect.\nAction speaks louder than words.',
  ),
];

/// 文本域占位文案。
const String batchHintText =
    '每行一个单词/词组/句子，例如：\n'
    'abandon\n'
    'break down\n'
    'I have been working here for five years.';

/// 面板内元素间距。
const double panelGap = 12;

/// 输入卡片内边距。
const double inputCardPadding = 14;

/// 卡片内字段之间的间距。
const double batchFieldGap = 12;

/// 计数行与文本域的间距。
const double counterGap = 6;

/// 多行输入框的最小行数。
const int batchMinLines = 4;

/// 多行输入框的最大行数。
const int batchMaxLines = 8;

/// 「全部确认加入」的确认门。
///
/// **为什么必须确认**：这是**零撤销**的批量写库——一次点按就把预览里的
/// 每一行写成正式词条，没有任何回滚入口（逐行确认至少还是你自己点的）。
/// 同一个应用里「创建初始化任务」要走一遍带预览的配置器、
/// 「撤销导入批次」也要二次确认；只有这里和队列的批量重试是零确认，
/// 用户学到的规则就成了「这里不用确认」，然后在别处丢数据。
Future<void> _confirmAllWithDialog(
  BuildContext context,
  ManualBatchController notifier,
  ManualBatchState state,
) async {
  final confirmed = await confirmAction(
    context,
    title: '全部确认加入？',
    body:
        '将把 ${state.pendingCount} 行预览写入正式词库，'
        ' 这一步不会再查询词典，也没有撤销入口。'
        ' \n\n想逐行检查的话，先取消，再展开每一行看详情。',
    confirmLabel: '写入词库',
  );
  if (!confirmed) return;
  await notifier.confirmAll();
}
