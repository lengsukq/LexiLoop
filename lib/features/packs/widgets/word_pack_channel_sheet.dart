/// 词书包下载通道选择、测速与自定义镜像配置面板。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/features/packs/word_packs_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 弹出下载通道配置与一键测速 Sheet。
Future<void> showWordPackChannelSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _WordPackChannelSheet(),
    );

class _WordPackChannelSheet extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_WordPackChannelSheet> createState() =>
      _WordPackChannelSheetState();
}

class _WordPackChannelSheetState extends ConsumerState<_WordPackChannelSheet> {
  late WordPackChannelKind _selected;
  late final TextEditingController _customUrlCtrl;
  late final TextEditingController _repoCtrl;
  late final TextEditingController _refCtrl;
  Map<WordPackChannelKind, int?> _latencies = <WordPackChannelKind, int?>{};
  bool _probing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current =
        ref.read(wordPackDownloadConfigProvider).value ??
        const WordPackDownloadConfig();
    _selected = current.channel;
    _customUrlCtrl = TextEditingController(text: current.customBaseUrl);
    _repoCtrl = TextEditingController(text: current.repoOverride);
    _refCtrl = TextEditingController(text: current.refOverride);
  }

  @override
  void dispose() {
    _customUrlCtrl.dispose();
    _repoCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  WordPackDownloadConfig get _draft => WordPackDownloadConfig(
    channel: _selected,
    customBaseUrl: _customUrlCtrl.text.trim(),
    repoOverride: _repoCtrl.text.trim(),
    refOverride: _refCtrl.text.trim(),
  );

  Future<void> _probe() async {
    setState(() => _probing = true);
    try {
      final results = await ref
          .read(wordPackDownloaderProvider)
          .probeChannels(_draft);
      if (!mounted) return;
      setState(() {
        _latencies = <WordPackChannelKind, int?>{
          for (final item in results) item.kind: item.latencyMs,
        };
      });
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(wordPackDownloadConfigProvider.notifier).save(_draft);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          LexiSpace.s16,
          LexiSpace.s16,
          LexiSpace.s16,
          LexiSpace.s16 + inset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SheetHeader(probing: _probing, onProbe: _probe),
            const SizedBox(height: LexiSpace.s12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final kind in WordPackChannelKind.values)
                      _ChannelTile(
                        kind: kind,
                        selected: _selected == kind,
                        latencyMs: _latencies[kind],
                        probed: _latencies.containsKey(kind),
                        onSelect: () => setState(() => _selected = kind),
                      ),
                    const SizedBox(height: LexiSpace.s12),
                    _CustomFields(
                      customUrlCtrl: _customUrlCtrl,
                      repoCtrl: _repoCtrl,
                      refCtrl: _refCtrl,
                      showCustomHint: _selected == WordPackChannelKind.custom,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LexiSpace.s12),
            FilledButton(
              onPressed: _saving ? null : () => unawaited(_save()),
              child: Text(_saving ? '保存中…' : '保存通道设置'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const new({required this.probing, required this.onProbe});

  final bool probing;
  final VoidCallback onProbe;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '词书下载通道',
                style: LexiType.title.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '全部通道均执行 SHA-256 完整性校验',
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: probing ? null : onProbe,
          icon: const Icon(LucideIcons.gauge, size: 16),
          label: Text(probing ? '测速中…' : '一键测速'),
        ),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const new({
    required this.kind,
    required this.selected,
    required this.latencyMs,
    required this.probed,
    required this.onSelect,
  });

  final WordPackChannelKind kind;
  final bool selected;
  final int? latencyMs;
  final bool probed;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onSelect,
      leading: Icon(
        selected ? LucideIcons.circleCheck : LucideIcons.circle,
        size: 18,
        color: selected ? colors.accent : colors.tertiaryLabel,
      ),
      title: Text(kind.label, style: LexiType.callout),
      subtitle: Text(
        kind.subtitle,
        style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
      ),
      trailing: probed ? _LatencyBadge(latencyMs: latencyMs) : null,
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  const new({required this.latencyMs});

  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final ms = latencyMs;
    if (ms == null) {
      return const LexiBadge(label: '超时', tone: LexiBadgeTone.danger);
    }
    final tone = ms < 600
        ? LexiBadgeTone.success
        : (ms < 1800 ? LexiBadgeTone.warning : LexiBadgeTone.neutral);
    return LexiBadge(label: '${ms}ms', tone: tone);
  }
}

class _CustomFields extends StatelessWidget {
  const new({
    required this.customUrlCtrl,
    required this.repoCtrl,
    required this.refCtrl,
    required this.showCustomHint,
  });

  final TextEditingController customUrlCtrl;
  final TextEditingController repoCtrl;
  final TextEditingController refCtrl;
  final bool showCustomHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: customUrlCtrl,
          decoration: InputDecoration(
            labelText: showCustomHint ? '自定义加速源 / 镜像前缀（必填）' : '自定义加速前缀（可选）',
            hintText: 'https://packs.example.com/ 或 https://proxy/{url}',
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: TextField(
                controller: repoCtrl,
                decoration: const InputDecoration(
                  labelText: 'GitHub 仓库（留空用默认）',
                  hintText: 'lengsukq/LexiLoop-packs',
                ),
              ),
            ),
            const SizedBox(width: LexiSpace.s8),
            Expanded(
              child: TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: '标签 / 分支',
                  hintText: 'v1.0.0',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
