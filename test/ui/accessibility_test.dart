/// 无障碍守卫：纯图标控件必须自带标签，动效必须尊重「减弱动态效果」。
///
/// **为什么需要它**：这两件事都没有编译期保护，也不会让界面「看起来不对」。
///
/// 1. 纯图标控件（`InkWell` / `GestureDetector` 里只有一个 `Icon`）在读屏
///    软件里只会念「按钮」，桌面端用户悬停也看不到它做什么。项目里 16 个
///    `IconButton` 都写了 `tooltip`，但**不是** `IconButton` 的那种（比如
///    游戏里 92×92 的发音键）就漏掉了。
///
/// 2. `MediaQuery.disableAnimationsOf` 是系统给应用的唯一「减弱动态效果」
///    信号；应用自己的动画若直接写死时长，就等于忽略了这个开关。
///
/// **关于误判**：判定「纯图标」是启发式的——有 `Icon`、没有 `Text`。当文字
/// 藏在同一个文件里的私有 widget 里时（例如 `related_words_card` 的行内容
/// 由 `_RelatedBody` 渲染），启发式会误报。这类情况就地写一行
/// `// a11y-ok: 理由`，理由不能为空——和仓库里 `// ignore:` 必须带理由的
/// 约定一致。不提供「无条件跳过」的写法，否则守卫会慢慢失效。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';

import '../architecture/source_scan.dart';

/// 会「吞掉」子控件语义的纯图标可点区域。
const List<String> tappables = <String>[
  'InkWell(',
  'InkResponse(',
  'GestureDetector(',
];

/// 能提供语义标签的外层包装。
const List<String> labellers = <String>['Tooltip(', 'Semantics('];

/// 就地豁免的标记。
const String optOut = '// a11y-ok:';

/// 往上找豁免标记时回看的字符数（够覆盖几行注释）。
const int optOutLookBehind = 240;

/// 找出括号配对的整段调用文本（含结尾的 `)`）。
String? callAt(String text, int openParenEnd) {
  var depth = 0;
  var i = openParenEnd - 1;
  while (i < text.length) {
    if (text[i] == '(') {
      depth += 1;
    } else if (text[i] == ')') {
      depth -= 1;
      if (depth == 0) return text.substring(openParenEnd - 1, i + 1);
    }
    i += 1;
  }
  return null;
}

/// 所有 [labellers] 调用的字符区间，用于判断某个控件是否被它们包住。
List<(int, int)> labellerSpans(String text) {
  final spans = <(int, int)>[];
  for (final name in labellers) {
    for (final match in RegExp(
      '(?<![A-Za-z_])${RegExp.escape(name)}',
    ).allMatches(text)) {
      final body = callAt(text, match.end);
      if (body != null) spans.add((match.start, match.start + body.length));
    }
  }
  return spans;
}

/// 控件内部或它上面几行里是否写了带非空理由的 [optOut]。
bool hasOptOut(String text, int start, String body) {
  final from = start > optOutLookBehind ? start - optOutLookBehind : 0;
  final haystack = text.substring(from, start) + body;
  final marker = haystack.lastIndexOf(optOut);
  if (marker < 0) return false;
  final rest = haystack.substring(marker + optOut.length);
  final reason = rest.split('\n').first.trim();
  return reason.isNotEmpty;
}

void main() {
  group('纯图标控件', () {
    test('lib 里的纯图标可点区域都带了标签', () {
      final violations = <String>[];

      for (final file in collectDartFiles('lib')) {
        final text = file.lines.join('\n');
        final spans = labellerSpans(text);

        for (final name in tappables) {
          for (final match in RegExp(
            '(?<![A-Za-z_])${RegExp.escape(name)}',
          ).allMatches(text)) {
            final body = callAt(text, match.end);
            if (body == null) continue;
            // 纯图标：有 Icon，没有可见文字。
            if (!body.contains('Icon(') || body.contains('Text(')) continue;
            // 自带标签，或被 Tooltip / Semantics 包住。
            if (body.contains('tooltip') || body.contains('Tooltip(')) continue;
            if (spans.any((s) => s.$1 <= match.start && match.start < s.$2)) {
              continue;
            }
            // 就地豁免：标记可以写在控件内部，也可以写在它上面几行
            // （注释通常写在上面）。理由必须非空。
            if (hasOptOut(text, match.start, body)) continue;
            final line =
                '\n'.allMatches(text.substring(0, match.start)).length + 1;
            violations.add('${file.path}:$line');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '纯图标控件必须自带标签，否则读屏软件只会念「按钮」，\n'
            '桌面端用户悬停也看不到它做什么。用 `Tooltip(message: ...)`\n'
            '（同时提供悬停提示与语义标签）或 `Semantics(label: ...)`。\n'
            '若文字确实藏在同一文件的私有 widget 里，就地写\n'
            '`$optOut 理由`（理由不能为空）。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });
  });

  group('减弱动态效果', () {
    testWidgets('disableAnimations 为真时时长折成零', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = LexiMotion.of(context, LexiMotion.feedback);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, Duration.zero);
    });

    testWidgets('未开启时时长原样返回', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            resolved = LexiMotion.of(context, LexiMotion.feedback);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(resolved, LexiMotion.feedback);
    });

    test('反馈时长非零，否则动画等于没有', () {
      expect(LexiMotion.feedback, greaterThan(Duration.zero));
    });
  });
}
