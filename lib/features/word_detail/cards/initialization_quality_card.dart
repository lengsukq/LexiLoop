/// 初始化质量卡片：逐条列出数据源的调用结果。
///
/// **为什么这张卡值得存在**：`provider_attempts` 一直是只写不读的表——
/// worker 把每次调用的状态、耗时、质量分写进去，然后就没有人再看过。
/// 于是「AI 明明返回了内容，界面却还是空的」这类问题在界面上没有任何线索，
/// 只能去翻 SQLite 文件。这张卡是那张表的第一个读取入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 初始化质量卡片（默认折叠）。
class InitializationQualityCard extends ConsumerWidget {
  /// 以词条 ID 构造。
  const new({required this.wordId, super.key});

  /// 词条 ID。
  final int wordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attempts = ref.watch(wordProviderAttemptsProvider(wordId));
    return attempts.when(
      loading: () => const DetailLoadingCard(title: '初始化质量'),
      error: (error, _) => DetailErrorCard(
        title: '初始化质量',
        message: '数据源调用记录加载失败：$error',
        onRetry: () => ref.invalidate(wordProviderAttemptsProvider(wordId)),
      ),
      data: (value) => _Collapsible(
        title: '初始化质量',
        icon: Icons.insights_rounded,
        child: value.isEmpty
            ? const DetailEmptyHint(text: '这个词条还没有数据源调用记录。')
            : _AttemptList(attempts: value),
      ),
    );
  }
}

/// 默认折叠的卡片壳。
///
/// 折叠是默认状态而不是「有失败才展开」：这张卡对绝大多数词条是空的，
/// 默认展开会在详情页塞进十几行没人关心的调用记录，反而把真正要看的
/// 释义与例句挤到屏外。
class _Collapsible extends StatefulWidget {
  const new({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return SectionCard(
      title: widget.title,
      icon: widget.icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(_expanded ? '收起' : '展开'),
            ),
          ),
          if (_expanded)
            Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Divider(color: colors.separator, height: 14),
                  widget.child,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AttemptList extends StatelessWidget {
  const new({required this.attempts});

  final List<ProviderAttemptView> attempts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final attempt in attempts) _AttemptRow(attempt: attempt),
      ],
    );
  }
}

/// 一次数据源调用。
class _AttemptRow extends StatelessWidget {
  const new({required this.attempt});

  final ProviderAttemptView attempt;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              DetailChip(
                text: attemptStatusLabel(attempt.status),
                color: attemptStatusColor(attempt.status, colors),
              ),
              const SizedBox(width: LexiSpace.s6),
              Expanded(
                child: Text(
                  attempt.providerId,
                  overflow: TextOverflow.ellipsis,
                  style: LexiType.footnote.copyWith(
                    color: colors.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatTimestamp(attempt.createdAt),
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
            ],
          ),
          if (attempt.qualityScore != null || attempt.durationMs != null)
            Padding(
              padding: const EdgeInsets.only(top: LexiSpace.s2),
              child: Text(
                _facts(attempt),
                style: LexiType.caption.copyWith(color: colors.secondaryLabel),
              ),
            ),
          if (attempt.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: LexiSpace.s2),
              child: Text(
                attempt.errorCode == null
                    ? attempt.errorMessage!
                    : '${attempt.errorCode}：${attempt.errorMessage}',
                style: LexiType.caption.copyWith(color: colors.danger),
              ),
            ),
        ],
      ),
    );
  }

  /// 「耗时 · 质量分 · 返回字段」。
  ///
  /// 只在至少有一项可展示时才被调用（见 `build`）——耗时与质量分都没有时
  /// 这一行全是占位符，不如不占一行高度。
  String _facts(ProviderAttemptView attempt) {
    final parts = <String>[
      '耗时 ${formatDuration(attempt.durationMs)}',
      if (attempt.qualityScore != null) '质量分 ${attempt.qualityScore}',
      if (attempt.fieldsReturned.isNotEmpty)
        '返回 ${attempt.fieldsReturned.join('/')}',
    ];
    return parts.join(' · ');
  }
}

/// 调用状态的中文名。
String attemptStatusLabel(ProviderAttemptStatus status) => switch (status) {
  ProviderAttemptStatus.success => '成功',
  ProviderAttemptStatus.empty => '无内容',
  ProviderAttemptStatus.failed => '失败',
};

/// 调用状态的语义色。
Color attemptStatusColor(ProviderAttemptStatus status, LexiColors colors) =>
    switch (status) {
      ProviderAttemptStatus.success => colors.success,
      ProviderAttemptStatus.empty => colors.secondaryLabel,
      ProviderAttemptStatus.failed => colors.danger,
    };
