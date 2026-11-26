/// 从模型输出里提取 JSON。
///
/// 对应旧版 `src/lib/json.ts` 的 `extractJson`。
///
/// **为什么要容错**：即便要求「只输出一个 JSON 对象」，免费网关与
/// 小参数模型仍会带上 Markdown 代码围栏、前后解释或省略外层括号。
/// 直接 `jsonDecode` 会把可用结果整体判死。
library;

import 'dart:convert';

/// 从文本中提取第一个可解析的 JSON 值；提取不到返回 `null`。
Object? extractJsonValue(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final candidates = <String>[trimmed];
  final fenced = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  ).firstMatch(trimmed)?.group(1);
  if (fenced != null) candidates.add(fenced.trim());
  final braced = _sliceBalanced(trimmed, '{', '}');
  if (braced != null) candidates.add(braced);
  final bracketed = _sliceBalanced(trimmed, '[', ']');
  if (bracketed != null) candidates.add(bracketed);
  for (final candidate in candidates) {
    final decoded = _tryDecode(candidate);
    if (decoded != null) return decoded;
  }
  return null;
}

Object? _tryDecode(String text) {
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

String? _sliceBalanced(String text, String open, String close) {
  final start = text.indexOf(open);
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < text.length; index += 1) {
    final character = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        inString = false;
      }
      continue;
    }
    if (character == '"') {
      inString = true;
      continue;
    }
    if (character == open) depth += 1;
    if (character == close) {
      depth -= 1;
      if (depth == 0) return text.substring(start, index + 1);
    }
  }
  return null;
}
