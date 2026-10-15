/// 短语卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 短语卡片：短语 + 翻译。
///
/// 调用方保证 [phrases] 非空，否则整卡不显示。
class PhrasesCard extends StatelessWidget {
  /// 以短语列表构造。
  const new({required this.phrases, super.key});

  /// 短语列表。
  final List<PhraseView> phrases;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '短语',
      icon: Icons.link_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final item in phrases)
            DetailBullet(item.phrase, note: item.translation),
        ],
      ),
    );
  }
}
