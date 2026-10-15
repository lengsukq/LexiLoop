/// AI 词条内容的归一化、校验与字段转换。
///
/// 对应旧版 `ai-lexical-normalize.ts` 与 `ai-lexical-content.ts`。
///
/// **为什么归一化不能省**：模型输出的枚举大小写、字符串/对象混用、
/// 缺字段是常态。若直接落库，`word_contents` 里会积累无法渲染的条目，
/// 而且下游「字段是否完备」的判定会全部失效。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';

/// 模型输出里可能出现的枚举别名。
const Map<String, String> aiEnumAliases = <String, String>{
  'common': 'COMMON',
  'very_common': 'VERY_COMMON',
  'normal': 'NORMAL',
  'rare': 'RARE',
  'a1': 'A1',
  'a2': 'A2',
  'b1': 'B1',
  'b2': 'B2',
  'c1': 'C1',
  'c2': 'C2',
  'formal': 'FORMAL',
  'informal': 'INFORMAL',
  'neutral': 'NEUTRAL',
  'slang': 'SLANG',
  'general': 'NEUTRAL',
  'easy': 'EASY',
  'intermediate': 'NORMAL',
  'advanced': 'ADVANCED',
  'upper-intermediate': 'ADVANCED',
  'lemma': 'LEMMA',
  'past': 'PAST',
  'past_participle': 'PAST_PARTICIPLE',
  'present_participle': 'PRESENT_PARTICIPLE',
  'third_person': 'THIRD_PERSON',
  'plural': 'PLURAL',
  'comparative': 'COMPARATIVE',
  'superlative': 'SUPERLATIVE',
  'other': 'OTHER',
  'prefix': 'PREFIX',
  'suffix': 'SUFFIX',
  'collocation': 'COLLOCATION',
  'phrase': 'PHRASE',
  'idiom': 'IDIOM',
};

/// 归一化模型输出（枚举纠偏 + 字符串条目补全为对象）。
Map<String, Object?> normalizeAiLexicalOutput(Map<String, Object?> raw) {
  final result = Map<String, Object?>.from(raw);
  final summary = _map(result['summary']);
  summary['cefrLevel'] = _fixEnum(summary['cefrLevel'], const <String>[
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ]);
  summary['frequency'] = _fixEnum(summary['frequency'], const <String>[
    'VERY_COMMON',
    'COMMON',
    'NORMAL',
    'RARE',
  ]);
  result['summary'] = summary;
  result['senses'] = <Object?>[
    for (final sense in _list(result['senses'])) _normalizeSense(_map(sense)),
  ];
  result['morphology'] = _normalizeMorphology(_map(result['morphology']));
  result['phrases'] = <Object?>[
    for (final item in _list(result['phrases'])) _fixCollocation(item),
  ];
  result['confusedWords'] = <Object?>[
    for (final item in _list(result['confusedWords'])) _fixRelatedItem(item),
  ];
  result['sentenceAnalysis'] = _normalizeSentenceAnalysis(
    _map(result['sentenceAnalysis']),
  );
  return result;
}

Map<String, Object?> _normalizeSense(Map<String, Object?> sense) {
  final result = Map<String, Object?>.from(sense);
  result['register'] = _fixEnum(result['register'], const <String>[
    'FORMAL',
    'INFORMAL',
    'NEUTRAL',
    'SLANG',
  ]);
  result['examples'] = <Object?>[
    for (final item in _list(result['examples'])) _normalizeExample(_map(item)),
  ];
  result['synonyms'] = <Object?>[
    for (final item in _list(result['synonyms'])) _fixRelatedItem(item),
  ];
  result['antonyms'] = <Object?>[
    for (final item in _list(result['antonyms'])) _fixRelatedItem(item),
  ];
  result['collocations'] = <Object?>[
    for (final item in _list(result['collocations'])) _fixCollocation(item),
  ];
  return result;
}

Map<String, Object?> _normalizeExample(Map<String, Object?> example) {
  final result = Map<String, Object?>.from(example);
  result['difficulty'] = _fixEnum(result['difficulty'], const <String>[
    'EASY',
    'NORMAL',
    'ADVANCED',
  ]);
  return result;
}

Map<String, Object?> _normalizeMorphology(Map<String, Object?> morphology) {
  final result = Map<String, Object?>.from(morphology);
  result['forms'] = <Object?>[
    for (final item in _list(morphology['forms'])) _normalizeForm(_map(item)),
  ];
  result['wordFamily'] = <Object?>[
    for (final item in _list(morphology['wordFamily'])) _fixRelatedItem(item),
  ];
  result['affixes'] = <Object?>[
    for (final item in _list(morphology['affixes']))
      _normalizeAffix(_map(item)),
  ];
  return result;
}

Map<String, Object?> _normalizeForm(Map<String, Object?> form) {
  final result = Map<String, Object?>.from(form);
  result['type'] = _fixEnum(result['type'], const <String>[
    'LEMMA',
    'PAST',
    'PAST_PARTICIPLE',
    'PRESENT_PARTICIPLE',
    'THIRD_PERSON',
    'PLURAL',
    'COMPARATIVE',
    'SUPERLATIVE',
    'OTHER',
  ]);
  return result;
}

Map<String, Object?> _normalizeAffix(Map<String, Object?> affix) {
  final result = Map<String, Object?>.from(affix);
  final meaning = _text(result['meaning']);
  if (meaning.isEmpty) result['meaning'] = _text(result['value']);
  result['type'] = _fixEnum(result['type'], const <String>['PREFIX', 'SUFFIX']);
  return result;
}

Map<String, Object?> _normalizeSentenceAnalysis(Map<String, Object?> raw) {
  final result = Map<String, Object?>.from(raw);
  result['grammarNotes'] = _list(raw['grammarNotes']);
  result['keyExpressions'] = <Object?>[
    for (final item in _list(raw['keyExpressions'])) _fixKeyExpression(item),
  ];
  result['similarExamples'] = <Object?>[
    for (final item in _list(raw['similarExamples']))
      if (item is String)
        <String, Object?>{'sentence': item, 'translation': '', 'focus': null}
      else
        item,
  ];
  result['variations'] = <Object?>[
    for (final item in _list(raw['variations']))
      if (item is String)
        <String, Object?>{'sentence': item, 'translation': null}
      else
        item,
  ];
  return result;
}

Object? _fixEnum(Object? value, List<String> allowed) {
  if (value == null) return null;
  if (value is! String) return value;
  if (allowed.contains(value)) return value;
  final key = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  final mapped = aiEnumAliases[key];
  if (mapped != null && allowed.contains(mapped)) return mapped;
  return value;
}

Object? _fixRelatedItem(Object? item) {
  if (item is String) {
    return <String, Object?>{
      'word': item,
      'translation': null,
      'partOfSpeech': null,
      'difference': null,
    };
  }
  if (item is! Map) return item;
  final record = item.cast<String, Object?>();
  return <String, Object?>{
    'word': record['word'],
    'translation': record['translation'],
    'partOfSpeech': record['partOfSpeech'],
    'difference': record['difference'],
    'relation': record['relation'] ?? 'RELATED',
  };
}

Object? _fixCollocation(Object? item) {
  if (item is String) {
    return <String, Object?>{
      'phrase': item,
      'translation': null,
      'example': null,
    };
  }
  return item;
}

Object? _fixKeyExpression(Object? item) {
  if (item is! String) return item;
  final parts = item.split(RegExp('[:：]'));
  final expression = parts.isEmpty ? item : parts.first.trim();
  final meaning = parts.length > 1 ? parts.sublist(1).join(':').trim() : item;
  return <String, Object?>{
    'expression': expression.isEmpty ? item : expression,
    'meaning': meaning.isEmpty ? item : meaning,
    'note': null,
  };
}

/// 把归一化后的输出转成词条字段。
Map<String, Object?> aiLexicalToFields(
  Map<String, Object?> output,
  ProviderRequest request,
  String source,
) {
  final self = _normalizeText(request.term);
  final definitions = <Map<String, Object?>>[];
  final examples = <Map<String, Object?>>[];
  final synonyms = <Map<String, Object?>>[];
  final antonyms = <Map<String, Object?>>[];
  final phrases = <Map<String, Object?>>[];
  for (final sense in _list(output['senses'])) {
    final record = _map(sense);
    _appendSense(
      record,
      source: source,
      request: request,
      definitions: definitions,
      examples: examples,
      synonyms: synonyms,
      antonyms: antonyms,
      phrases: phrases,
      self: self,
    );
  }
  final morphology = _map(output['morphology']);
  final forms = <Map<String, Object?>>[];
  final lemma = _text(morphology['lemma']);
  if (lemma.isNotEmpty) {
    forms.add(<String, Object?>{
      'type': 'LEMMA',
      'value': lemma,
      'source': source,
    });
  }
  for (final form in _list(morphology['forms'])) {
    final record = _map(form);
    final value = _text(record['value']);
    if (value.isEmpty) continue;
    forms.add(<String, Object?>{
      'type': _text(record['type']),
      'value': value,
      'source': source,
    });
  }
  for (final item in _list(output['phrases'])) {
    final record = _map(item);
    final phrase = _text(record['phrase']);
    if (phrase.isEmpty) continue;
    phrases.add(<String, Object?>{
      'phrase': phrase,
      'translation': _nullable(record['translation']),
      'source': source,
    });
  }
  return <String, Object?>{
    'definitions': definitions,
    'examples': examples,
    'phrases': phrases,
    'forms': forms,
    'synonyms': synonyms,
    'antonyms': antonyms,
    'wordFamily': _related(
      _list(morphology['wordFamily']),
      relation: 'WORD_FAMILY',
      source: source,
      exclude: self,
    ),
    'confusedWords': _related(
      _list(output['confusedWords']),
      relation: 'CONFUSED_WITH',
      source: source,
      exclude: self,
    ),
    'roots': _roots(_list(morphology['roots']), source),
    'affixes': _affixes(_list(morphology['affixes']), source),
    'summary': _map(output['summary']),
    'learning': _learning(_map(output['learning'])),
    'sentenceAnalysis': _map(output['sentenceAnalysis']),
    'tags': _strings(output['tags']),
  };
}

void _appendSense(
  Map<String, Object?> sense, {
  required String source,
  required ProviderRequest request,
  required List<Map<String, Object?>> definitions,
  required List<Map<String, Object?>> examples,
  required List<Map<String, Object?>> synonyms,
  required List<Map<String, Object?>> antonyms,
  required List<Map<String, Object?>> phrases,
  required String self,
}) {
  final partOfSpeech = _nullable(sense['partOfSpeech']);
  final definition = _text(sense['definition']);
  final translation = _text(sense['translation']);
  if (definition.isNotEmpty) {
    definitions.add(
      _definition(request.sourceLanguage, partOfSpeech, definition, source),
    );
  }
  if (translation.isNotEmpty) {
    definitions.add(
      _definition(request.targetLanguage, partOfSpeech, translation, source),
    );
  }
  for (final item in _list(sense['examples'])) {
    final record = _map(item);
    final sentence = _text(record['sentence']);
    if (sentence.isEmpty) continue;
    examples.add(<String, Object?>{
      'sentence': sentence,
      'translation': _nullable(record['translation']),
      'source': source,
      'isUserAdded': false,
    });
  }
  synonyms.addAll(
    _related(
      _list(sense['synonyms']),
      relation: 'SYNONYM',
      source: source,
      exclude: self,
    ),
  );
  antonyms.addAll(
    _related(
      _list(sense['antonyms']),
      relation: 'ANTONYM',
      source: source,
      exclude: self,
    ),
  );
  for (final item in _list(sense['collocations'])) {
    final record = _map(item);
    final phrase = _text(record['phrase']);
    if (phrase.isEmpty) continue;
    phrases.add(<String, Object?>{
      'phrase': phrase,
      'translation': _nullable(record['translation']),
      'source': source,
    });
  }
}

Map<String, Object?> _definition(
  String language,
  String? partOfSpeech,
  String text,
  String source,
) => <String, Object?>{
  'language': language,
  'partOfSpeech': partOfSpeech,
  'text': text,
  'source': source,
  'isUserEdited': false,
};

List<Map<String, Object?>> _related(
  List<Object?> raw, {
  required String relation,
  required String source,
  required String exclude,
}) {
  final result = <Map<String, Object?>>[];
  for (final item in raw) {
    final record = _map(item);
    final word = _text(record['word']);
    if (word.isEmpty || _normalizeText(word) == exclude) continue;
    result.add(<String, Object?>{
      'word': word,
      'translation': _nullable(record['translation']),
      'partOfSpeech': _nullable(record['partOfSpeech']),
      'relation': _text(record['relation']).isEmpty
          ? relation
          : _text(record['relation']),
      'source': source,
      'difference': _nullable(record['difference']),
    });
  }
  return result;
}

List<Map<String, Object?>> _roots(List<Object?> raw, String source) {
  final result = <Map<String, Object?>>[];
  for (final item in raw) {
    final record = _map(item);
    final root = _text(record['root']);
    final meaning = _text(record['meaning']);
    if (root.isEmpty || meaning.isEmpty) continue;
    result.add(<String, Object?>{
      'root': root,
      'meaning': meaning,
      'origin': _nullable(record['origin']),
      'source': source,
    });
  }
  return result;
}

List<Map<String, Object?>> _affixes(List<Object?> raw, String source) {
  final result = <Map<String, Object?>>[];
  for (final item in raw) {
    final record = _map(item);
    final value = _text(record['value']);
    final meaning = _text(record['meaning']);
    final type = record['type'] == 'PREFIX'
        ? 'PREFIX'
        : record['type'] == 'SUFFIX'
        ? 'SUFFIX'
        : '';
    if (value.isEmpty || meaning.isEmpty || type.isEmpty) continue;
    result.add(<String, Object?>{
      'value': value,
      'meaning': meaning,
      'type': type,
      'source': source,
    });
  }
  return result;
}

Map<String, Object?> _learning(Map<String, Object?> raw) {
  final mnemonic = _text(raw['mnemonic']);
  return <String, Object?>{
    'pronunciationTip': _nullable(raw['pronunciationTip']),
    // 助记词必须是中文：模型偶尔会把英文解释塞进这个字段，
    // 与其整份丢弃，不如只丢掉这一个字段。
    'mnemonic': isChineseMnemonic(mnemonic) ? mnemonic : null,
    'commonMistakes': _strings(raw['commonMistakes']),
  };
}

/// 助记词是否是合格的中文叙述（至少 [aiMnemonicMinChineseChars] 个汉字）。
bool isChineseMnemonic(String value) =>
    RegExp(r'[\u3400-\u9fff]').allMatches(value).length >=
    aiMnemonicMinChineseChars;

/// 语义校验：返回问题列表（空表示通过）。
List<String> aiLexicalSemanticIssues(
  Map<String, Object?> output,
  ProviderRequest request,
) {
  final accepted = _acceptedTerms(output, request);
  final issues = <String>[];
  if (request.contentType == LexicalContentType.sentence) {
    _appendSentenceIssues(output, issues);
    return issues;
  }
  final senses = _list(output['senses']);
  for (final item in senses) {
    final sense = _map(item);
    final id = _text(sense['id']);
    final examples = _list(sense['examples']);
    var covered = false;
    for (final example in examples) {
      final sentence = _normalizeText(_text(_map(example)['sentence']));
      if (accepted.any(sentence.contains)) {
        covered = true;
        break;
      }
    }
    if (!covered) issues.add('词义 $id 的例句未包含目标词或其词形');
  }
  return issues;
}

void _appendSentenceIssues(Map<String, Object?> output, List<String> issues) {
  final analysis = _map(output['sentenceAnalysis']);
  if (_text(analysis['grammarPattern']).isEmpty ||
      _text(analysis['grammarExplanation']).isEmpty) {
    issues.add('句子内容缺少结构化语法骨架或中文语法解释');
  }
  if (_list(analysis['grammarNotes']).isEmpty) {
    issues.add('句子内容缺少语法要点');
  }
  if (_list(analysis['similarExamples']).length <
      sentenceAnalysisMinSimilarExamples) {
    issues.add('句子内容至少需要 3 个同语法双语例句');
  }
}

Set<String> _acceptedTerms(
  Map<String, Object?> output,
  ProviderRequest request,
) {
  final result = <String>{_normalizeText(request.term)};
  final morphology = _map(output['morphology']);
  final lemma = _normalizeText(_text(morphology['lemma']));
  if (lemma.isNotEmpty) result.add(lemma);
  for (final form in _list(morphology['forms'])) {
    final value = _normalizeText(_text(_map(form)['value']));
    if (value.isNotEmpty) result.add(value);
  }
  result.remove('');
  return result;
}

/// 质量分（0–100）。低于 `aiQualityScoreThreshold` 时整份丢弃。
int aiLexicalQualityScore(
  Map<String, Object?> output,
  ProviderRequest request,
) {
  final senses = <Map<String, Object?>>[
    for (final item in _list(output['senses'])) _map(item),
  ];
  final examples = <Map<String, Object?>>[
    for (final sense in senses)
      for (final item in _list(sense['examples'])) _map(item),
  ];
  final definitions = senses
      .where(
        (sense) =>
            _text(sense['definition']).isNotEmpty &&
            _text(sense['translation']).isNotEmpty,
      )
      .length;
  final relatedCount = senses.fold<int>(
    0,
    (sum, sense) =>
        sum +
        _list(sense['synonyms']).length +
        _list(sense['antonyms']).length +
        _list(sense['collocations']).length,
  );
  final morphology = _map(output['morphology']);
  final morphologyCount =
      _list(morphology['forms']).length +
      _list(morphology['wordFamily']).length +
      _list(morphology['roots']).length +
      _list(morphology['affixes']).length;
  var score = _capped(definitions * 15, 30);
  if (_text(_map(output['summary'])['translation']).isNotEmpty) score += 15;
  score += _capped(examples.length * 7, 20);
  score += _capped(relatedCount * 2, 10);
  score += request.contentType == LexicalContentType.word
      ? _capped(morphologyCount * 2, 10)
      : 10;
  score += request.contentType == LexicalContentType.sentence
      ? _sentenceBonus(output)
      : _exampleCoverageBonus(output, request, examples);
  score += _learningBonus(output);
  return score > 100 ? 100 : score;
}

int _capped(int value, int max) => value > max ? max : value;

int _sentenceBonus(Map<String, Object?> output) {
  final analysis = _map(output['sentenceAnalysis']);
  var bonus = 0;
  if (_text(analysis['grammarPattern']).isNotEmpty) bonus += 2;
  if (_text(analysis['grammarExplanation']).isNotEmpty) bonus += 2;
  bonus += _list(analysis['grammarNotes']).length;
  bonus += _list(analysis['keyExpressions']).length;
  bonus += _list(analysis['similarExamples']).length;
  return _capped(bonus, 10);
}

int _exampleCoverageBonus(
  Map<String, Object?> output,
  ProviderRequest request,
  List<Map<String, Object?>> examples,
) {
  if (examples.isEmpty) return 0;
  final term = _normalizeText(request.term);
  final forms = <String>[
    for (final form in _list(_map(output['morphology'])['forms']))
      _normalizeText(_text(_map(form)['value'])),
  ];
  var covered = 0;
  for (final example in examples) {
    final sentence = _normalizeText(_text(example['sentence']));
    if (sentence.contains(term) || forms.any(sentence.contains)) covered += 1;
  }
  return (covered / examples.length * 10).round();
}

int _learningBonus(Map<String, Object?> output) {
  final learning = _map(output['learning']);
  final hasMnemonic = _text(learning['mnemonic']).isNotEmpty;
  final hasMistakes = _list(learning['commonMistakes']).isNotEmpty;
  return hasMnemonic || hasMistakes ? 5 : 0;
}

String _normalizeText(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final item in value) {
    final text = _text(item);
    if (text.isNotEmpty) result.add(text);
  }
  return result;
}

String _text(Object? value) => value is String ? value.trim() : '';

String? _nullable(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}
