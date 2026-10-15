/// HTML → 文本的工具函数。
///
/// 对应旧版 `youdao-parser.ts` / `youdao-fields.ts` / `iciba-fields.ts` 里
/// 各自重复了一遍的实体解码与标签剥离逻辑。
///
/// **为什么不用 `package:html`**：`pubspec.yaml` 没有该依赖，且任务约束
/// 禁止新增依赖。这里只需要「取纯文本行」与「剥标签」两件事，正则足够；
/// 真正的字段定位由各 provider 用更精确的 `id="..."` 锚点完成。
library;

/// HTML 命名实体与数字实体解码。
String decodeHtmlEntities(String value) => value
    .replaceAll(RegExp('&nbsp;', caseSensitive: false), ' ')
    .replaceAll(RegExp('&amp;', caseSensitive: false), '&')
    .replaceAll(RegExp('&lt;', caseSensitive: false), '<')
    .replaceAll(RegExp('&gt;', caseSensitive: false), '>')
    .replaceAll(RegExp('&quot;', caseSensitive: false), '"')
    .replaceAllMapped(
      RegExp('&#x([0-9a-fA-F]+);'),
      (match) => _fromCodePoint(int.tryParse(match.group(1)!, radix: 16)),
    )
    .replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => _fromCodePoint(int.tryParse(match.group(1)!)),
    );

/// 剥离全部 HTML 标签并去除首尾空白。
String stripHtmlTags(String value) =>
    value.replaceAll(RegExp('<[^>]+>'), '').trim();

/// 把 HTML 拆成「块级元素一行」的纯文本行。
///
/// 有道与爱词霸的页面结构差异极大，但都靠块级换行区分语义行；
/// 先把结构拍平成行，字段解析才能用统一的逐行扫描实现。
List<String> extractTextLines(String html) {
  var text = html
      .replaceAll(
        RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<noscript[^>]*>[\s\S]*?</noscript>', caseSensitive: false),
        '',
      );
  const blockTags =
      'div|p|li|ul|ol|h[1-6]|section|article|tr|td|th|dl|dt|dd|blockquote|pre';
  text = text
      .replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp('</($blockTags)[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp('<($blockTags)[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp('<[^>]+>'), '');
  final result = <String>[];
  for (final line in decodeHtmlEntities(
    text,
  ).replaceAll('**', '').split('\n')) {
    final normalized = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isNotEmpty) result.add(normalized);
  }
  return result;
}

/// 文本是否以中日韩统一表意文字为主。
///
/// 用来区分「英文例句」与「中文译文」，与旧版 `isChineseLine` 一致。
bool isChineseText(String value) => RegExp(r'[\u3400-\u9fff]').hasMatch(value);

/// 句子中是否出现目标词条（按词边界匹配单个词，按子串匹配多词短语）。
bool matchesTerm(String sentence, String term) {
  final normalizedTerm = term.trim().toLowerCase();
  if (normalizedTerm.isEmpty) return false;
  final haystack = sentence.toLowerCase();
  if (normalizedTerm.contains(' ')) return haystack.contains(normalizedTerm);
  final escaped = RegExp.escape(normalizedTerm);
  return RegExp('(?:^|[^a-z])$escaped(?:\$|[^a-z])').hasMatch(haystack);
}

String _fromCodePoint(int? code) {
  if (code == null || code < 0 || code > _maxCodePoint) return '';
  return String.fromCharCode(code);
}

/// Unicode 码点上限。
const int _maxCodePoint = 0x10FFFF;
