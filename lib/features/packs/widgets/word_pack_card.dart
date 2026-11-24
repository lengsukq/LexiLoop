/// 词书中心单本词书卡片（区分未安装与已安装两种状态）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/features/packs/word_packs_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词书卡片操作回调集合（收敛构造函数参数数 ≤ 5）。
class WordPackCardActions {
  /// 以各操作回调构造。
  const new({
    required this.onDownload,
    required this.onCancel,
    required this.onStudy,
    required this.onBrowseWords,
    required this.onToggleDaily,
    required this.onEnrichYoudao,
    required this.onUninstall,
    this.onPrecacheAudio,
  });

  /// 下载或更新词书。
  final VoidCallback onDownload;

  /// 取消当前下载。
  final VoidCallback onCancel;

  /// 开始本词书专项学习。
  final VoidCallback onStudy;

  /// 在单词本中浏览本词书词条。
  final VoidCallback onBrowseWords;

  /// 切换是否纳入每日计划。
  final ValueChanged<bool> onToggleDaily;

  /// 后台使用有道补全本词书缺失内容。
  final VoidCallback onEnrichYoudao;

  /// 卸载词书。
  final VoidCallback onUninstall;

  /// 离线批量预缓存本词书单词发音（可选）。
  final VoidCallback? onPrecacheAudio;
}

/// 词书卡片组件。
class WordPackCard extends StatelessWidget {
  /// 以目录项、可选已安装摘要、传输进度与操作集合构造。
  const new({
    required this.catalogItem,
    required this.installed,
    required this.transfer,
    required this.actions,
    super.key,
  });

  /// 目录信息（若为纯本地导入词书可为空）。
  final WordPackCatalogItem? catalogItem;

  /// 本地已安装状态摘要（未安装时为空）。
  final InstalledWordPackSummary? installed;

  /// 当前下载/入库进度（空闲时为空）。
  final WordPackTransferState? transfer;

  /// 卡片操作集合。
  final WordPackCardActions actions;

  @override
  Widget build(BuildContext context) {
    final name = installed?.name ?? catalogItem?.name ?? '';
    final description = installed?.description.isNotEmpty == true
        ? installed!.description
        : (catalogItem?.description ?? '');
    final category =
        installed?.category ?? catalogItem?.category ?? WordPackCategory.custom;
    final mode =
        installed?.contentMode ??
        catalogItem?.contentMode ??
        WordPackContentMode.ecdictBase;
    final hasUpdate =
        installed != null &&
        catalogItem != null &&
        installed!.version != catalogItem!.version;

    return Surface(
      padding: const EdgeInsets.all(LexiSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PackHeader(
            name: name,
            category: category,
            installed: installed,
            hasUpdate: hasUpdate,
            actions: actions,
          ),
          if (description.isNotEmpty) ...<Widget>[
            const SizedBox(height: LexiSpace.s6),
            Text(
              description,
              style: LexiType.body.copyWith(
                color: context.lexiColors.secondaryLabel,
              ),
            ),
          ],
          const SizedBox(height: LexiSpace.s10),
          _PackMetaRow(
            catalogItem: catalogItem,
            installed: installed,
            mode: mode,
          ),
          if (installed != null) ...<Widget>[
            const SizedBox(height: LexiSpace.s12),
            _InstalledProgress(installed: installed!),
          ],
          const SizedBox(height: LexiSpace.s12),
          if (transfer != null)
            _TransferProgressRow(
              transfer: transfer!,
              onCancel: actions.onCancel,
            )
          else if (installed != null)
            _InstalledFooter(installed: installed!, actions: actions)
          else
            _UninstalledFooter(onDownload: actions.onDownload),
        ],
      ),
    );
  }
}

class _PackHeader extends StatelessWidget {
  const new({
    required this.name,
    required this.category,
    required this.installed,
    required this.hasUpdate,
    required this.actions,
  });

  final String name;
  final WordPackCategory category;
  final InstalledWordPackSummary? installed;
  final bool hasUpdate;
  final WordPackCardActions actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: LexiSpace.s8,
            runSpacing: LexiSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                name,
                style: LexiType.title.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
              LexiBadge(label: category.label),
              if (installed != null)
                const LexiBadge(label: '已添加', tone: LexiBadgeTone.success),
              if (hasUpdate)
                const LexiBadge(label: '有更新', tone: LexiBadgeTone.accent),
            ],
          ),
        ),
        if (installed != null)
          PopupMenuButton<_PackMenuAction>(
            tooltip: '词书操作',
            icon: Icon(LucideIcons.ellipsis, color: colors.secondaryLabel),
            onSelected: (action) => switch (action) {
              _PackMenuAction.precacheAudio => actions.onPrecacheAudio?.call(),
              _PackMenuAction.enrich => actions.onEnrichYoudao(),
              _PackMenuAction.update => actions.onDownload(),
              _PackMenuAction.uninstall => actions.onUninstall(),
            },
            itemBuilder: (context) => <PopupMenuEntry<_PackMenuAction>>[
              if (actions.onPrecacheAudio != null)
                const PopupMenuItem<_PackMenuAction>(
                  value: _PackMenuAction.precacheAudio,
                  child: Text('离线缓存词书发音'),
                ),
              if (installed!.enrichableWords > 0)
                PopupMenuItem<_PackMenuAction>(
                  value: _PackMenuAction.enrich,
                  child: Text('用有道补全例句/短语（${installed!.enrichableWords} 词）'),
                ),
              if (hasUpdate)
                const PopupMenuItem<_PackMenuAction>(
                  value: _PackMenuAction.update,
                  child: Text('更新到最新版'),
                ),
              const PopupMenuItem<_PackMenuAction>(
                value: _PackMenuAction.uninstall,
                child: Text('卸载此词书'),
              ),
            ],
          ),
      ],
    );
  }
}

enum _PackMenuAction { precacheAudio, enrich, update, uninstall }

class _PackMetaRow extends StatelessWidget {
  const new({
    required this.catalogItem,
    required this.installed,
    required this.mode,
  });

  final WordPackCatalogItem? catalogItem;
  final InstalledWordPackSummary? installed;
  final WordPackContentMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final count = installed?.totalWords ?? catalogItem?.wordCount ?? 0;
    final bytes = catalogItem?.compressedBytes ?? 0;
    return Wrap(
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          '$count 词',
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
        if (bytes > 0)
          Text(
            formatPackBytes(bytes),
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
        LexiBadge(label: mode.label, tone: LexiBadgeTone.accent),
      ],
    );
  }
}

class _InstalledProgress extends StatelessWidget {
  const new({required this.installed});

  final InstalledWordPackSummary installed;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final ratio = installed.totalWords == 0
        ? 0.0
        : (installed.masteredWords / installed.totalWords).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '已掌握 ${installed.masteredWords} · '
                '学习中 ${installed.learningWords} · 未学 ${installed.newWords}',
                style: LexiType.caption.copyWith(color: colors.secondaryLabel),
              ),
            ),
            Text(
              '${installed.masteredPercent}%',
              style: LexiType.caption.copyWith(
                color: colors.accentText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s6),
        ClipRRect(
          borderRadius: BorderRadius.circular(LexiRadius.pill),
          child: LinearProgressIndicator(value: ratio, minHeight: LexiSpace.s6),
        ),
      ],
    );
  }
}

class _TransferProgressRow extends StatelessWidget {
  const new({required this.transfer, required this.onCancel});

  final WordPackTransferState transfer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                transfer.label,
                style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
              ),
            ),
            if (transfer.stage == WordPackTransferStage.downloading)
              TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ),
        const SizedBox(height: LexiSpace.s4),
        ClipRRect(
          borderRadius: BorderRadius.circular(LexiRadius.pill),
          child: LinearProgressIndicator(
            value: transfer.progress,
            minHeight: LexiSpace.s6,
          ),
        ),
      ],
    );
  }
}

class _InstalledFooter extends StatelessWidget {
  const new({required this.installed, required this.actions});

  final InstalledWordPackSummary installed;
  final WordPackCardActions actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '纳入每日学习计划',
                style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
              ),
            ),
            Switch(
              value: installed.includeInDailyStudy,
              onChanged: actions.onToggleDaily,
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s8),
        Wrap(
          spacing: LexiSpace.s8,
          runSpacing: LexiSpace.s8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: actions.onStudy,
              icon: const Icon(LucideIcons.graduationCap, size: 16),
              label: const Text('专项学习'),
            ),
            OutlinedButton.icon(
              onPressed: actions.onBrowseWords,
              icon: const Icon(LucideIcons.bookOpen, size: 16),
              label: const Text('浏览词表'),
            ),
          ],
        ),
      ],
    );
  }
}

class _UninstalledFooter extends StatelessWidget {
  const new({required this.onDownload});

  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: onDownload,
        icon: const Icon(LucideIcons.cloudDownload, size: 16),
        label: const Text('下载并添加'),
      ),
    );
  }
}
