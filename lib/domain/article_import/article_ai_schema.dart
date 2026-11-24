/// AI 选词的 JSON Schema 与容错解析。
///
/// 对应旧版 `src/modules/article-import/schema.ts`（311 行）。
///
/// **与旧版的差异（有意）**：旧版先跑一遍「宽容解析」再交给 zod 校验，
/// 校验失败才退回宽容结果。但宽容解析本身就按同一组上限做了截断、按同一组
/// 枚举做了过滤、缺字段补了默认值，因此第二步在宽容结果上**恒真**——
/// 保留它只会让「到底哪一步决定了最终结果」变得难以回答。本版只保留宽容
/// 解析这一步，并把上限全部具名到 `lib/core/constants.dart`，与原 zod 逐条对应。
///
/// 本文件必须保持纯 Dart。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/article_import/article_ai_models.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';

/// CEFR 等级取值。
const List<String> articleCefrLevels = <String>[
  'A1',
  'A2',
  'B1',
  'B2',
  'C1',
  'C2',
];

/// 词频档取值。
const List<String> articleFrequencies = <String>[
  'VERY_COMMON',
  'COMMON',
  'NORMAL',
  'RARE',
];

/// `["string","null"]` 类型声明。
const List<String> _nullableString = <String>['string', 'null'];

/// AI 选词的完整结构化输出 Schema（单词 + 短语 + 难句）。
///
/// 兼容 OpenAI 的 strict 模式：`properties` 里的每个键都必须出现在
/// `required` 中，可选字段用 `null` 联合类型表示。
Map<String, Object?> get articleAiSelectionJsonSchema => <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['words', 'phrases', 'sentences'],
  'properties': <String, Object?>{
    'words': _wordsSchema(),
    'phrases': _phrasesSchema(),
    'sentences': _sentencesSchema(),
  },
};

/// 仅分词模式的轻量结构化输出 Schema（只返回单词，查词交由有道完成）。
///
/// 同样满足 OpenAI strict 模式要求：体积更小、输出更快、不易截断。
Map<String, Object?> get articleAiWordOnlyJsonSchema => <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['words'],
  'properties': <String, Object?>{'words': _wordsSchema()},
};

/// 容错解析 AI 返回的 JSON。
///
/// 返回 `null` 表示「结构完全不可用」，调用方应回退本地筛选并给出原因。
/// 只要有一项内容可解析就返回结果，绝不因为个别字段超长或缺失而整批丢弃。
ArticleAiSelection? normalizeAiSelectionResponse(Object? parsed) {
  if (parsed is! Map) return null;
  final words = _lenientList(
    _pickKey(parsed, const <String>['words', 'selected']),
    _lenientWord,
    articleAiWordsMaxItems,
  );
  final phrases = _lenientList(
    _pickKey(parsed, const <String>['phrases']),
    _lenientPhrase,
    articleAiPhrasesMaxItems,
  );
  final sentences = _lenientList(
    _pickKey(parsed, const <String>['sentences']),
    _lenientSentence,
    articleAiSentencesMaxItems,
  );
  if (words.isEmpty && phrases.isEmpty && sentences.isEmpty) return null;
  return ArticleAiSelection.success(
    words: words,
    phrases: phrases,
    sentences: sentences,
  );
}

Map<String, Object?> _wordsSchema() => <String, Object?>{
  'type': 'array',
  'maxItems': articleAiWordsMaxItems,
  'items': <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'term',
      'surface',
      'reason',
      'difficulty',
      'cefrLevel',
      'frequency',
      'examTags',
    ],
    'properties': <String, Object?>{
      'term': <String, Object?>{'type': 'string'},
      'surface': <String, Object?>{'type': _nullableString},
      'reason': <String, Object?>{'type': 'string'},
      'difficulty': _difficultySchema(),
      'cefrLevel': <String, Object?>{
        'type': _nullableString,
        'enum': <Object?>[...articleCefrLevels, null],
      },
      'frequency': <String, Object?>{
        'type': _nullableString,
        'enum': <Object?>[...articleFrequencies, null],
      },
      'examTags': <String, Object?>{
        'type': 'array',
        'maxItems': articleAiExamTagsMaxItems,
        'items': <String, Object?>{'type': 'string'},
      },
    },
  },
};

Map<String, Object?> _phrasesSchema() => <String, Object?>{
  'type': 'array',
  'maxItems': articlePhraseLimit,
  'items': <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'term',
      'reason',
      'difficulty',
      'cefrLevel',
      'literalTranslation',
      'freeTranslation',
      'keyVocab',
      'grammar',
      'nuance',
    ],
    'properties': <String, Object?>{
      'term': <String, Object?>{'type': 'string'},
      'reason': <String, Object?>{'type': 'string'},
      'difficulty': _difficultySchema(),
      'cefrLevel': <String, Object?>{'type': _nullableString},
      'literalTranslation': <String, Object?>{'type': 'string'},
      'freeTranslation': <String, Object?>{'type': 'string'},
      'keyVocab': _keyVocabSchema(articleAiPhraseKeyVocabMaxItems),
      'grammar': _grammarSchema(),
      'nuance': <String, Object?>{'type': _nullableString},
    },
  },
};

Map<String, Object?> _sentencesSchema() => <String, Object?>{
  'type': 'array',
  'maxItems': articleSentenceLimit,
  'items': <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'sentence',
      'literalTranslation',
      'freeTranslation',
      'keyVocab',
      'grammar',
      'nuance',
    ],
    'properties': <String, Object?>{
      'sentence': <String, Object?>{'type': 'string'},
      'literalTranslation': <String, Object?>{'type': 'string'},
      'freeTranslation': <String, Object?>{'type': 'string'},
      'keyVocab': _keyVocabSchema(articleAiSentenceKeyVocabMaxItems),
      'grammar': _grammarSchema(),
      'nuance': <String, Object?>{'type': _nullableString},
    },
  },
};

Map<String, Object?> _difficultySchema() => <String, Object?>{
  'type': 'integer',
  'minimum': 1,
  'maximum': articleAiDifficultyMax,
};

Map<String, Object?> _keyVocabSchema(int maxItems) => <String, Object?>{
  'type': 'array',
  'maxItems': maxItems,
  'items': <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>['term', 'pos', 'meaning'],
    'properties': <String, Object?>{
      'term': <String, Object?>{'type': 'string'},
      'pos': <String, Object?>{'type': _nullableString},
      'meaning': <String, Object?>{'type': 'string'},
    },
  },
};

Map<String, Object?> _grammarSchema() => <String, Object?>{
  'type': <String>['object', 'null'],
  'additionalProperties': false,
  'required': <String>['pattern', 'notes'],
  'properties': <String, Object?>{
    'pattern': <String, Object?>{'type': _nullableString},
    'notes': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string'},
    },
  },
};

/// 按候选键取值；键名大小写不敏感（旧版 `pickKey`）。
Object? _pickKey(Object? raw, List<String> names) {
  if (raw is! Map) return null;
  for (final name in names) {
    if (raw.containsKey(name)) return raw[name];
  }
  final lowered = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is String) lowered[key.toLowerCase()] = entry.value;
  }
  for (final name in names) {
    final value = lowered[name.toLowerCase()];
    if (value != null) return value;
  }
  return null;
}

List<T> _lenientList<T>(Object? value, T? Function(Object?) map, int max) {
  if (value is! List) return <T>[];
  final out = <T>[];
  for (final item in value) {
    final mapped = map(item);
    if (mapped != null) out.add(mapped);
    if (out.length >= max) break;
  }
  return out;
}

/// 文本字段：去空白、空串视为缺失、超长截断。
String? _lenientText(Object? value, int max) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > max ? trimmed.substring(0, max) : trimmed;
}

/// 难度：数字或数字字符串，夹到 1–[articleAiDifficultyMax]。
///
/// **与旧版的差异（有意）**：旧版用 JS 的 `Number(value)` 强转，`null` /
/// `[]` / `true` 会被隐式转成 0 或 1，再夹成「最简单」。那是隐式转换的
/// 副作用而不是产品意图，本版对非数字输入一律退回
/// [articleAiDifficultyFallback]。
int _lenientDifficulty(Object? value) {
  final parsed = switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text.trim()),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite) return articleAiDifficultyFallback;
  return parsed.round().clamp(1, articleAiDifficultyMax);
}

String? _lenientEnum(Object? value, List<String> allowed) {
  if (value is! String) return null;
  final upper = value.trim().toUpperCase();
  return allowed.contains(upper) ? upper : null;
}

List<ArticleAiKeyVocab> _lenientKeyVocab(Object? value, int max) {
  if (value is! List) return const <ArticleAiKeyVocab>[];
  final out = <ArticleAiKeyVocab>[];
  for (final item in value) {
    if (item is! Map) continue;
    final term = _lenientText(item['term'], articleAiKeyVocabTermMaxChars);
    final meaning = _lenientText(
      item['meaning'],
      articleAiKeyVocabMeaningMaxChars,
    );
    if (term == null || meaning == null) continue;
    out.add(
      ArticleAiKeyVocab(
        term: term,
        pos: _lenientText(item['pos'], articleAiKeyVocabPosMaxChars),
        meaning: meaning,
      ),
    );
    if (out.length >= max) break;
  }
  return out;
}

_ArticleGrammar _lenientGrammar(Object? value) {
  if (value is! Map) return const _ArticleGrammar(null, <String>[]);
  final notes = <String>[];
  final rawNotes = value['notes'];
  if (rawNotes is List) {
    for (final note in rawNotes) {
      final text = _lenientText(note, articleAiGrammarNoteMaxChars);
      if (text != null) notes.add(text);
      if (notes.length >= articleAiGrammarNotesMaxItems) break;
    }
  }
  return _ArticleGrammar(
    _lenientText(value['pattern'], articleAiGrammarPatternMaxChars),
    notes,
  );
}

ArticleAiWord? _lenientWord(Object? item) {
  if (item is! Map) return null;
  final term = _lenientText(
    item['term'] ?? item['lemma'],
    articleAiTermMaxChars,
  );
  if (term == null) return null;
  final rawSurface = _lenientText(
    item['surface'] ?? item['surfaceForm'],
    articleAiSurfaceMaxChars,
  );
  final surface =
      rawSurface != null && rawSurface.toLowerCase() != term.toLowerCase()
      ? rawSurface
      : null;
  return ArticleAiWord(
    term: term,
    surfaceForm: surface,
    reason:
        _lenientText(
          item['reason'] ?? item['contextHint'],
          articleAiReasonMaxChars,
        ) ??
        articleDefaultReason,
    difficulty: _lenientDifficulty(item['difficulty']),
    cefrLevel: _lenientEnum(item['cefrLevel'], articleCefrLevels),
    frequency: _lenientEnum(item['frequency'], articleFrequencies),
    examTags: _lenientExamTags(item['examTags']),
  );
}

List<String> _lenientExamTags(Object? value) {
  if (value is! List) return const <String>[];
  final out = <String>[];
  for (final entry in value) {
    final text = _lenientText(entry, articleAiExamTagMaxChars);
    if (text == null) continue;
    final upper = text.toUpperCase();
    if (!out.contains(upper)) out.add(upper);
    if (out.length >= articleAiExamTagsMaxItems) break;
  }
  return List<String>.unmodifiable(out);
}

ArticleAiPhrase? _lenientPhrase(Object? item) {
  if (item is! Map) return null;
  final term = _lenientText(item['term'], articleAiTermMaxChars);
  final literal = _lenientText(
    item['literalTranslation'],
    articleAiPhraseTranslationMaxChars,
  );
  final free = _lenientText(
    item['freeTranslation'],
    articleAiPhraseTranslationMaxChars,
  );
  if (term == null || literal == null || free == null) return null;
  final grammar = _lenientGrammar(item['grammar']);
  return ArticleAiPhrase(
    term: term,
    reason:
        _lenientText(item['reason'], articleAiReasonMaxChars) ??
        articleDefaultReason,
    difficulty: _lenientDifficulty(item['difficulty']),
    cefrLevel: _lenientEnum(item['cefrLevel'], articleCefrLevels),
    literalTranslation: literal,
    freeTranslation: free,
    keyVocab: _lenientKeyVocab(
      item['keyVocab'],
      articleAiPhraseKeyVocabMaxItems,
    ),
    grammarPattern: grammar.pattern,
    grammarNotes: grammar.notes,
    nuance: _lenientText(item['nuance'], articleAiPhraseNuanceMaxChars),
  );
}

ArticleAiSentence? _lenientSentence(Object? item) {
  if (item is! Map) return null;
  final sentence = _lenientText(
    item['sentence'],
    articleAiSentenceTextMaxChars,
  );
  final literal = _lenientText(
    item['literalTranslation'],
    articleAiSentenceTranslationMaxChars,
  );
  final free = _lenientText(
    item['freeTranslation'],
    articleAiSentenceTranslationMaxChars,
  );
  if (sentence == null || literal == null || free == null) return null;
  final grammar = _lenientGrammar(item['grammar']);
  return ArticleAiSentence(
    sentence: sentence,
    literalTranslation: literal,
    freeTranslation: free,
    keyVocab: _lenientKeyVocab(
      item['keyVocab'],
      articleAiSentenceKeyVocabMaxItems,
    ),
    grammarPattern: grammar.pattern,
    grammarNotes: grammar.notes,
    nuance: _lenientText(item['nuance'], articleAiSentenceNuanceMaxChars),
  );
}

/// 语法字段的解析结果。
///
/// 用私有类而不是记录：记录的取值器是 `$1` / `$2`，在阅读时完全看不出
/// 「哪一个才是句型」。
class _ArticleGrammar {
  const new(this.pattern, this.notes);

  final String? pattern;
  final List<String> notes;
}
