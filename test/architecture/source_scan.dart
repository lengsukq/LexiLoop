/// 架构守卫测试的源码扫描工具。
///
/// 这些测试**不测行为，只测结构**——把 `docs/CLEAN_CODE_BASELINE.md` 记录的
/// 问题类型变成 CI 会拦下的硬约束，而不是依赖人工评审。
///
/// 实现方式是直接读 `lib/` 下的源码文本做静态检查。比引入
/// `custom_lint`（与当前 riverpod 版本存在 analyzer 依赖死锁）更轻，
/// 也不需要额外依赖。
library;

import 'dart:io';

/// 一个源码文件及其行。
class SourceFile {
  /// 从路径与内容构造。
  new(this.path, this.lines);

  /// 相对仓库根目录的路径。
  final String path;

  /// 按行拆分的内容（1-based 访问请用 `lineAt`）。
  final List<String> lines;

  /// 取第 [lineNumber] 行（1-based），越界返回空串。
  String lineAt(int lineNumber) {
    if (lineNumber < 1 || lineNumber > lines.length) return '';
    return lines[lineNumber - 1];
  }

  /// 返回 `路径:行号` 形式，用于断言失败时的定位信息。
  String locate(int lineNumber) => '$path:$lineNumber';
}

/// 递归收集 [directory] 下的所有 `.dart` 文件。
///
/// 自动跳过生成文件（`*.g.dart` / `*.freezed.dart`），它们不由人手维护。
List<SourceFile> collectDartFiles(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return <SourceFile>[];

  final result = <SourceFile>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    if (!path.endsWith('.dart')) continue;
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
    result.add(SourceFile(_relative(path), entity.readAsLinesSync()));
  }
  result.sort((a, b) => a.path.compareTo(b.path));
  return result;
}

String _relative(String path) {
  const libMarker = '/lib/';
  final libIndex = path.indexOf(libMarker);
  if (libIndex >= 0) {
    return 'lib/${path.substring(libIndex + libMarker.length)}';
  }
  const testMarker = '/test/';
  final testIndex = path.indexOf(testMarker);
  if (testIndex >= 0) {
    return 'test/${path.substring(testIndex + testMarker.length)}';
  }
  return path;
}

/// 一段被大括号包裹的代码块（函数、方法或构造函数）。
class CodeBlock {
  /// 从签名行与结束行构造。
  new({
    required this.file,
    required this.startLine,
    required this.endLine,
    required this.signature,
  });

  /// 所属文件。
  final SourceFile file;

  /// 签名所在行（1-based）。
  final int startLine;

  /// 结束大括号所在行（1-based）。
  final int endLine;

  /// 签名文本。
  final String signature;

  /// 代码块总行数（含签名与结束括号）。
  int get lineCount => endLine - startLine + 1;

  /// `路径:行号 签名摘要`，用于断言消息。
  String describe() {
    final trimmed = signature.trim();
    final short = trimmed.length > 70
        ? '${trimmed.substring(0, 70)}…'
        : trimmed;
    return '${file.locate(startLine)} → $short（$lineCount 行）';
  }
}

/// 找出文件中所有「函数体」代码块。
///
/// 判定方式：某行以 `{` 结尾且该行看起来像函数/方法签名（含 `(`），
/// 随后按大括号配对找到结束行。这是一组启发式规则，对格式化过的
/// Dart 代码足够可靠。
List<CodeBlock> findFunctionBlocks(SourceFile file) {
  final blocks = <CodeBlock>[];
  var index = 0;

  while (index < file.lines.length) {
    final line = file.lines[index];
    if (!_looksLikeSignature(line)) {
      index += 1;
      continue;
    }

    final end = _matchBrace(file, index);
    if (end == null) {
      index += 1;
      continue;
    }

    blocks.add(
      CodeBlock(
        file: file,
        startLine: index + 1,
        endLine: end + 1,
        signature: line,
      ),
    );
    index = end + 1;
  }

  return blocks;
}

bool _looksLikeSignature(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('//') || trimmed.startsWith('///')) return false;
  if (trimmed.startsWith('*')) return false;
  // 以 `}` 开头的是**上一个块的续行**（`} else if (...) {`、
  // `} on Foo catch (e) {`、`} finally {`）。它们含括号也以 `{` 结尾，
  // 但绝不是函数签名；不排除的话会把整个后续块算成一个「超长函数」。
  if (trimmed.startsWith('}')) return false;
  if (!trimmed.endsWith('{')) return false;
  // 函数签名一定含参数列表；排除 `if (x) {`、`for (...) {` 等控制流。
  if (!trimmed.contains('(')) return false;
  const controlKeywords = <String>[
    'if ',
    'if(',
    'for ',
    'for(',
    'while ',
    'while(',
    'switch ',
    'switch(',
    'catch ',
    'catch(',
    'else ',
    'try ',
    'on ',
    'finally ',
  ];
  for (final keyword in controlKeywords) {
    if (trimmed.startsWith(keyword)) return false;
  }
  return true;
}

/// 从 [startIndex]（0-based，签名行）起按大括号配对，返回结束行下标。
int? _matchBrace(SourceFile file, int startIndex) {
  var depth = 0;
  var seenOpen = false;

  for (var i = startIndex; i < file.lines.length; i += 1) {
    final line = file.lines[i];
    for (var c = 0; c < line.length; c += 1) {
      final char = line[c];
      if (char == '{') {
        depth += 1;
        seenOpen = true;
      } else if (char == '}') {
        depth -= 1;
        if (seenOpen && depth == 0) return i;
      }
    }
  }
  return null;
}

/// 判断某行是否处于字符串或注释中，用于跳过误报。
///
/// 仅处理最常见的单行情形，够用即可。
bool isCommentOrBlank(String line) {
  final trimmed = line.trim();
  return trimmed.isEmpty ||
      trimmed.startsWith('//') ||
      trimmed.startsWith('///') ||
      trimmed.startsWith('*') ||
      trimmed.startsWith('/*');
}
