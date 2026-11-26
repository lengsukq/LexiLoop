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
///
/// **必须单遍替换**：早先的实现是 `replaceAll('&amp;', '&')` 之后再
/// `replaceAll('&lt;', '<')` 这样一条链。链式替换会把上一层**刚生成的**
/// 文本再解一次，于是 `&amp;lt;` 变成 `<` 而不是 `&lt;`——
/// 这正是「双重反转义」的经典缺陷：本来就该显示成字面量 `&lt;` 的内容
/// 被吃掉了两层。
///
/// 这里改成一次扫描：整串只匹配一次，命中的实体直接查表替换，
/// 替换出来的字符不会再被扫描，语义因此与「按 HTML 反转义一次」一致。
String decodeHtmlEntities(String value) {
  if (!value.contains('&')) return value;
  return value.replaceAllMapped(_entityPattern, (match) {
    final body = match.group(1)!;
    if (body.startsWith('#')) return _numericEntity(body) ?? match.group(0)!;
    final replacement = _namedEntities[body.toLowerCase()];
    return replacement ?? match.group(0)!;
  });
}

/// 命不中的实体原样保留（`match.group(0)`），避免把不认识的实体吞掉。
final RegExp _entityPattern = RegExp('&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);');

/// 支持的命名实体。
///
/// 只收 HTML 文本里真正会出现的几个：一份词典的释义与例句不需要
/// 完整的两千多个实体表，而**多收一个用不上的实体反而会让
/// 「为什么这个没解」变得难以回答**。
const Map<String, String> _namedEntities = <String, String>{
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
};

String? _numericEntity(String body) {
  if (body.length < 2) return null;
  final isHex = body[1] == 'x' || body[1] == 'X';
  final digits = isHex ? body.substring(2) : body.substring(1);
  final code = int.tryParse(digits, radix: isHex ? 16 : 10);
  if (code == null) return null;
  return _fromCodePoint(code);
}

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
