/// 词库列表里的一张词条卡片。
///
/// 卡片上只放「一眼能判断要不要点进去」的信息：词形、两条状态徽标、
/// 释义摘要、语向与到期日，外加两个就地操作（朗读、编辑）——
/// 旧版 `words/page.tsx` 也是把这两个入口挂在卡片上，
/// 用户不必为了改一个错字先进详情页。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/packs/word_packs_providers.dart';
import 'package:lexiloop/features/word_detail/dialogs/edit_word_dialog.dart';
import 'package:lexiloop/features/word_detail/word_detail_audio.dart';
import 'package:lexiloop/features/words/words_format.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/lexi_pressable.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词条卡片。
class WordCard extends StatelessWidget {
  /// 以词条与点击回调构造；多选模式下传入 [selectable] 与 [selected]。
  const new({
    required this.entry,
    required this.onTap,
    this.selectable = false,
    this.selected = false,
    super.key,
  });

  /// 卡片对应的词条行。
  final WordListEntry entry;

  /// 进入词条详情（或多选模式下切换勾选）。
  final VoidCallback onTap;

  /// 是否显示多选复选框。
  final bool selectable;

  /// 多选模式下是否已选中。
  final bool selected;

  /// 复习卡是否已到期。
  ///
  /// 在界面侧而不是 SQL 里算：到期是**随时间变化**的判定，
  /// 写进查询会让同一行在不同时刻返回不同结果，缓存与分页都会跟着失真。
  bool get isDue {
    final dueAt = entry.dueAt;
    return dueAt != null && dueAt <= DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    return LexiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s14,
          vertical: LexiSpace.s12,
        ),
        child: Row(
          children: <Widget>[
            if (selectable) ...<Widget>[
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: LexiSpace.s6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _CardHeading(entry: entry),
                  const SizedBox(height: LexiSpace.s4),
                  _CardMeaning(meaning: entry.meaning),
                  const SizedBox(height: LexiSpace.s6),
                  _CardMeta(entry: entry, isDue: isDue),
                ],
              ),
            ),
            const SizedBox(width: LexiSpace.s10),
            _CardAside(entry: entry),
          ],
        ),
      ),
    );
  }
}

/// 词形与两条状态徽标。
class _CardHeading extends StatelessWidget {
  const new({required this.entry});

  final WordListEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            entry.term,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LexiType.title.copyWith(
              color: context.lexiColors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (entry.wrongWordActive)
          const Padding(
            padding: EdgeInsets.only(left: LexiSpace.s6),
            child: LexiBadge(label: '错词', tone: LexiBadgeTone.danger),
          ),
        if (entry.isSuspended)
          const Padding(
            padding: EdgeInsets.only(left: LexiSpace.s6),
            child: LexiBadge(label: '已暂停'),
          ),
      ],
    );
  }
}

/// 释义摘要。
class _CardMeaning extends StatelessWidget {
  const new({required this.meaning});

  final String? meaning;

  @override
  Widget build(BuildContext context) {
    return Text(
      meaning ?? '暂无释义',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: LexiType.body.copyWith(color: context.lexiColors.secondaryLabel),
    );
  }
}

/// 初始化状态、掌握等级、语向与到期日。
class _CardMeta extends StatelessWidget {
  const new({required this.entry, required this.isDue});

  final WordListEntry entry;

  final bool isDue;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final dueAt = entry.dueAt;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (entry.initializationStatus != InitializationStatus.ready)
          InitializationBadge(status: entry.initializationStatus),
        MasteryBadge(level: entry.masteryLevel),
        if (entry.isPersonal && entry.packNames.isNotEmpty)
          const LexiBadge(label: '个人', tone: LexiBadgeTone.accent),
        for (final packName in entry.packNames.take(wordCardMaxPackBadges))
          LexiBadge(label: packName),
        Text(
          '${entry.sourceLanguage} → ${entry.targetLanguage}',
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
        if (isDue) const LexiBadge(label: '到期', tone: LexiBadgeTone.accent),
        if (dueAt != null)
          Text(
            formatDueDate(dueAt),
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
      ],
    );
  }
}

/// 卡片右侧：朗读 / 编辑入口与掌握分。
class _CardAside extends StatelessWidget {
  const new({required this.entry});

  final WordListEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SpeakerButton(entry: entry),
            _EditButton(entry: entry),
          ],
        ),
      ],
    );
  }
}

/// 朗读发音按钮。
///
/// 走 [speakWithWordSpeaker]（真人录音优先、系统朗读兜底）：卡片上带着
/// `pronunciations` 就是为了这里——没有音频地址时它会静默回落到系统朗读，
/// 有地址时先播放词典的 mp3。
class _SpeakerButton extends ConsumerWidget {
  const new({required this.entry});

  final WordListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: '朗读发音',
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(_speak(context, ref)),
      icon: Icon(
        LucideIcons.volume2,
        size: 16,
        color: context.lexiColors.accentText,
      ),
    );
  }

  Future<void> _speak(BuildContext context, WidgetRef ref) =>
      speakWithWordSpeaker(
        context: context,
        ref: ref,
        term: entry.term,
        contentType: entry.contentType,
        pronunciations: entry.pronunciations,
      );
}

/// 编辑词条按钮。
///
/// 与详情页头部用的是同一个弹窗：列表页改完文本后由
/// `WordDetailActions.applyYoudao` 统一失效 `wordListProvider`，
/// 卡片会自己刷新成新词形。
class _EditButton extends ConsumerWidget {
  const new({required this.entry});

  final WordListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: '词条操作',
      icon: const Icon(LucideIcons.ellipsis),
      onSelected: (value) {
        if (value == 'promote') {
          unawaited(_promote(context, ref));
          return;
        }
        unawaited(
          EditWordDialog.show(
            context,
            target: EditWordTarget(
              wordId: entry.id,
              term: entry.term,
              sourceLanguage: entry.sourceLanguage,
              targetLanguage: entry.targetLanguage,
              contentType: entry.contentType,
            ),
          ),
        );
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        if (!entry.isPersonal)
          const PopupMenuItem<String>(value: 'promote', child: Text('收入个人词库')),
        const PopupMenuItem<String>(value: 'edit', child: Text('编辑词条')),
      ],
    );
  }

  Future<void> _promote(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref
        .read(wordPackTransferProvider.notifier)
        .promoteWordToPersonal(entry.id);
    messenger?.showSnackBar(SnackBar(content: Text('已将「${entry.term}」收入个人词库')));
  }
}
