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
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/import/import_history_section.dart';
import 'package:lexiloop/features/import/import_preview_table.dart';
import 'package:lexiloop/features/import/import_providers.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/reset_progress_option.dart';

/// CSV 导入页。
class ImportPage extends ConsumerWidget {
  /// 创建导入页。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importWizardProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            LexiSpace.s20,
            LexiSpace.s16,
            LexiSpace.s20,
            LexiSpace.s32,
          ),
          children: <Widget>[
            const _ImportHeader(),
            const SizedBox(height: LexiSpace.s16),
            const _StepCard(step: 1, title: '选择语言方向', child: _LanguageStep()),
            const SizedBox(height: LexiSpace.s12),
            const _StepCard(
              step: 2,
              title: '选择 EasyDict CSV 文件',
              child: _FileStep(),
            ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: LexiSpace.s12),
              _ErrorBanner(message: state.errorMessage!),
            ],
            if (state.result != null) ...<Widget>[
              const SizedBox(height: LexiSpace.s12),
              _ResultCard(result: state.result!),
            ],
            const SizedBox(height: LexiSpace.s12),
            _StepCard(
              step: 3,
              title: '预览与导入模式',
              child: state.preview == null
                  ? const _PreviewPlaceholder()
                  : _PreviewStep(preview: state.preview!),
            ),
            const SizedBox(height: LexiSpace.s12),
            const ImportHistorySection(),
          ],
        ),
      ),
    );
  }
}

class _ImportHeader extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '导入词库',
          style: LexiType.page.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: LexiSpace.s4),
        Text(
          '支持 EasyDict 导出的 CSV：单词 / 释义 / 音标 / 例句 / 同义词等列会自动识别。',
          style: LexiType.body.copyWith(color: colors.secondaryLabel),
        ),
      ],
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
    return LiquidGlass(
      level: GlassLevel.elevated,
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
                  color: colors.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: LexiType.caption.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: LexiSpace.s8),
              Text(
                title,
                style: LexiType.callout.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
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

    return Row(
      children: <Widget>[
        Expanded(
          child: _LanguageDropdown(
            key: const Key('importSourceLanguage'),
            label: '源语言',
            value: state.sourceLanguage,
            onChanged: notifier.setSourceLanguage,
          ),
        ),
        const SizedBox(width: LexiSpace.s12),
        Expanded(
          child: _LanguageDropdown(
            key: const Key('importTargetLanguage'),
            label: '目标语言',
            value: state.targetLanguage,
            onChanged: notifier.setTargetLanguage,
          ),
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
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: <DropdownMenuItem<String>>[
            for (final language in importLanguages)
              DropdownMenuItem<String>(
                value: language.code,
                child: Text(
                  '${language.label}（${language.code}）',
                  style: LexiType.body.copyWith(color: colors.label),
                ),
              ),
          ],
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
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

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            preview == null
                ? '尚未选择文件。'
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
              : const Icon(Icons.folder_open_rounded, size: 16),
          label: Text(preview == null ? '选择文件' : '重新选择'),
        ),
      ],
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Text(
      '选择文件后，这里会显示逐行预览与问题行。',
      style: LexiType.body.copyWith(color: colors.secondaryLabel),
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
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s6),
      child: Material(
        color: selected ? colors.accent.withValues(alpha: 0.1) : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s10,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: selected ? colors.accent : colors.tertiaryLabel,
                ),
                const SizedBox(width: LexiSpace.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _modeLabel(mode),
                        style: LexiType.body.copyWith(
                          color: selected ? colors.accent : colors.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: LexiSpace.s2),
                      Text(
                        _modeDescription(mode),
                        style: LexiType.footnote.copyWith(
                          color: colors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
              : const Icon(Icons.check_rounded, size: 16),
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
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(LexiSpace.s14),
      child: Column(
        key: const Key('importResultCard'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.task_alt_rounded, size: 17, color: colors.success),
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
            '失败 ${result.failed}；已入队初始化 ${result.queuedInitializations} 个',
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
          icon: const Icon(Icons.playlist_play_rounded, size: 16),
          label: const Text('查看初始化'),
        ),
        OutlinedButton.icon(
          key: const Key('importGoWords'),
          onPressed: () => context.go('/words'),
          icon: const Icon(Icons.menu_book_rounded, size: 16),
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
    final colors = context.lexiColors;
    return Container(
      key: const Key('importErrorBanner'),
      padding: const EdgeInsets.all(LexiSpace.s12),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 17, color: colors.danger),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(
              message,
              style: LexiType.body.copyWith(color: colors.danger),
            ),
          ),
        ],
      ),
    );
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
