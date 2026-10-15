/// 例句卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 例句卡片：句子 + 翻译。
///
/// 调用方保证 [examples] 非空，否则整卡不显示。
class ExamplesCard extends StatelessWidget {
  /// 以例句列表构造。
  const new({required this.examples, super.key});

  /// 例句列表。
  final List<ExampleView> examples;

  @override
  Widget build(BuildContext context) {
    return DetailSectionCard(
      title: '例句',
      icon: Icons.format_quote_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final item in examples) _ExampleRow(item: item),
        ],
      ),
    );
  }
}

class _ExampleRow extends StatelessWidget {
  const new({required this.item});

  final ExampleView item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.sentence,
            style: TextStyle(color: colors.label, fontSize: 14, height: 1.45),
          ),
          if (item.translation != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.translation!,
                style: TextStyle(
                  color: colors.secondaryLabel,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
