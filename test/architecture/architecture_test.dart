/// 架构守卫测试。
///
/// 这些测试把 `docs/CLEAN_CODE_BASELINE.md` 记录的问题类型变成**自动化约束**。
/// 旧版的问题是靠人工评审发现的，发现时已经积累了 231 行的整改清单；
/// 这里改为在写出来的当下就由 CI 拦下。
///
/// 对应关系：
/// - 重复逻辑      → `lib/domain/` 的纯函数约束（§分层）
/// - 巨型函数/组件 → 函数 ≤40 行、`build()` ≤80 行
/// - 参数膨胀      → 构造函数 ≤5 个参数
/// - 魔法数字      → `domain/`、`services/` 禁止裸数字字面量
/// - 静默吞异常    → 禁止空 `catch`
/// - 字符串判错    → 禁止 `error.message == "..."`
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/time.dart';

import 'source_scan.dart';

void main() {
  group('分层边界', () {
    test('lib/domain 必须是纯 Dart：不得引入 Flutter、IO 或框架包', () {
      const forbidden = <String>[
        'package:flutter/',
        'package:drift/',
        'package:dio/',
        'package:path_provider/',
        'package:flutter_secure_storage/',
        'package:window_manager/',
        'package:just_audio/',
        'package:flutter_tts/',
        'dart:io',
        'dart:ui',
      ];

      final violations = <String>[];
      for (final file in collectDartFiles('lib/domain')) {
        for (var i = 0; i < file.lines.length; i += 1) {
          final line = file.lines[i];
          if (!line.trimLeft().startsWith('import ')) continue;
          for (final bad in forbidden) {
            if (line.contains(bad)) {
              violations.add('${file.locate(i + 1)} 引入了 $bad');
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'domain/ 是纯逻辑层，必须可脱离 Flutter 单测。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });
  });

  group('规模阈值', () {
    test('函数与方法不超过 40 行', () {
      const maxLines = 40;
      final violations = <String>[];

      for (final file in _allLibFiles()) {
        for (final block in findFunctionBlocks(file)) {
          // `build()` 有独立的 80 行上限（见下一个用例），此处豁免。
          if (block.signature.contains('Widget build(')) continue;
          if (block.lineCount > maxLines) violations.add(block.describe());
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '超过 $maxLines 行的函数应拆分为单一职责的小函数。\n'
            '对应旧版问题：initialization/worker.ts 的 processJob 约 95 行。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });

    test('Widget 的 build() 不超过 80 行', () {
      const maxLines = 80;
      final violations = <String>[];

      for (final file in _allLibFiles()) {
        for (final block in findFunctionBlocks(file)) {
          if (!block.signature.contains('Widget build(')) continue;
          if (block.lineCount > maxLines) violations.add(block.describe());
        }
      }

      expect(
        violations,
        isEmpty,
        reason: <String>[
          '超过 $maxLines 行的 build() 应拆成子组件。',
          '旧版反例：study-client.tsx 497 行、games/page.tsx 543 行。',
          '违规项：',
          violations.join('\n'),
        ].join('\n'),
      );
    });

    test('构造函数参数不超过 5 个', () {
      const maxParams = 5;
      final violations = <String>[];

      for (final file in _allLibFiles()) {
        for (var i = 0; i < file.lines.length; i += 1) {
          final line = file.lines[i];
          if (!_looksLikeConstructor(line)) continue;
          final params = _countParameters(line);
          if (params > maxParams) {
            violations.add('${file.locate(i + 1)} 有 $params 个参数');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '参数超过 $maxParams 个时应改用参数对象。\n'
            '对应旧版问题：设置页传 13+8 个回调 props、词条详情页 11+6+7 个。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });
  });

  group('错误处理', () {
    test('禁止空 catch 块', () {
      final violations = <String>[];

      for (final file in _allLibFiles()) {
        for (var i = 0; i < file.lines.length; i += 1) {
          final line = file.lines[i];
          final trimmed = line.trim();
          // `} catch (_) {}` 或 `catch (e) {}` 这类静默吞异常。
          if (RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}').hasMatch(trimmed)) {
            violations.add(file.locate(i + 1));
            continue;
          }
          // `catch (e) {` 后紧跟 `}` 的多行写法。
          if (RegExp(r'catch\s*\([^)]*\)\s*\{$').hasMatch(trimmed) &&
              i + 1 < file.lines.length &&
              file.lines[i + 1].trim() == '}') {
            violations.add(file.locate(i + 1));
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '空 catch 会静默吞掉脏数据。至少记录日志或转换为 AppError。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });

    test('禁止用字符串比较判断错误类型', () {
      final violations = <String>[];
      final pattern = RegExp(
        r'''(message|error|e)\s*\.\s*message\s*==\s*['"]''',
      );

      for (final file in _allLibFiles()) {
        for (var i = 0; i < file.lines.length; i += 1) {
          if (pattern.hasMatch(file.lines[i])) {
            violations.add(file.locate(i + 1));
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '字符串判错无法被编译器检查。请改用 AppError 的 sealed 类型 + switch。\n'
            '对应旧版问题：约 15 处 `error.message === "WORD_NOT_FOUND"`。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });
  });

  group('魔法数字', () {
    test('lib/domain 与 lib/services 不得出现裸数字字面量', () {
      final violations = <String>[];

      for (final dir in <String>['lib/domain', 'lib/services']) {
        for (final file in collectDartFiles(dir)) {
          for (var i = 0; i < file.lines.length; i += 1) {
            final line = file.lines[i];
            if (isCommentOrBlank(line)) continue;
            // 允许行内显式豁免（用于确有必要的局部算术）。
            if (line.contains('// guard:allow-magic')) continue;
            final found = _bareNumbers(line);
            if (found.isNotEmpty) {
              violations.add('${file.locate(i + 1)} 含 ${found.join(", ")}');
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            '数值常量应集中到 lib/core/constants.dart 并具名。\n'
            '对应旧版问题：suggestions/candidates.ts 一个表达式 13 个裸权重。\n'
            '确有必要时在该行加 `// guard:allow-magic` 豁免。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });
  });

  group('常量集中', () {
    test('时间单位常量自洽', () {
      // 这组常量被几乎所有模块引用，算错会静默污染全部时间逻辑。
      expect(secondMs, 1000);
      expect(minuteMs, 60 * secondMs);
      expect(hourMs, 60 * minuteMs);
      expect(dayMs, 24 * hourMs);
      expect(weekMs, 7 * dayMs);
    });
  });
}

List<SourceFile> _allLibFiles() => collectDartFiles('lib');

bool _looksLikeConstructor(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('const ') && !trimmed.startsWith('  const ')) {
    if (!trimmed.contains('({') && !trimmed.contains('({')) return false;
  }
  // 形如 `const Foo({` 或 `Foo({`，且不是函数调用。
  return RegExp(r'^\s*(const\s+)?[A-Z][A-Za-z0-9_]*\s*\(\s*\{').hasMatch(line);
}

int _countParameters(String line) {
  final start = line.indexOf('{');
  if (start < 0) return 0;
  final body = line.substring(start + 1);
  // 统计顶层逗号数量，再 +1（无参数时为 0）。
  var depth = 0;
  var commas = 0;
  var hasContent = false;
  for (var i = 0; i < body.length; i += 1) {
    final char = body[i];
    if (char == '(' || char == '[' || char == '{') depth += 1;
    if (char == ')' || char == ']' || char == '}') {
      if (depth == 0) break;
      depth -= 1;
    }
    if (depth == 0 && char == ',') commas += 1;
    if (!_isWhitespace(char) && char != ',') hasContent = true;
  }
  return hasContent ? commas + 1 : 0;
}

bool _isWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

/// 提取一行中「非 0/1/-1」的裸数字字面量。
///
/// 跳过标识符内的数字（如 `base64`）、字符串与注释内容。
List<String> _bareNumbers(String line) {
  final code = _stripStringsAndComments(line);
  final result = <String>[];
  final pattern = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])');

  for (final match in pattern.allMatches(code)) {
    final value = match.group(1)!;
    if (value == '0' || value == '1') continue;
    result.add(value);
  }
  return result;
}

/// 去掉行内的字符串字面量与行尾注释，避免误报。
String _stripStringsAndComments(String line) {
  final buffer = StringBuffer();
  var inSingle = false;
  var inDouble = false;

  for (var i = 0; i < line.length; i += 1) {
    final char = line[i];
    if (char == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (char == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (!inSingle && !inDouble) {
      if (char == '/' && i + 1 < line.length && line[i + 1] == '/') break;
      buffer.write(char);
    }
  }
  return buffer.toString();
}
