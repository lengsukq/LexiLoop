/// CSV 导入页。
///
/// 对应旧版 `app/import/page.tsx`。步骤：选语言 → 选文件 → 预览 →
/// 选模式 → 提交 → 结果摘要；页面底部是导入历史。
///
/// **与旧版的差异**：旧版有一个假的 `Progress value={75}` 进度条
/// （见 `docs/CLEAN_CODE_BASELINE.md`），本版只展示真实计数，
/// 不再编造进度。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/import/csv_columns.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/data/import/wordlist_parser.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/import/import_history_section.dart';
import 'package:lexiloop/features/import/import_preview_table.dart';
import 'package:lexiloop/features/import/import_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/flow_steps.dart';
import 'package:lexiloop/ui/widgets/inline_notice.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/reset_progress_option.dart';
import 'package:lexiloop/ui/widgets/selection_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// CSV 导入页。
class ImportPage extends ConsumerWidget {
  /// 创建导入页。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importWizardProvider);

    return PageShell(
      scrollable: true,
      // **这一页此前没有任何返回入口**：它是顶层路由、不套外壳，也没有
      // `AppBar`，唯一的出口是三步都走完之后结果卡上的按钮。中途想退出
      // （选错了文件、不想导了）只能切走应用。页头补上返回，是本页
      // 最要紧的一个改动。
      header: PageHeader(
        title: '导入词库',
        subtitle: '支持 EasyDict CSV、Anki / 欧路 / 墨墨 TSV 与纯文本词表（TXT）；文件仅在本机解析。',
        leading: Builder(
          builder: (backContext) => IconButton(
            key: const Key('importBack'),
            tooltip: '返回',
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () {
              // 能被推上来就回上一页（例如从设置页进来），
              // 否则回到单词本——那是导入的主入口。
              if (backContext.canPop()) {
                backContext.pop();
              } else {
                backContext.go(wordsPath);
              }
            },
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FlowSteps(
            labels: const <String>['选择文件', '预览确认', '导入完成'],
            current: state.result != null
                ? 2
                : state.preview != null
                ? 1
                : 0,
          ),
          const _StepCard(step: 1, title: '选择语言方向', child: _LanguageStep()),
          const SizedBox(height: LexiSpace.s12),
          const _StepCard(
            step: 2,
            title: '选择词表文件（CSV / TSV / TXT）',
            child: _FileStep(),
          ),
          if (state.pendingMapping != null) ...<Widget>[
            const SizedBox(height: LexiSpace.s12),
            _StepCard(
              step: 2,
              title: '未识别到标准表头 · 手动指定列映射',
              child: _ColumnMappingForm(draft: state.pendingMapping!),
            ),
          ],
          if (state.errorMessage != null) ...<Widget>[
            const SizedBox(height: LexiSpace.s12),
            _ErrorBanner(message: state.errorMessage!),
          ],
          if (state.result != null) ...<Widget>[
            const SizedBox(height: LexiSpace.s12),
            _ResultCard(result: state.result!),
          ],
          const SizedBox(height: LexiSpace.s12),
          if (state.preview != null)
            _StepCard(
              step: 3,
              title: '预览与导入模式',
              child: _PreviewStep(preview: state.preview!),
            ),
          const SizedBox(height: LexiSpace.s12),
          const DisclosureSection(
            title: '导入历史与撤销',
            child: ImportHistorySection(),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const new({required this.step, required this.title, required this.child});

  final int step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      tone: LexiTone.sky,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(LexiSpace.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: LexiTint.tint),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: LexiType.caption.copyWith(
                    color: colors.accentText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: LexiSpace.s8),
              // 标题必须能换行：360 宽下「第 2 步 · 预览并挑选要导入的词」
              // 这类标题的自然宽度会顶破这一行（实测溢出 11px）。
              Expanded(
                child: Text(
                  title,
                  style: LexiType.callout.copyWith(
                    color: colors.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LexiSpace.s12),
          child,
        ],
      ),
    );
  }
}

class _LanguageStep extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importWizardProvider);
    final notifier = ref.read(importWizardProvider.notifier);

    // `Wrap` 而不是两个 `Expanded`：按内容取宽之后，两个下拉框加起来可能
    // 比一行窄，也可能在窄屏上放不下；`Expanded` 会把它们硬撑成两半。
    return Wrap(
      spacing: LexiSpace.s32,
      runSpacing: LexiSpace.s12,
      children: <Widget>[
        _LanguageDropdown(
          key: const Key('importSourceLanguage'),
          label: '源语言',
          value: state.sourceLanguage,
          onChanged: notifier.setSourceLanguage,
        ),
        _LanguageDropdown(
          key: const Key('importTargetLanguage'),
          label: '目标语言',
          value: state.targetLanguage,
          onChanged: notifier.setTargetLanguage,
        ),
      ],
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s4),
        // 限制最大宽度并用 `isExpanded`：桌面端箭头紧贴文案、不会被拉到行尾，
        // 窄屏 + 2.0 倍大字体下也不会撑爆 360px 版心。
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: <DropdownMenuItem<String>>[
              for (final language in importLanguages)
                DropdownMenuItem<String>(
                  value: language.code,
                  child: Text(
                    '${language.label}（${language.code}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LexiType.body.copyWith(color: colors.label),
                  ),
                ),
            ],
            onChanged: (selected) {
              if (selected != null) onChanged(selected);
            },
          ),
        ),
      ],
    );
  }
}

class _FileStep extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(importWizardProvider);
    final notifier = ref.read(importWizardProvider.notifier);
    final preview = state.preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                preview == null
                    ? '尚未选择文件（支持 CSV、TSV、每行一词 TXT）。'
                    : '${preview.filename}（${preview.totalRows} 行）',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LexiType.body.copyWith(
                  color: preview == null ? colors.secondaryLabel : colors.label,
                ),
              ),
            ),
            const SizedBox(width: LexiSpace.s12),
            FilledButton.icon(
              key: const Key('importPickFile'),
              onPressed: state.busy ? null : notifier.pickFile,
              icon: state.busy
                  ? const SizedBox(
                      width: LexiSpace.s14,
                      height: LexiSpace.s14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.folderOpen, size: 16),
              label: Text(preview == null ? '选择文件' : '重新选择'),
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s10),
        TextField(
          key: const Key('importBatchTags'),
          onChanged: notifier.setBatchTagsText,
          style: LexiType.body.copyWith(color: colors.label),
          decoration: InputDecoration(
            isDense: true,
            labelText: '本批标签（选文件前填写，可选）',
            hintText: '例如：雅思核心, Anki 导出（逗号或空格分隔）',
            hintStyle: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            filled: true,
            fillColor: colors.fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LexiRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// 自定义 CSV/TSV 列映射表单。
class _ColumnMappingForm extends ConsumerStatefulWidget {
  const new({required this.draft});

  final CsvColumnMappingDraft draft;

  @override
  ConsumerState<_ColumnMappingForm> createState() => _ColumnMappingFormState();
}

class _ColumnMappingFormState extends ConsumerState<_ColumnMappingForm> {
  int _termCol = 0;
  int? _definitionCol;
  int? _phoneticCol;
  int? _exampleCol;
  int? _tagsCol;
  bool _hasHeader = true;

  @override
  void initState() {
    super.initState();
    final cols = widget.draft.headers.length;
    _definitionCol = cols > 1 ? 1 : null;
  }

  Map<CsvField, int> _buildColumnMap() => <CsvField, int>{
    CsvField.term: _termCol,
    CsvField.definition: ?_definitionCol,
    CsvField.phonetic: ?_phoneticCol,
    CsvField.examples: ?_exampleCol,
    CsvField.tags: ?_tagsCol,
  };

  List<Widget> _buildPickers(List<String> headers) => <Widget>[
    _ColPicker(
      label: '词条列（必选）',
      headers: headers,
      value: _termCol,
      allowNone: false,
      onChanged: (v) => setState(() => _termCol = v ?? 0),
    ),
    _ColPicker(
      label: '释义列',
      headers: headers,
      value: _definitionCol,
      onChanged: (v) => setState(() => _definitionCol = v),
    ),
    _ColPicker(
      label: '音标列',
      headers: headers,
      value: _phoneticCol,
      onChanged: (v) => setState(() => _phoneticCol = v),
    ),
    _ColPicker(
      label: '例句列',
      headers: headers,
      value: _exampleCol,
      onChanged: (v) => setState(() => _exampleCol = v),
    ),
    _ColPicker(
      label: '标签列',
      headers: headers,
      value: _tagsCol,
      onChanged: (v) => setState(() => _tagsCol = v),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final notifier = ref.read(importWizardProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '文件 ${widget.draft.filename} 未匹配到 EasyDict 标准表头，请指定各列含义：',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _hasHeader,
          onChanged: (value) => setState(() => _hasHeader = value ?? true),
          title: Text(
            '首行是表头（导入时跳过首行）',
            style: LexiType.body.copyWith(color: colors.label),
          ),
        ),
        Wrap(
          spacing: LexiSpace.s16,
          runSpacing: LexiSpace.s8,
          children: _buildPickers(widget.draft.headers),
        ),
        const SizedBox(height: LexiSpace.s12),
        Wrap(
          spacing: LexiSpace.s8,
          children: <Widget>[
            FilledButton(
              key: const Key('importApplyMapping'),
              onPressed: () => notifier.applyColumnMapping(
                _buildColumnMap(),
                hasHeaderRow: _hasHeader,
              ),
              child: const Text('应用映射并预览'),
            ),
            TextButton(
              onPressed: notifier.cancelColumnMapping,
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColPicker extends StatelessWidget {
  const new({
    required this.label,
    required this.headers,
    required this.value,
    required this.onChanged,
    this.allowNone = true,
  });

  final String label;
  final List<String> headers;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
        DropdownButton<int?>(
          value: value,
          underline: const SizedBox.shrink(),
          items: <DropdownMenuItem<int?>>[
            if (allowNone) const DropdownMenuItem<int?>(child: Text('不导入')),
            for (var i = 0; i < headers.length; i += 1)
              DropdownMenuItem<int?>(
                value: i,
                child: Text(
                  '第 ${i + 1} 列：${headers[i].isEmpty ? '(空)' : headers[i]}',
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PreviewStep extends ConsumerWidget {
  const new({required this.preview});

  final ImportPreview preview;

  /// 勾了「重置学习进度」就先拦一道：这一步不可撤销，也不能靠「撤销批次」
  /// 找回——撤销要求批次纯新增，而重置过的批次恰恰不是。
  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(importWizardProvider.notifier);
    if (ref.read(importWizardProvider).resetLearningProgress) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => const _ResetProgressDialog(),
      );
      if (confirmed != true) return;
    }
    await notifier.commit();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importWizardProvider);
    final notifier = ref.read(importWizardProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FilterChip(
          key: const Key('importPreviewFilter'),
          label: const Text('只看问题行（无效 / 重复 / 已存在）'),
          selected: state.onlyProblems,
          onSelected: (selected) => notifier.setOnlyProblems(value: selected),
        ),
        const SizedBox(height: LexiSpace.s10),
        ImportPreviewTable(preview: preview, onlyProblems: state.onlyProblems),
        const SizedBox(height: LexiSpace.s14),
        Text(
          '导入模式',
          style: LexiType.footnote.copyWith(
            color: context.lexiColors.secondaryLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s6),
        for (final mode in ImportMode.values)
          _ModeOption(
            mode: mode,
            selected: state.mode == mode,
            onTap: () => notifier.setMode(mode),
          ),
        const SizedBox(height: LexiSpace.s12),
        ResetProgressOption(
          value: state.resetLearningProgress,
          onChanged: (next) => notifier.setResetLearningProgress(value: next),
        ),
        const SizedBox(height: LexiSpace.s12),
        _SubmitButton(
          busy: state.busy,
          enabled: preview.importableRows > 0,
          onSubmit: () => _submit(context, ref),
        ),
      ],
    );
  }
}

/// 重置学习进度前的不可撤销确认。
class _ResetProgressDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重置已有词条的学习进度？'),
      content: const Text(
        '本次导入覆盖到的已有词条，其复习卡、复习日志、错词状态与掌握度'
        '都会被删除，正在进行的复习题目也会被撤下。\n\n'
        '词典内容不会删除，但这些学习历史无法恢复，也无法通过「撤销批次」找回。',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('resetProgressConfirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('仍然重置'),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const new({required this.mode, required this.selected, required this.onTap});

  final ImportMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s6),
      child: SelectionCard(
        title: _modeLabel(mode),
        subtitle: _modeDescription(mode),
        tone: LexiTone.sky,
        selected: selected,
        onTap: onTap,
        compact: true,
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const new({
    required this.busy,
    required this.enabled,
    required this.onSubmit,
  });

  final bool busy;
  final bool enabled;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        FilledButton.icon(
          key: const Key('importSubmit'),
          onPressed: busy || !enabled ? null : onSubmit,
          icon: busy
              ? const SizedBox(
                  width: LexiSpace.s14,
                  height: LexiSpace.s14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.check, size: 16),
          label: Text(busy ? '导入中…' : '开始导入'),
        ),
        const SizedBox(width: LexiSpace.s12),
        if (!enabled)
          Expanded(
            child: Text(
              '没有可导入的行。',
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            ),
          ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const new({required this.result});

  final ImportCommitResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(LexiSpace.s14),
      child: Column(
        key: const Key('importResultCard'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(LucideIcons.circleCheck, size: 17, color: colors.success),
              const SizedBox(width: LexiSpace.s6),
              Text(
                '导入完成',
                style: LexiType.callout.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: LexiSpace.s8),
          Text(
            '新增 ${result.created} · 已存在 ${result.existing} · '
            '重复 ${result.duplicate} · 无效 ${result.invalid} · '
            '失败 ${result.failed}；已入队内容补全 ${result.queuedInitializations} 个',
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s12),
          const _ResultActions(),
        ],
      ),
    );
  }
}

/// 导入完成后的三个出口。
///
/// 对应旧版 `components/add/csv-tab.tsx` 成功卡片上的三个动作：
/// 「查看初始化」跳 `/initialize`、「打开单词本」跳 `/words`、
/// 「继续导入」清空向导回到第一步。没有出口时，用户导入 200 个词条后
/// 只能自己找路。
///
/// **路径字面量待统一**：`/initialize` 与 `/words` 目前没有具名常量，
/// 而 `/import` 在项目里被抄了三份（`words_providers.dart` 与
/// `dashboard_page.dart` 各有一个 `csvImportPath`，
/// `data_management_section.dart` 是裸字面量）。本次**不做**这项去重——
/// 它会同时改动另外几个工作流正在改的文件；统一时应当把四条路径一起收进
/// `app/router.dart` 的常量。
class _ResultActions extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(importWizardProvider.notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          key: const Key('importGoInitialize'),
          onPressed: () => context.go('/initialize'),
          icon: const Icon(LucideIcons.listVideo, size: 16),
          label: const Text('查看内容补全'),
        ),
        OutlinedButton.icon(
          key: const Key('importGoWords'),
          onPressed: () => context.go('/words'),
          icon: const Icon(LucideIcons.bookOpen, size: 16),
          label: const Text('打开单词本'),
        ),
        TextButton(
          key: const Key('importRestart'),
          onPressed: notifier.reset,
          child: const Text('继续导入'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return InlineNotice(key: const Key('importErrorBanner'), message: message);
  }
}

/// 导入模式的中文名。
String _modeLabel(ImportMode mode) => switch (mode) {
  ImportMode.skipExisting => '仅新增（SKIP_EXISTING）',
  ImportMode.fillMissing => '新增并补全缺失字段（FILL_MISSING）',
  ImportMode.forceDictionaryRefresh => '新增并刷新词典内容（FORCE_DICTIONARY_REFRESH）',
};

/// 导入模式的说明文案。
String _modeDescription(ImportMode mode) => switch (mode) {
  ImportMode.skipExisting => '库里已有的词条完全不动，只新增没有的词条。',
  ImportMode.fillMissing => '新增词条，并把 CSV 里的内容补到已有词条的空字段上，不覆盖已有内容。',
  ImportMode.forceDictionaryRefresh =>
    '新增词条，并用 CSV 内容覆盖已有词条的词典字段；学习进度、复习记录不受影响。',
};
