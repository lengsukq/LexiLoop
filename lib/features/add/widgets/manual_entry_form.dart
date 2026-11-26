/// 手动录入表单。
///
/// 拆成独立组件而不是塞进页面：表单字段与校验的复杂度已经足够高，
/// 混在页面里会让 `build()` 迅速超过 80 行（旧版 `manual-tab.tsx` 300 行）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/add/add_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 手动录入表单。
class ManualEntryForm extends ConsumerStatefulWidget {
  /// 以键构造。
  const new({super.key});

  @override
  ConsumerState<ManualEntryForm> createState() => _ManualEntryFormState();
}

class _ManualEntryFormState extends ConsumerState<ManualEntryForm> {
  late final TextEditingController _term;
  late final TextEditingController _definitions;
  late final TextEditingController _phonetic;
  late final TextEditingController _examples;
  late final TextEditingController _tags;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final state = ref.read(manualEntryProvider);
    _term = TextEditingController(text: state.term);
    _definitions = TextEditingController(text: state.definitionsText);
    _phonetic = TextEditingController(text: state.phonetic);
    _examples = TextEditingController(text: state.examplesText);
    _tags = TextEditingController(text: state.tagsText);
    _note = TextEditingController(text: state.note);
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _term,
      _definitions,
      _phonetic,
      _examples,
      _tags,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualEntryProvider);
    final notifier = ref.read(manualEntryProvider.notifier);
    return Surface(
      tone: LexiTone.mint,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(formPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ..._identityFields(state, notifier),
          const SizedBox(height: fieldGap),
          ..._contentFields(state, notifier),
          const SizedBox(height: fieldGap),
          DisclosureSection(
            title: '标签与笔记',
            child: Column(children: _metaFields(state, notifier)),
          ),
          if (state.error != null) ...<Widget>[
            const SizedBox(height: fieldGap),
            Text(
              state.error!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.lexiColors.dangerText),
            ),
          ],
          const SizedBox(height: submitGap),
          _SubmitButton(state: state, notifier: notifier),
        ],
      ),
    );
  }

  /// 词条身份：文本、内容类型、语种。
  List<Widget> _identityFields(
    ManualEntryState state,
    ManualEntryController notifier,
  ) => <Widget>[
    _LabeledField(
      label: '词条',
      child: TextField(
        controller: _term,
        autofocus: true,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(hintText: '例如 apple'),
        onChanged: (value) => notifier.replace(state.copyWith(term: value)),
      ),
    ),
    const SizedBox(height: fieldGap),
    _LabeledField(
      label: '内容类型',
      child: _ContentTypePicker(
        value: state.contentType,
        onChanged: (type) =>
            notifier.replace(state.copyWith(contentType: type)),
      ),
    ),
    const SizedBox(height: fieldGap),
    _LanguageRow(
      source: state.sourceLanguage,
      target: state.targetLanguage,
      onSource: (code) =>
          notifier.replace(state.copyWith(sourceLanguage: code)),
      onTarget: (code) =>
          notifier.replace(state.copyWith(targetLanguage: code)),
    ),
  ];

  /// 词条内容：释义、音标、例句。
  List<Widget> _contentFields(
    ManualEntryState state,
    ManualEntryController notifier,
  ) => <Widget>[
    _LabeledField(
      label: '释义（每行一条）',
      child: TextField(
        controller: _definitions,
        minLines: minLines,
        maxLines: maxLines,
        decoration: const InputDecoration(hintText: '苹果\n苹果树'),
        onChanged: (value) =>
            notifier.replace(state.copyWith(definitionsText: value)),
      ),
    ),
    const SizedBox(height: fieldGap),
    DisclosureSection(
      title: '音标与例句',
      child: Column(
        children: <Widget>[
          _LabeledField(
            label: '音标',
            child: TextField(
              controller: _phonetic,
              decoration: const InputDecoration(hintText: '/ˈæpl/'),
              onChanged: (value) =>
                  notifier.replace(state.copyWith(phonetic: value)),
            ),
          ),
          const SizedBox(height: fieldGap),
          _LabeledField(
            label: '例句（每行「句子 | 翻译」）',
            child: TextField(
              controller: _examples,
              minLines: minLines,
              maxLines: maxLines,
              decoration: const InputDecoration(
                hintText: 'I ate an apple. | 我吃了一个苹果。',
              ),
              onChanged: (value) =>
                  notifier.replace(state.copyWith(examplesText: value)),
            ),
          ),
        ],
      ),
    ),
  ];

  /// 附加信息：标签与笔记。
  List<Widget> _metaFields(
    ManualEntryState state,
    ManualEntryController notifier,
  ) => <Widget>[
    _LabeledField(
      label: '标签（逗号分隔）',
      child: TextField(
        controller: _tags,
        decoration: const InputDecoration(hintText: '水果, 基础词'),
        onChanged: (value) => notifier.replace(state.copyWith(tagsText: value)),
      ),
    ),
    const SizedBox(height: fieldGap),
    _LabeledField(
      label: '笔记',
      child: TextField(
        controller: _note,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: (value) => notifier.replace(state.copyWith(note: value)),
      ),
    ),
  ];
}

/// 提交按钮：提交中显示指示器。
class _SubmitButton extends StatelessWidget {
  const new({required this.state, required this.notifier});

  final ManualEntryState state;
  final ManualEntryController notifier;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: state.canSubmit
        ? () => notifier.submit(now: DateTime.now().millisecondsSinceEpoch)
        : null,
    child: state.submitting
        ? const SizedBox(
            width: indicatorSize,
            height: indicatorSize,
            child: CircularProgressIndicator(strokeWidth: indicatorStroke),
          )
        : const Text('保存到词库'),
  );
}

/// 内容类型选择器。
class _ContentTypePicker extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final LexicalContentType value;
  final ValueChanged<LexicalContentType> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<LexicalContentType>(
    segments: const <ButtonSegment<LexicalContentType>>[
      ButtonSegment<LexicalContentType>(
        value: LexicalContentType.word,
        label: Text('单词'),
      ),
      ButtonSegment<LexicalContentType>(
        value: LexicalContentType.phrase,
        label: Text('短语'),
      ),
      ButtonSegment<LexicalContentType>(
        value: LexicalContentType.sentence,
        label: Text('句子'),
      ),
    ],
    selected: <LexicalContentType>{value},
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

/// 源语言与目标语言选择。
class _LanguageRow extends StatelessWidget {
  const new({
    required this.source,
    required this.target,
    required this.onSource,
    required this.onTarget,
  });

  final String source;
  final String target;
  final ValueChanged<String> onSource;
  final ValueChanged<String> onTarget;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: _LabeledField(
          label: '源语言',
          child: _LanguagePicker(value: source, onChanged: onSource),
        ),
      ),
      const SizedBox(width: languageGap),
      Expanded(
        child: _LabeledField(
          label: '目标语言',
          child: _LanguagePicker(value: target, onChanged: onTarget),
        ),
      ),
    ],
  );
}

/// 单个语言下拉。
class _LanguagePicker extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    items: <DropdownMenuItem<String>>[
      for (final entry in supportedLanguages.entries)
        DropdownMenuItem<String>(
          value: entry.key,
          child: Text('${entry.value}（${entry.key}）'),
        ),
    ],
    onChanged: (selected) {
      if (selected != null) onChanged(selected);
    },
  );
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
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: context.lexiColors.secondaryLabel),
      ),
      const SizedBox(height: labelGap),
      child,
    ],
  );
}

/// 表单内边距。
const double formPadding = 16;

/// 字段之间的间距。
const double fieldGap = 14;

/// 标签与控件的间距。
const double labelGap = 6;

/// 多行输入框的最小行数。
const int minLines = 2;

/// 多行输入框的最大行数。
const int maxLines = 4;

/// 提交按钮上方的间距。
const double submitGap = 18;

/// 语言选择器之间的间距。
const double languageGap = 12;

/// 提交指示器尺寸。
const double indicatorSize = 18;

/// 提交指示器线宽。
const double indicatorStroke = 2;
