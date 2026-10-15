/// 字母拼图作答。
///
/// 已选中的块记 [LetterTile] 而不是字母文本：同一个词里可能出现重复字母
/// （`apple` 有两个 `p`），只按文本记录就无法区分「哪一块用过了」。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 字母拼图。
class LetterBank extends StatefulWidget {
  /// 以题目、判定结果与作答回调构造。
  const new({
    required this.item,
    required this.outcome,
    required this.onAnswer,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 已提交的判定结果；未提交时为 `null`。
  final ReviewOutcome? outcome;

  /// 拼接结果变化时回调。
  final ValueChanged<String> onAnswer;

  @override
  State<LetterBank> createState() => _LetterBankState();
}

class _LetterBankState extends State<LetterBank> {
  /// 已选中的块，顺序即拼接顺序。
  ///
  /// 记 [LetterTile] 而不是字母文本：同一个词里可能出现重复字母
  /// （`apple` 有两个 `p`），只按文本记录会让「用过的块」无法区分。
  final List<LetterTile> _picked = <LetterTile>[];

  String get _spelled => _picked.map((tile) => tile.value).join();

  @override
  Widget build(BuildContext context) {
    final locked = widget.outcome != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SpellingDisplay(text: _spelled),
        const SizedBox(height: LexiSpace.s14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final tile in widget.item.letters)
              if (!_isPicked(tile))
                _LetterTileButton(
                  tile: tile,
                  enabled: !locked,
                  onTap: () => _pick(tile),
                ),
          ],
        ),
        const SizedBox(height: LexiSpace.s14),
        Row(
          children: <Widget>[
            _SmallAction(
              icon: Icons.backspace_rounded,
              label: '退格',
              enabled: !locked && _picked.isNotEmpty,
              onTap: _backspace,
            ),
            const SizedBox(width: LexiSpace.s10),
            _SmallAction(
              icon: Icons.clear_rounded,
              label: '清空',
              enabled: !locked && _picked.isNotEmpty,
              onTap: _clear,
            ),
          ],
        ),
      ],
    );
  }

  bool _isPicked(LetterTile tile) => _picked.any((item) => item.id == tile.id);

  void _pick(LetterTile tile) {
    setState(() => _picked.add(tile));
    widget.onAnswer(_spelled);
  }

  void _backspace() {
    if (_picked.isEmpty) return;
    setState(_picked.removeLast);
    widget.onAnswer(_spelled);
  }

  void _clear() {
    setState(_picked.clear);
    widget.onAnswer(_spelled);
  }
}

/// 当前拼接结果的展示位。
class _SpellingDisplay extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      key: const Key('study.letterBank.spelling'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s12,
        vertical: LexiSpace.s10,
      ),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Text(
        text.isEmpty ? '点击下方字母拼写' : text,
        style: LexiType.page.copyWith(
          color: text.isEmpty ? colors.tertiaryLabel : colors.label,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// 单个字母块。
class _LetterTileButton extends StatelessWidget {
  const new({required this.tile, required this.enabled, required this.onTap});

  final LetterTile tile;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: Container(
          width: studyMinTapTarget,
          height: studyMinTapTarget,
          alignment: Alignment.center,
          child: Text(
            tile.value,
            style: LexiType.title.copyWith(
              color: enabled ? colors.label : colors.tertiaryLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 退格 / 清空这类小动作按钮。
class _SmallAction extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: studyMinTapTarget),
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
