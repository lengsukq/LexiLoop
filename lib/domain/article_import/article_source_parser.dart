/// 多源文章输入解析器：纯文本、Markdown、字幕（SRT / VTT）与 HTML 网页正文。
///
/// 本文件必须保持纯 Dart，不依赖 Flutter、dio 或 `dart:io`，便于在全平台与单测中直接复用。
library;

import 'package:lexiloop/core/constants.dart';

/// 识别出的文章来源格式。
enum ArticleSourceFormat {
  /// 纯文本。
  plainText,

  /// Markdown 文档。
  markdown,

  /// 字幕文件（SRT / WebVTT）。
  subtitle,

  /// HTML 文档 / 网页。
  html,
}

/// 解析后的文章正文与元信息。
class ParsedArticleSource {
  /// 以正文、格式与可选标题构造。
  const new({required this.text, required this.format, this.title});

  /// 清洗后可直接送入分词管线的英文正文。
  final String text;

  /// 识别出的来源格式。
  final ArticleSourceFormat format;

  /// 提取出的文档标题（网页 `<title>` 或 Markdown 一级标题，可能为空）。
  final String? title;
}

/// 判断单行文本是否像一个可抓取的 HTTP(S) 链接。
bool looksLikeHttpUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.contains('\n') || trimmed.contains(' ')) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  return uri.scheme == 'http' || uri.scheme == 'https';
}

/// 自动识别来源格式并提取适合分词的文章正文。
ParsedArticleSource parseArticleSource(
  String raw, {
  String? filename,
  String? contentType,
}) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final format = detectArticleSourceFormat(
    normalized,
    filename: filename,
    contentType: contentType,
  );
  return switch (format) {
    ArticleSourceFormat.subtitle => ParsedArticleSource(
      text: extractSubtitleText(normalized),
      format: format,
      title: _stripExtension(filename),
    ),
    ArticleSourceFormat.html => _parseHtml(normalized),
    ArticleSourceFormat.markdown => _parseMarkdown(normalized, filename),
    ArticleSourceFormat.plainText => ParsedArticleSource(
      text: _collapseBlankLines(normalized),
      format: format,
      title: _stripExtension(filename),
    ),
  };
}

/// 根据扩展名、MIME 类型与内容特征判断来源格式。
ArticleSourceFormat detectArticleSourceFormat(
  String text, {
  String? filename,
  String? contentType,
}) {
  final ext = _extensionOf(filename);
  if (ext == 'srt' || ext == 'vtt') return ArticleSourceFormat.subtitle;
  if (ext == 'html' || ext == 'htm') return ArticleSourceFormat.html;
  if (ext == 'md' || ext == 'markdown') return ArticleSourceFormat.markdown;
  final mime = contentType?.toLowerCase() ?? '';
  if (mime.contains('html')) return ArticleSourceFormat.html;
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('WEBVTT') || _timestampLine.hasMatch(text)) {
    return ArticleSourceFormat.subtitle;
  }
  if (_looksLikeHtml(trimmed)) return ArticleSourceFormat.html;
  return ArticleSourceFormat.plainText;
}

/// 提取 SRT / WebVTT 字幕正文：去掉序号、时间戳、WebVTT 头、样式标签与重复行。
String extractSubtitleText(String raw) {
  final lines = raw.split('\n');
  final cues = <String>[];
  var skipNote = false;
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      skipNote = false;
      continue;
    }
    if (skipNote) continue;
    if (_isSubtitleNoise(line)) {
      if (line.startsWith('NOTE')) skipNote = true;
      continue;
    }
    final clean = _cleanSubtitleCue(line);
    if (clean.isEmpty) continue;
    if (cues.isEmpty || cues.last != clean) cues.add(clean);
  }
  return _joinSubtitleCues(cues);
}

ParsedArticleSource _parseMarkdown(String raw, String? filename) {
  final titleMatch = _mdHeadingOne.firstMatch(raw);
  final title = titleMatch?.group(1)?.trim() ?? _stripExtension(filename);
  var text = raw
      .replaceAll(_fencedCodeBlock, '\n')
      .replaceAll(_mdImage, ' ')
      .replaceAllMapped(_mdLink, (m) => m.group(1) ?? '')
      .replaceAll(_inlineCode, ' ')
      .replaceAll(_mdHeadingPrefix, '')
      .replaceAll(_mdBlockquotePrefix, '')
      .replaceAll(_mdEmphasis, '');
  text = _collapseBlankLines(text);
  return ParsedArticleSource(
    text: text,
    format: ArticleSourceFormat.markdown,
    title: title,
  );
}

ParsedArticleSource _parseHtml(String html) {
  final titleMatch = _htmlTitle.firstMatch(html);
  final title = titleMatch == null
      ? null
      : _decodeEntities(titleMatch.group(1) ?? '').trim();
  final mainBody = _extractMainContainer(html);
  final primary = _htmlToParagraphs(mainBody);
  final text = primary.length >= articleHtmlMainMinChars
      ? primary
      : _htmlToParagraphs(html);
  return ParsedArticleSource(
    text: text,
    format: ArticleSourceFormat.html,
    title: title != null && title.isNotEmpty ? title : null,
  );
}

String _extractMainContainer(String html) {
  final article = _htmlArticleTag.firstMatch(html);
  if (article != null) return article.group(1) ?? html;
  final main = _htmlMainTag.firstMatch(html);
  if (main != null) return main.group(1) ?? html;
  return html;
}

String _htmlToParagraphs(String html) {
  var cleaned = html
      .replaceAll(_htmlScriptStyle, ' ')
      .replaceAll(_htmlChromeTags, ' ')
      .replaceAll(_htmlComment, ' ')
      .replaceAll(_htmlLineBreak, '\n')
      .replaceAll(_htmlBlockEnd, '\n\n')
      .replaceAll(_htmlTag, ' ');
  cleaned = _decodeEntities(cleaned);
  final paragraphs = <String>[];
  for (final block in cleaned.split(_multiNewline)) {
    final line = block.replaceAll(_whitespaceRun, ' ').trim();
    if (line.isEmpty) continue;
    if (paragraphs.isEmpty || paragraphs.last != line) paragraphs.add(line);
  }
  return paragraphs.join('\n\n');
}

bool _isSubtitleNoise(String line) {
  if (line.startsWith('WEBVTT') ||
      line.startsWith('NOTE') ||
      line.startsWith('STYLE') ||
      line.startsWith('REGION') ||
      line.startsWith('Kind:') ||
      line.startsWith('Language:')) {
    return true;
  }
  if (_pureDigits.hasMatch(line)) return true;
  return _timestampLine.hasMatch(line);
}

String _cleanSubtitleCue(String line) => _decodeEntities(
  line
      .replaceAll(_assStyleTag, '')
      .replaceAll(_htmlTag, '')
      .replaceAll(_whitespaceRun, ' ')
      .trim(),
);

String _joinSubtitleCues(List<String> cues) {
  final paragraphs = <String>[];
  final buffer = StringBuffer();
  for (final cue in cues) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(cue);
    if (_sentenceEnd.hasMatch(cue)) {
      paragraphs.add(buffer.toString().trim());
      buffer.clear();
    }
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) paragraphs.add(tail);
  return paragraphs.join('\n\n');
}

bool _looksLikeHtml(String trimmed) {
  final head = trimmed.toLowerCase();
  return head.startsWith('<!doctype html') ||
      head.startsWith('<html') ||
      (head.contains('<p>') && head.contains('</p>')) ||
      (head.contains('<article') && head.contains('</article>'));
}

String _collapseBlankLines(String text) {
  final blocks = <String>[];
  for (final raw in text.split(_blankLineSplit)) {
    final lines = <String>[
      for (final line in raw.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isNotEmpty) blocks.add(lines.join(' '));
  }
  return blocks.join('\n\n');
}

String _decodeEntities(String value) {
  if (!value.contains('&')) return value;
  return value.replaceAllMapped(_entityPattern, (match) {
    final body = match.group(1)!;
    if (body.startsWith('#')) return _decodeNumericEntity(body) ?? match[0]!;
    return _htmlNamedEntities[body.toLowerCase()] ?? match[0]!;
  });
}

String? _decodeNumericEntity(String body) {
  if (body.length <= 1) return null;
  final hex = body[1] == 'x' || body[1] == 'X';
  final digits = hex ? body.substring(1 + 1) : body.substring(1);
  final code = int.tryParse(digits, radix: hex ? hexRadix : decimalRadix);
  if (code == null || code < 0 || code > maxUnicodeCodePoint) return null;
  return String.fromCharCode(code);
}

String? _extensionOf(String? filename) {
  if (filename == null) return null;
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return null;
  return filename.substring(dot + 1).toLowerCase();
}

String? _stripExtension(String? filename) {
  if (filename == null || filename.trim().isEmpty) return null;
  final clean = filename.trim();
  final dot = clean.lastIndexOf('.');
  return dot > 0 ? clean.substring(0, dot) : clean;
}

final RegExp _timestampLine = RegExp(
  r'\d{1,2}:\d{2}(?::\d{2})?[.,]\d{3}\s*-->\s*\d{1,2}:\d{2}(?::\d{2})?[.,]\d{3}',
);
final RegExp _pureDigits = RegExp(r'^\d+$');
final RegExp _assStyleTag = RegExp(r'\{\\[^}]*\}');
final RegExp _sentenceEnd = RegExp(r'[.!?。！？]["”’\)]?$');
final RegExp _fencedCodeBlock = RegExp(r'```[\s\S]*?```');
final RegExp _inlineCode = RegExp('`[^`]+`');
final RegExp _mdImage = RegExp(r'!\[[^\]]*\]\([^)]+\)');
final RegExp _mdLink = RegExp(r'\[([^\]]+)\]\([^)]+\)');
final RegExp _mdHeadingOne = RegExp(r'^#\s+(.+)$', multiLine: true);
final RegExp _mdHeadingPrefix = RegExp(r'^#{1,6}\s+', multiLine: true);
final RegExp _mdBlockquotePrefix = RegExp(r'^>\s?', multiLine: true);
final RegExp _mdEmphasis = RegExp('[*_~]{1,3}');
final RegExp _htmlTitle = RegExp(
  r'<title[^>]*>([\s\S]*?)</title>',
  caseSensitive: false,
);
final RegExp _htmlArticleTag = RegExp(
  r'<article[^>]*>([\s\S]*?)</article>',
  caseSensitive: false,
);
final RegExp _htmlMainTag = RegExp(
  r'<main[^>]*>([\s\S]*?)</main>',
  caseSensitive: false,
);
final RegExp _htmlScriptStyle = RegExp(
  r'<(script|style|noscript|svg)[^>]*>[\s\S]*?</\1>',
  caseSensitive: false,
);
final RegExp _htmlChromeTags = RegExp(
  r'<(nav|header|footer|aside)[^>]*>[\s\S]*?</\1>',
  caseSensitive: false,
);
final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?-->');
final RegExp _htmlLineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _htmlBlockEnd = RegExp(
  '</(?:p|div|h[1-6]|li|blockquote|section|article|tr)>',
  caseSensitive: false,
);
final RegExp _htmlTag = RegExp('<[^>]+>');
final RegExp _multiNewline = RegExp(r'\n{2,}');
final RegExp _blankLineSplit = RegExp(r'\n\s*\n');
final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _entityPattern = RegExp('&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);');

const Map<String, String> _htmlNamedEntities = <String, String>{
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'mdash': '—',
  'ndash': '–',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
};
