/// 笔记卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';

/// 笔记卡片：编辑并保存到 `words.user_note`。
///
/// 是详情页唯一的本地输入状态，因此做成 `StatefulWidget`；
/// 数据来源仍只有 [initialNote] 一个参数，保存动作走行为对象。
class NoteCard extends ConsumerStatefulWidget {
  /// 以词条 ID 与现有笔记构造。
  const new({required this.wordId, this.initialNote, super.key});

  /// 词条 ID。
  final int wordId;

  /// 现有笔记；为空表示尚未写过。
  final String? initialNote;

  @override
  ConsumerState<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends ConsumerState<NoteCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNote ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(wordDetailActionsProvider)
          .saveNote(widget.wordId, _controller.text);
      messenger.showSnackBar(const SnackBar(content: Text('笔记已保存')));
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('笔记保存失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailSectionCard(
      title: '我的笔记',
      icon: Icons.edit_note_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '写下这个词的联想、用法或易错点…'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_rounded, size: 17),
            label: Text(_busy ? '保存中…' : '保存笔记'),
          ),
        ],
      ),
    );
  }
}
