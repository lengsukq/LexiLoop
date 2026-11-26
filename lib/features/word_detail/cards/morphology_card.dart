/// 词根词缀卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词根词缀卡片：词根、前缀、后缀分区展示。
///
/// 调用方保证 [roots] 与 [affixes] 至少一个非空，否则整卡不显示。
class MorphologyCard extends StatelessWidget {
  /// 以词根与词缀列表构造。
  const new({required this.roots, required this.affixes, super.key});

  /// 词根列表。
  final List<RootView> roots;

  /// 词缀列表。
  final List<AffixView> affixes;

  @override
  Widget build(BuildContext context) {
    final prefixes = _affixesOf(AffixKind.prefix);
    final suffixes = _affixesOf(AffixKind.suffix);

    return SectionCard(
      variant: SurfaceVariant.plain,
      tone: LexiTone.lavender,
      title: '词根词缀',
      icon: LucideIcons.network,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (roots.isNotEmpty)
            _MorphologyGroup(
              title: '词根',
              children: <Widget>[
                for (final item in roots)
                  DetailBullet(item.root, note: _rootNote(item)),
              ],
            ),
          if (prefixes.isNotEmpty)
            _MorphologyGroup(
              title: '前缀',
              children: <Widget>[
                for (final item in prefixes)
                  DetailBullet(item.value, note: _affixNote(item)),
              ],
            ),
          if (suffixes.isNotEmpty)
            _MorphologyGroup(
              title: '后缀',
              children: <Widget>[
                for (final item in suffixes)
                  DetailBullet(item.value, note: _affixNote(item)),
              ],
            ),
        ],
      ),
    );
  }

  /// 取指定类型的词缀。
  List<AffixView> _affixesOf(AffixKind kind) =>
      affixes.where((item) => item.kind == kind).toList(growable: false);

  /// 「含义 · 语源」；语源缺失时只显示含义。
  String _rootNote(RootView item) =>
      item.origin == null ? item.meaning : '${item.meaning} · ${item.origin}';

  /// 「含义 · 来源」；来源缺失时只显示含义。
  String _affixNote(AffixView item) =>
      item.source == null ? item.meaning : '${item.meaning} · ${item.source}';
}

class _MorphologyGroup extends StatelessWidget {
  const new({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: LexiType.footnote.copyWith(
              color: colors.secondaryLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s4),
          ...children,
        ],
      ),
    );
  }
}
