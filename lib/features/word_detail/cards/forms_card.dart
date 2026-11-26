/// 词形变化卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词形变化卡片：复数、过去式、比较级等。
///
/// 调用方保证 [forms] 非空，否则整卡不显示。
class FormsCard extends StatelessWidget {
  /// 以变化列表构造。
  const new({required this.forms, super.key});

  /// 词形变化列表。
  final List<FormView> forms;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      variant: SurfaceVariant.plain,
      tone: LexiTone.lavender,
      title: '词形变化',
      icon: LucideIcons.arrowLeftRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final item in forms) DetailBullet(item.form, note: _note(item)),
        ],
      ),
    );
  }

  /// 「变化类型 · 释义」；两者都缺时返回 `null`。
  String? _note(FormView item) {
    final parts = <String>[
      if (item.label != null) item.label!,
      if (item.translation != null) item.translation!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
