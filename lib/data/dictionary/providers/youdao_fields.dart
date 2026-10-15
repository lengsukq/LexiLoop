/// 有道页面的逐字段解析。
///
/// 对应旧版 `modules/dictionary/providers/youdao-fields.ts`，
/// 逐字段与 `tests/unit/youdao-provider.test.ts` 的断言对齐。
///
/// **为什么字段解析与 provider 分开**：解析是纯函数（HTML/文本行 → 字段），
/// 网络与重试是副作用；分开之后解析可以对着旧版单测里的真实 HTML 片段
/// 逐字段断言，不需要任何网络桩。
library;

import 'package:lexiloop/data/dictionary/html_text.dart';

/// 词性行的形态：`n. 招呼，问候`。
final RegExp youdaoPosPattern = RegExp(
  r'^(n|v|adj|adv|prep|conj|int|pron|art|num|aux|det|abbr)\.\s*(.+)$',
);

/// 词形变化的行首标签 → 变化类型。
const Map<String, String> youdaoFormLabels = <String, String>{
  '复数': 'PLURAL',
  '第三人称单数': 'THIRD_PERSON',
  '现在分词': 'PRESENT_PARTICIPLE',
  '过去式': 'PAST',
  '过去分词': 'PAST_PARTICIPLE',
  '比较级': 'COMPARATIVE',
  '最高级': 'SUPERLATIVE',
};

/// 有道页面上的栏目名，用于终止逐行扫描。
const Set<String> youdaoSectionHeadings = <String>{
  '网络释义',
  '英英释义',
  '专业释义',
  '同近义词',
  '同根词',
  '词源',
  '短语',
  '词典短语',
  '双语例句',
  '原声例句',
  '权威例句',
  '百科',
  '有道翻译',
};

/// 词典字段的来源标识。
const String youdaoDictionarySource = 'youdao';

/// 直译结果的来源标识。
const String youdaoTranslationSource = 'youdao:translation';

/// 双语例句的来源标识。
const String youdaoExampleSource = 'youdao:example';

/// 原声例句的来源标识。
const String youdaoAudioExampleSource = 'youdao:audio-example';

/// 权威例句的来源标识。
const String youdaoAuthorityExampleSource = 'youdao:authority-example';

/// 词典短语的来源标识。
const String youdaoPhraseSource = 'youdao:phrase';

/// 网络释义的来源标识。
const String youdaoNetworkSource = 'youdao:network';

/// 英英释义的来源标识。
const String youdaoEnDefinitionSource = 'youdao:en-definition';

/// 同根词的来源标识。
const String youdaoWordFamilySource = 'youdao:word-family';

/// 该行是否是栏目名或页脚提示。
bool isYoudaoSectionHeading(String line) =>
    youdaoSectionHeadings.contains(line.trim()) ||
    RegExp('^(更多|查看|以上为机器翻译)').hasMatch(line.trim());

/// 解析音标（英/美）与有道发音音频地址。
///
/// 优先读 HTML 里的 `class="phonetic"` 节点（新版页面），
/// 回退到纯文本行（旧版页面），两条路径都保留是因为旧单测同时覆盖两者。
List<Map<String, Object?>> parseYoudaoPhonetics(
  List<String> lines,
  String term,
  String html,
) {
  final text = lines.join(' ');
  final trimmedTerm = term.trim();
  final audioBase = trimmedTerm.isEmpty
      ? null
      : 'https://dict.youdao.com/dictvoice?audio='
            '${Uri.encodeComponent(trimmedTerm)}';
  final uk = _phoneticFromHtml(html, '英') ?? _phoneticFromText(text, '英');
  final us = _phoneticFromHtml(html, '美') ?? _phoneticFromText(text, '美');
  final result = <Map<String, Object?>>[];
  if (uk != null) {
    result.add(_phonetic(uk, 'UK', audioBase));
  }
  if (us != null) {
    result.add(_phonetic(us, 'US', audioBase));
  }
  return result;
}

Map<String, Object?> _phonetic(String phonetic, String accent, String? base) {
  final type = accent == 'UK' ? '1' : '2';
  return <String, Object?>{
    'accent': accent,
    'phonetic': phonetic,
    'audioUrl': base == null ? null : '$base&type=$type',
    'source': youdaoDictionarySource,
    'isSynthetic': false,
  };
}

String? _phoneticFromHtml(String html, String label) {
  final match = RegExp(
    '$label\\s*<span[^>]*class="phonetic"[^>]*>([^<]+)</span>',
  ).firstMatch(html);
  final raw = match?.group(1);
  if (raw == null) return null;
  final cleaned = decodeHtmlEntities(raw)
      .replaceAll(RegExp(r'[\[\]]'), '')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

String? _phoneticFromText(String text, String label) {
  final bracketed = RegExp('$label\\s*[\\[/]\\s*([^\\]/]+?)\\s*\\]')
      .firstMatch(text);
  final slashed = RegExp('$label\\s*/\\s*([^/]+?)\\s*/').firstMatch(text);
  final value = (bracketed?.group(1) ?? slashed?.group(1))?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// 解析简明释义（`n. 招呼，问候`）。
List<Map<String, Object?>> parseYoudaoDefinitions(
  List<String> lines,
  String language,
) {
  var active = false;
  final result = <Map<String, Object?>>[];
  for (final raw in lines) {
    final line = raw.trim();
    if (line == '简明' || line == '词典释义') active = true;
    if (isYoudaoSectionHeading(line) && line != '词典释义' && line != '简明') {
      active = false;
    }
    final match = youdaoPosPattern.firstMatch(line);
    final text = match?.group(2)?.trim();
    if (text == null || text.isEmpty || (!active && match == null)) continue;
    result.add(<String, Object?>{
      'language': language,
      'partOfSpeech': match?.group(1),
      'text': text,
      'source': youdaoDictionarySource,
      'isUserEdited': false,
    });
  }
  return result;
}

/// 解析词形变化（复数 / 过去式 / …）。
List<Map<String, Object?>> parseYoudaoWordForms(List<String> lines) {
  final result = <Map<String, Object?>>[];
  String? pending;
  for (final raw in lines) {
    final line = raw.trim();
    for (final entry in youdaoFormLabels.entries) {
      final match = RegExp('^${entry.key}\\s+(.+)\$').firstMatch(line);
      final value = match?.group(1)?.trim();
      if (value == null || value.isEmpty) continue;
      result.add(<String, Object?>{
        'type': entry.value,
        'value': value,
        'source': youdaoDictionarySource,
      });
      pending = null;
    }
    final label = youdaoFormLabels[line];
    if (label != null) {
      pending = label;
      continue;
    }
    if (pending == null || line.isEmpty) continue;
    if (isYoudaoSectionHeading(line)) continue;
    if (RegExp(r'^\d+$').hasMatch(line)) continue;
    if (isChineseText(line)) continue;
    result.add(<String, Object?>{
      'type': pending,
      'value': line,
      'source': youdaoDictionarySource,
    });
    pending = null;
  }
  return result;
}

/// 解析双语 / 原声 / 权威例句（英文句 + 中文译文成对出现）。
List<Map<String, Object?>> parseYoudaoExamples(
  List<String> lines,
  String term,
) {
  final result = <Map<String, Object?>>[];
  String? source;
  Map<String, Object?>? pending;
  for (final raw in lines) {
    final line = raw.trim();
    final nextSource = _exampleSource(line);
    if (nextSource != null) {
      source = nextSource;
      continue;
    }
    if (source != null && _endsExampleSection(line)) source = null;
    if (source == null) continue;
    final clean = _cleanExampleLine(line);
    if (clean.isEmpty || RegExp(r'^《[^》]+》$').hasMatch(clean)) continue;
    if (RegExp(r'^\d+$').hasMatch(clean)) continue;
    if (pending != null && isChineseText(clean)) {
      pending['translation'] = clean;
      pending = null;
      continue;
    }
    if (!matchesTerm(clean, term) || isChineseText(clean)) continue;
    if (clean.length < _minExampleChars) continue;
    final sentence = clean
        .replaceAll(RegExp(r'\s+[\u3400-\u9fff].*$'), '')
        .trim();
    if (sentence.length < _minExampleChars) continue;
    pending = <String, Object?>{
      'sentence': sentence,
      'translation': null,
      'source': source,
      'isUserAdded': false,
    };
    result.add(pending);
  }
  return result;
}

/// 例句最短字符数——更短的「句子」通常是页面上的按钮文案。
const int _minExampleChars = 5;

String? _exampleSource(String line) {
  if (line == '双语例句') return youdaoExampleSource;
  if (line == '原声例句') return youdaoAudioExampleSource;
  if (line == '权威例句') return youdaoAuthorityExampleSource;
  return null;
}

bool _endsExampleSection(String line) =>
    line.contains('查看更多') || line == '词典短语' || line == '同近义词' || line == '百科';

String _cleanExampleLine(String line) => line
    .replaceAll(RegExp(r'^\d+[.、]?\s*'), '')
    .replaceAll(RegExp(r'^\[?点击发音\]?\s*'), '')
    .replaceAll(RegExp(r'\s*点击发音.*$'), '')
    .trim();

/// 解析短语列表（网络释义 / 词典短语两栏）。
List<Map<String, Object?>> parseYoudaoPhrases(List<String> lines) {
  final result = <Map<String, Object?>>[];
  String? source;
  var index = 0;
  while (index < lines.length) {
    final line = lines[index].trim();
    final nextSource = _phraseSource(line);
    if (nextSource != null) {
      source = nextSource;
      index += 1;
      continue;
    }
    if (source != null && _endsPhraseSection(line)) {
      source = null;
      index += 1;
      continue;
    }
    if (source == null || line.isEmpty) {
      index += 1;
      continue;
    }
    if (RegExp(r'^\d+$').hasMatch(line) || isYoudaoSectionHeading(line)) {
      index += 1;
      continue;
    }
    final next = index + 1 < lines.length ? lines[index + 1].trim() : '';
    final inline = RegExp(r'^(.+?)([\u3400-\u9fff].+)$').firstMatch(line);
    final phrase = (inline?.group(1) ?? line)
        .replaceAll(RegExp(r'^[-•]\s*'), '')
        .trim();
    final translation =
        (inline?.group(2) ??
                (RegExp(r'^[\u3400-\u9fff]').hasMatch(next) ? next : ''))
            .replaceAll(RegExp(r'^[；;，,、\s]+'), '')
            .trim();
    final consumedNext = inline?.group(2) == null && translation.isNotEmpty;
    if (_acceptsPhrase(phrase, translation)) {
      result.add(<String, Object?>{
        'phrase': phrase,
        'translation': translation.isEmpty ? null : translation,
        'source': source,
      });
    }
    index += consumedNext ? 2 : 1;
  }
  return result;
}

bool _acceptsPhrase(String phrase, String translation) {
  if (!RegExp('^[a-zA-Z]').hasMatch(phrase)) return false;
  if (phrase.length < 2 || phrase.length > 100) return false;
  if (translation.isEmpty && phrase.split(RegExp(r'\s+')).length < 2) {
    return false;
  }
  return true;
}

String? _phraseSource(String line) {
  if (line == '网络释义') return youdaoNetworkSource;
  if (line == '短语' || line == '词典短语') return youdaoPhraseSource;
  return null;
}

bool _endsPhraseSection(String line) =>
    line == '双语例句' ||
    line == '原声例句' ||
    line == '权威例句' ||
    line == '同近义词' ||
    line == '百科';

/// 从「网络释义 / 词典短语」里取短语的中文含义。
///
/// 短语页面通常没有词性行，`parseYoudaoDefinitions` 什么也找不到，
/// 网络释义里的 `The proportion of …的比例` 是唯一可用含义。
Map<String, Object?>? parseYoudaoPhraseDefinition(
  List<String> lines,
  String term,
  String language,
) =>
    _scanPhraseDefinition(lines, term, language, false) ??
    _scanPhraseDefinition(lines, term, language, true);

Map<String, Object?>? _scanPhraseDefinition(
  List<String> lines,
  String term,
  String language,
  bool allowExtension,
) {
  final normalizedTerm = term.trim().toLowerCase();
  if (normalizedTerm.isEmpty) return null;
  String? source;
  var index = 0;
  while (index < lines.length) {
    final line = lines[index].trim();
    final nextSource = _phraseSource(line);
    if (nextSource != null) {
      source = nextSource;
      index += 1;
      continue;
    }
    if (source != null && _endsPhraseDefinitionSection(line)) {
      source = null;
      index += 1;
      continue;
    }
    if (source == null || line.isEmpty) {
      index += 1;
      continue;
    }
    if (RegExp(r'^\d+$').hasMatch(line) || isYoudaoSectionHeading(line)) {
      index += 1;
      continue;
    }
    final head = _phraseHead(line);
    if (head == null) {
      index += 1;
      continue;
    }
    if (!_phraseMatches(head, normalizedTerm, allowExtension)) {
      index += 1;
      continue;
    }
    final next = index + 1 < lines.length ? lines[index + 1].trim() : '';
    final text = _readPhraseTranslation(line, next, language);
    if (text.isEmpty) {
      index += 1;
      continue;
    }
    return <String, Object?>{'text': text, 'source': source};
  }
  return null;
}

bool _endsPhraseDefinitionSection(String line) =>
    line == '双语例句' ||
    line == '原声例句' ||
    line == '权威例句' ||
    line == '同近义词' ||
    line == '同根词' ||
    line == '百科';

String? _phraseHead(String line) {
  final stripped = line
      .replaceAll(RegExp(r'^\d+[.、]?\s*'), '')
      .replaceAll(RegExp(r'^[-•]\s*'), '');
  final match = RegExp(r"^([a-zA-Z][a-zA-Z\s'-]*)").firstMatch(stripped);
  final head = match?.group(1)?.trim();
  return head == null || head.isEmpty ? null : head;
}

bool _phraseMatches(String head, String normalizedTerm, bool allowExtension) {
  final normalizedHead = head.toLowerCase();
  if (normalizedHead == normalizedTerm) return true;
  return allowExtension &&
      normalizedTerm.contains(' ') &&
      normalizedHead.startsWith('$normalizedTerm ');
}

String _readPhraseTranslation(String line, String next, String language) {
  final inline = RegExp(r'^(.+?)([…⋯]*[\u3400-\u9fff].+)$').firstMatch(line);
  final hasNextTranslation = RegExp(r'^[…⋯]*[\u3400-\u9fff]').hasMatch(next);
  final raw = (inline?.group(2) ?? (hasNextTranslation ? next : ''))
      .replaceAll(RegExp(r'^[；;，,、：:\s]+'), '')
      .trim();
  if (raw.isEmpty) return '';
  final containsCjk = isChineseText(raw);
  final wantsCjk = language.toLowerCase().startsWith('zh');
  return wantsCjk == containsCjk ? raw : '';
}

/// 解析「有道翻译」直译块。
Map<String, Object?>? parseYoudaoTranslation(
  List<String> lines,
  String term,
  String language,
) {
  final marker = lines.indexWhere(
    (line) => line == '有道翻译' || line.contains('有道翻译'),
  );
  if (marker < 0) return null;
  final normalizedTerm = term.trim().toLowerCase();
  final end = marker + 1 + _translationLookahead;
  for (final candidate in lines.sublist(
    marker + 1,
    end > lines.length ? lines.length : end,
  )) {
    final value = candidate.replaceAll(RegExp(r'^[：:、\s]+'), '').trim();
    if (value.isEmpty || value.toLowerCase() == normalizedTerm) continue;
    if (isYoudaoSectionHeading(value)) continue;
    if (value.startsWith('以上为机器翻译')) continue;
    if (value == '长、整句建议使用人工翻译') continue;
    final wantsCjk = language.toLowerCase().startsWith('zh');
    if (wantsCjk == isChineseText(value)) {
      return <String, Object?>{
        'translation': value,
        'source': youdaoTranslationSource,
      };
    }
  }
  return null;
}

/// 直译块最多向后看几行。
const int _translationLookahead = 7;

/// 解析英英释义（`id="tEETrans"` 区块）。
List<Map<String, Object?>> parseYoudaoEnDefinitions(String html) {
  final section = RegExp(r'id="tEETrans"[\s\S]*?</ul>\s*</div>')
      .firstMatch(html)
      ?.group(0);
  if (section == null) return const <Map<String, Object?>>[];
  final byPos = _enDefinitionsByPos(section);
  if (byPos.isNotEmpty) return byPos;
  final result = <Map<String, Object?>>[];
  for (final match in RegExp(
    '<span class="def">([^<]+)</span>',
  ).allMatches(section)) {
    final text = decodeHtmlEntities(match.group(1)!).trim();
    if (text.isEmpty) continue;
    result.add(_enDefinition(text, null));
  }
  return result;
}

List<Map<String, Object?>> _enDefinitionsByPos(String section) {
  final blocks = section.split('<span class="pos">');
  if (blocks.length <= 1) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  for (final block in blocks.skip(1)) {
    final posRaw = decodeHtmlEntities(
      stripHtmlTags(block.split('</span>').first),
    ).trim().replaceAll(RegExp(r'\.$'), '');
    final pos = RegExp(r'^[a-zA-Z]+$').hasMatch(posRaw) && posRaw.isNotEmpty
        ? posRaw
        : null;
    var found = false;
    for (final match in RegExp(
      '<span class="def">([^<]+)</span>',
    ).allMatches(block)) {
      final text = decodeHtmlEntities(match.group(1)!).trim();
      if (text.isEmpty) continue;
      found = true;
      result.add(_enDefinition(text, pos));
    }
    if (!found) continue;
  }
  return result;
}

Map<String, Object?> _enDefinition(String text, String? partOfSpeech) =>
    <String, Object?>{
      'language': 'en',
      'partOfSpeech': partOfSpeech,
      'text': text,
      'source': youdaoEnDefinitionSource,
      'isUserEdited': false,
    };

/// 解析同近义词（`id="synonyms"` 区块）。
List<Map<String, Object?>> parseYoudaoSynonymsFromHtml(String html) {
  final section =
      _section(html, 'id="synonyms"', 'id="relWordTab"') ??
      _section(html, 'id="synonyms"', null);
  if (section == null) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final match in RegExp(
    '<a[^>]*class="search-js"[^>]*>([^<]+)</a>',
  ).allMatches(section)) {
    final word = decodeHtmlEntities(match.group(1)!.trim());
    if (!_isPlainWord(word, maxLength: _maxRelatedWordLength)) continue;
    if (!seen.add(word.toLowerCase())) continue;
    result.add(<String, Object?>{
      'word': word,
      'translation': null,
      'partOfSpeech': null,
      'relation': 'SYNONYM',
      'source': youdaoDictionarySource,
      'difference': null,
    });
  }
  return result;
}

/// 同近义词 / 同根词单词的长度上限。
const int _maxRelatedWordLength = 40;

bool _isPlainWord(String word, {required int maxLength}) {
  if (word.length < 2 || word.length > maxLength) return false;
  return RegExp(r"^[a-zA-Z][a-zA-Z\s'-]*$").hasMatch(word);
}

/// 解析同根词（`id="relWordTab"` 区块）。
List<Map<String, Object?>> parseYoudaoWordFamilyFromHtml(String html) {
  final section =
      _section(html, 'id="relWordTab"', 'id="discriminate"') ??
      _section(html, 'id="relWordTab"', null);
  if (section == null) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  String? currentPos;
  for (final block in section.split('<p class="wordGroup">')) {
    final end = block.indexOf('</p>');
    if (end < 0) continue;
    final inner = block.substring(0, end);
    final textOnly = stripHtmlTags(inner);
    if (RegExp(r'^\s*词根\s*[:：]?\s*$').hasMatch(textOnly)) continue;
    final pos = _posFromLine(textOnly);
    if (pos != null) {
      currentPos = pos;
      continue;
    }
    if (!inner.contains('<a')) continue;
    final anchor = RegExp('<a[^>]*>([^<]+)</a>').firstMatch(inner);
    final word = anchor == null
        ? ''
        : decodeHtmlEntities(anchor.group(1)!.trim());
    if (!RegExp(r"^[a-zA-Z][a-zA-Z'-]*$").hasMatch(word)) continue;
    if (!seen.add('${word.toLowerCase()}|${currentPos ?? ''}')) continue;
    final tail = inner.substring(anchor!.end);
    final translation = decodeHtmlEntities(stripHtmlTags(tail))
        .replaceAll(RegExp(r'^[；;，,、\s]+'), '')
        .trim();
    result.add(<String, Object?>{
      'word': word,
      'translation': translation.isEmpty ? null : translation,
      'partOfSpeech': currentPos,
      'relation': 'WORD_FAMILY',
      'source': youdaoWordFamilySource,
      'difference': null,
    });
  }
  return result;
}

String? _posFromLine(String text) {
  final trimmed = text
      .replaceAll(RegExp(r'^\s*词根\s*[:：]?\s*$'), '')
      .trim()
      .toLowerCase();
  if (trimmed.isEmpty) return null;
  if (!RegExp(r'^(adj|n|v|adv|prep|conj|int|pron|art|num)\.?$')
      .hasMatch(trimmed)) {
    return null;
  }
  return trimmed.replaceAll('.', '');
}

/// 解析短语区块（`id="wordGroup"`）。
List<Map<String, Object?>> parseYoudaoPhrasesFromHtml(String html) {
  final section =
      _section(html, 'id="wordGroup"', 'id="synonyms"') ??
      _section(html, 'id="wordGroup"', null);
  if (section == null) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  final pattern = RegExp(
    r'<p class="wordGroup">[\s\S]*?<a[^>]*>([^<]+)</a>([\s\S]*?)</p>',
  );
  for (final match in pattern.allMatches(section)) {
    final phrase = decodeHtmlEntities(match.group(1)!.trim());
    final translation = decodeHtmlEntities(stripHtmlTags(match.group(2)!))
        .replaceAll(RegExp(r'^[；;，,、\s]+'), '')
        .trim();
    if (phrase.length < 2 || phrase.length > 80) continue;
    if (!RegExp('^[a-zA-Z]').hasMatch(phrase)) continue;
    result.add(<String, Object?>{
      'phrase': phrase,
      'translation': translation.isEmpty ? null : translation,
      'source': youdaoPhraseSource,
    });
  }
  return result;
}

/// 解析考试标签（初中 / 高中 / CET4 / CET6 / 考研 / 四级 / 六级）。
List<String> parseYoudaoTags(List<String> lines) {
  final levelPattern = RegExp('初中|高中|CET4|CET6|考研|四级|六级');
  final tagPattern = RegExp(r'^(初中|高中|CET4|CET6|考研|四级|六级)$');
  String? levelLine;
  for (final line in lines) {
    if (levelPattern.hasMatch(line)) {
      levelLine = line;
      break;
    }
  }
  if (levelLine == null) return const <String>[];
  final tags = <String>{};
  for (final value in levelLine.split(RegExp(r'[/、，,\s]+'))) {
    final trimmed = value.trim();
    if (tagPattern.hasMatch(trimmed)) tags.add(trimmed);
  }
  return tags.toList(growable: false);
}

/// 从 `start` 到 `endAnchor`（或到区块末尾）截取一段 HTML。
String? _section(String html, String start, String? endAnchor) {
  final startIndex = html.indexOf(start);
  if (startIndex < 0) return null;
  if (endAnchor == null) {
    final match = RegExp('${RegExp.escape(start)}[\\s\\S]*?</div>')
        .firstMatch(html.substring(startIndex));
    return match?.group(0);
  }
  final endIndex = html.indexOf(endAnchor, startIndex);
  if (endIndex < 0) return null;
  return html.substring(startIndex, endIndex);
}
