/// 补充任务（助记词、例句翻译）的执行。
///
/// 对应旧版 `modules/ai-tasks/supplemental.ts` 与
/// `modules/initialization/queue.ts` 的 `queueAiTask`。
///
/// **为什么独立成执行器接口**：worker 只负责「状态机 + 重试」，
/// 具体让模型生成什么内容是可替换的策略。测试里注入一个记录调用的假实现，
/// 就能在不发任何网络请求的前提下验证 worker 的退避与终态。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/providers/ai_lexical_content.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/llm/llm_client.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 补充任务执行器。
abstract interface class SupplementalTaskRunner {
  /// 执行一个补充任务；失败抛 `ExternalServiceError`。
  Future<void> run({
    required JobTaskType taskType,
    required int wordId,
    required int now,
  });
}

/// 助记词任务的输出结构。
const Map<String, Object?> mnemonicSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['term', 'mnemonic'],
  'properties': <String, Object?>{
    'term': <String, Object?>{'type': 'string'},
    'mnemonic': <String, Object?>{
      'type': <String>['string', 'null'],
    },
  },
};

/// 例句翻译任务的输出结构。
const Map<String, Object?> exampleTranslationSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['term', 'translations'],
  'properties': <String, Object?>{
    'term': <String, Object?>{'type': 'string'},
    'translations': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['sentence', 'translation'],
        'properties': <String, Object?>{
          'sentence': <String, Object?>{'type': 'string'},
          'translation': <String, Object?>{'type': 'string'},
        },
      },
    },
  },
};

/// 释义翻译任务的输出结构。
///
/// **按原文文本配对而不是按下标**：旧版 `translateMissingDefinitions`
/// 用 `result.translations.get(index)` 按下标取译文，一旦翻译服务重排或
/// 少返回一条，译文就会贴到别的释义上。让模型把原文一并回显、按文本配对，
/// 配对不上的条目宁可丢弃也不会张冠李戴。
const Map<String, Object?> definitionTranslationSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['term', 'translations'],
  'properties': <String, Object?>{
    'term': <String, Object?>{'type': 'string'},
    'translations': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['text', 'translation'],
        'properties': <String, Object?>{
          'text': <String, Object?>{'type': 'string'},
          'translation': <String, Object?>{'type': 'string'},
        },
      },
    },
  },
};

/// 摘要翻译任务的输出结构。
const Map<String, Object?> summaryTranslationSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['term', 'translation'],
  'properties': <String, Object?>{
    'term': <String, Object?>{'type': 'string'},
    'translation': <String, Object?>{'type': 'string'},
  },
};

/// AI 翻译写入 `definitions.source` 的前缀。
///
/// 旧版是 `ai:translation:<翻译服务标识>`；本版翻译由 LLM 完成，
/// 因此接上模型名，出问题时能一眼看出是哪个模型翻的。
const String aiTranslationSourcePrefix = 'ai:translation:';

/// 基于 LLM 的补充任务执行器。
class LlmSupplementalTaskRunner implements SupplementalTaskRunner {
  /// 以数据库、设置服务与 HTTP 客户端构造。
  const new(this._db, this._settings, this._fetcher);

  final AppDatabase _db;
  final SettingsService _settings;
  final HttpFetcher _fetcher;

  @override
  Future<void> run({
    required JobTaskType taskType,
    required int wordId,
    required int now,
  }) async {
    if (taskType == JobTaskType.initialize) return;
    final word = await _loadWord(wordId);
    final config = await _config();
    final client = LlmClient(_fetcher, config);
    switch (taskType) {
      case JobTaskType.mnemonic:
        await _writeMnemonic(client, word, wordId, now);
      case JobTaskType.exampleTranslations:
        await _translateWordContent(client, word, wordId, now, config);
      case JobTaskType.initialize:
        return;
    }
  }

  Future<LlmConfig> _config() async {
    final settings = await _settings.load();
    final config = llmConfigFromSettings(settings.raw);
    if (!config.isUsable) {
      throw const ExternalServiceError(
        AppErrorCode.aiDisabled,
        details: 'AI 未启用或配置不完整，无法执行补充任务',
      );
    }
    return config;
  }

  /// 依次补齐缺失的释义译文、摘要译文与例句译文。
  ///
  /// 顺序与旧版 `translateMissingWordContent` 一致：
  /// definitions → summary → examples。这个顺序有意义——释义是词条的
  /// 核心内容，先把它补上，后面两步失败时词条至少已经可判题。
  Future<void> _translateWordContent(
    LlmClient client,
    _SupplementalWord word,
    int wordId,
    int now,
    LlmConfig config,
  ) async {
    final source = '$aiTranslationSourcePrefix${config.ai.model}';
    await _translateDefinitions(client, word, wordId, now, source);
    await _translateSummary(client, word, wordId, now);
    await _translateExamples(client, word, wordId, now);
  }

  Future<_SupplementalWord> _loadWord(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT w.term, w.source_language, w.target_language, '
          'w.content_type, wc.learning_json, wc.examples_json, '
          'wc.definitions_json, wc.summary_json FROM words w '
          'LEFT JOIN word_contents wc ON wc.word_id = w.id WHERE w.id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) {
      throw const NotFoundError(AppErrorCode.wordNotFound);
    }
    final row = rows.first;
    return _SupplementalWord(
      term: row.read<String>('term'),
      sourceLanguage: row.read<String>('source_language'),
      targetLanguage: row.read<String>('target_language'),
      learningJson: row.read<String?>('learning_json'),
      examplesJson: row.read<String?>('examples_json'),
      definitionsJson: row.read<String?>('definitions_json'),
      summaryJson: row.read<String?>('summary_json'),
    );
  }

  Future<void> _writeMnemonic(
    LlmClient client,
    _SupplementalWord word,
    int wordId,
    int now,
  ) async {
    final learning = _decodeObject(word.learningJson);
    final existing = learning['mnemonic'];
    if (existing is String && existing.trim().isNotEmpty) return;
    final output = await client.completeJson(
      system:
          'Return only one valid JSON object matching the requested schema.',
      user: _mnemonicPrompt(word),
      schema: mnemonicSchema,
    );
    _assertTerm(output['term'], word.term);
    final mnemonic = output['mnemonic'];
    final text = mnemonic is String ? mnemonic.trim() : '';
    if (!isChineseMnemonic(text)) {
      throw const ExternalServiceError(
        AppErrorCode.aiMnemonicLanguageInvalid,
        details: 'AI 生成的助记词不是中文',
      );
    }
    learning['mnemonic'] = text;
    await _updateColumn(wordId, 'learning_json', learning, now);
  }

  /// 补齐缺失的释义译文。
  ///
  /// 对应旧版 `modules/translations/service.ts` 的
  /// `translateMissingDefinitions`：源语言释义条数多于目标语言释义条数时，
  /// 取前 [translationBatchLimit] 条送翻译。
  ///
  /// **写库前重新读一次最新 JSON**：翻译要走一次网络往返，期间用户可能
  /// 刚手工加了一条释义。拿任务开始时读到的旧数组回写，会把那次编辑
  /// 整条抹掉。
  Future<void> _translateDefinitions(
    LlmClient client,
    _SupplementalWord word,
    int wordId,
    int now,
    String source,
  ) async {
    if (word.sourceLanguage == word.targetLanguage) return;
    final definitions = decodeJsonList(word.definitionsJson);
    final pending = _missingDefinitionTexts(definitions, word);
    if (pending.isEmpty) return;
    final output = await client.completeJson(
      system:
          'Return only one valid JSON object matching the requested schema.',
      user: _definitionTranslationPrompt(word, pending),
      schema: definitionTranslationSchema,
    );
    _assertTerm(output['term'], word.term);
    final translations = _translationMap(output['translations'], 'text');
    if (translations.isEmpty) {
      throw const ExternalServiceError(
        AppErrorCode.aiSemanticInvalid,
        details: '释义翻译结果为空',
      );
    }
    final latest = decodeJsonList(
      await _latestColumn(wordId, 'definitions_json'),
    );
    final added = _appendDefinitionTranslations(
      latest: latest,
      definitions: definitions,
      translations: translations,
      word: word,
      source: source,
    );
    if (added == 0) return;
    await _updateColumn(wordId, 'definitions_json', latest, now);
  }

  /// 补齐摘要的译文（`summary.shortDefinition` → `summary.translation`）。
  ///
  /// 对应旧版 `translateMissingSummary`。同样在写库前重读一次，
  /// 避免覆盖并发写入。
  Future<void> _translateSummary(
    LlmClient client,
    _SupplementalWord word,
    int wordId,
    int now,
  ) async {
    final summary = _decodeObject(word.summaryJson);
    final source = _text(summary['shortDefinition']);
    if (source.isEmpty || _text(summary['translation']).isNotEmpty) return;
    final output = await client.completeJson(
      system:
          'Return only one valid JSON object matching the requested schema.',
      user: _summaryTranslationPrompt(word, source),
      schema: summaryTranslationSchema,
    );
    _assertTerm(output['term'], word.term);
    final translation = _text(output['translation']);
    if (translation.isEmpty) {
      throw const ExternalServiceError(
        AppErrorCode.aiEmptyResponse,
        details: 'AI 没有返回释义译文',
      );
    }
    final latest = _decodeObject(await _latestColumn(wordId, 'summary_json'));
    if (_text(latest['translation']).isNotEmpty) return;
    latest['translation'] = translation;
    await _updateColumn(wordId, 'summary_json', latest, now);
  }

  Future<void> _translateExamples(
    LlmClient client,
    _SupplementalWord word,
    int wordId,
    int now,
  ) async {
    final examples = decodeJsonList(word.examplesJson);
    final pending = <Map<String, Object?>>[
      for (final item in examples)
        if (item is Map && _needsTranslation(item.cast<String, Object?>()))
          item.cast<String, Object?>(),
    ];
    if (pending.isEmpty) return;
    final output = await client.completeJson(
      system:
          'Return only one valid JSON object matching the requested schema.',
      user: _translationPrompt(word, pending),
      schema: exampleTranslationSchema,
    );
    _assertTerm(output['term'], word.term);
    final bySentence = _translationMap(output['translations'], 'sentence');
    if (bySentence.isEmpty) {
      throw const ExternalServiceError(
        AppErrorCode.aiSemanticInvalid,
        details: '例句翻译结果为空',
      );
    }
    final latest = decodeJsonList(await _latestColumn(wordId, 'examples_json'));
    var count = 0;
    for (final example in latest) {
      if (example is! Map) continue;
      final record = example.cast<String, Object?>();
      final sentence = record['sentence'];
      if (sentence is! String) continue;
      final translation = bySentence[sentence.trim()];
      // 重新读到的这一条可能已经有译文了（用户手工补的，或上一次任务
      // 写进去的），此时跳过而不是覆盖。
      if (translation == null ||
          translation.isEmpty ||
          !_needsTranslation(record)) {
        continue;
      }
      record['translation'] = translation;
      count += 1;
    }
    if (count == 0) return;
    await _updateColumn(wordId, 'examples_json', latest, now);
  }

  /// 读一列 JSON 文本的最新值；没有内容行时返回 `null`。
  Future<String?> _latestColumn(int wordId, String column) async {
    final rows = await _db
        .customSelect(
          'SELECT $column FROM word_contents WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String?>(column);
  }

  Future<void> _updateColumn(
    int wordId,
    String column,
    Object? value,
    int now,
  ) async {
    // 用 UPSERT 而不是 UPDATE：补充任务可能先于 INITIALIZE 落库，
    // 那时 word_contents 还没有这一行。`content_version` 必须自增，
    // 因此不能用 insertOrReplace。
    await _db.customUpdate(
      'INSERT INTO word_contents (word_id, $column, content_version, '
      'updated_at) VALUES (?, ?, 1, ?) '
      'ON CONFLICT(word_id) DO UPDATE SET $column = excluded.$column, '
      'content_version = word_contents.content_version + 1, '
      'updated_at = excluded.updated_at',
      variables: <Variable<Object>>[
        Variable<int>(wordId),
        Variable<String>(jsonEncode(value)),
        Variable<int>(now),
      ],
      updateKind: UpdateKind.update,
    );
  }
}

/// 补充任务需要的词条信息。
class _SupplementalWord {
  const new({
    required this.term,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.learningJson,
    required this.examplesJson,
    required this.definitionsJson,
    required this.summaryJson,
  });

  final String term;
  final String sourceLanguage;
  final String targetLanguage;
  final String? learningJson;
  final String? examplesJson;
  final String? definitionsJson;
  final String? summaryJson;
}

/// 待翻译的释义原文（最多 [translationBatchLimit] 条）。
///
/// 判定与旧版逐条一致：源语言释义条数减去目标语言释义条数就是缺口，
/// 缺口非正时无事可做。
List<String> _missingDefinitionTexts(
  List<Object?> definitions,
  _SupplementalWord word,
) {
  final source = <String>[];
  var targetCount = 0;
  for (final item in definitions) {
    if (item is! Map) continue;
    final text = _text(item['text']);
    if (text.isEmpty) continue;
    if (item['language'] == word.targetLanguage) {
      targetCount += 1;
    } else if (item['language'] == word.sourceLanguage) {
      source.add(text);
    }
  }
  if (source.length - targetCount <= 0) return const <String>[];
  return source.take(translationBatchLimit).toList(growable: false);
}

/// 把译文追加进最新释义数组，返回新增条数。
///
/// 目标语言里已有同文本的释义时跳过：重复的译文会让选择题出现两个
/// 一模一样的选项。
int _appendDefinitionTranslations({
  required List<Object?> latest,
  required List<Object?> definitions,
  required Map<String, String> translations,
  required _SupplementalWord word,
  required String source,
}) {
  final existing = <String>{
    for (final item in latest)
      if (item is Map && item['language'] == word.targetLanguage)
        _text(item['text']).toLowerCase(),
  }..remove('');
  var count = 0;
  for (final item in definitions) {
    if (item is! Map) continue;
    final translation = translations[_text(item['text'])];
    if (translation == null || !existing.add(translation.toLowerCase())) {
      continue;
    }
    latest.add(
      _definitionRecord(item, translation, word.targetLanguage, source),
    );
    count += 1;
  }
  return count;
}

/// 构造一条翻译释义，保留原文的义项编号、语体与用法说明。
///
/// 三个可选字段必须跟着译文走：它们描述的是**这个义项**，丢掉之后
/// 例句的 `senseId` 就再也对不上任何释义。
Map<String, Object?> _definitionRecord(
  Map<dynamic, dynamic> original,
  String translation,
  String targetLanguage,
  String source,
) => <String, Object?>{
  'language': targetLanguage,
  'partOfSpeech': original['partOfSpeech'],
  'text': translation,
  'source': source,
  'isUserEdited': false,
  if (original['senseId'] is String) 'senseId': original['senseId'],
  if (original['register'] is String) 'register': original['register'],
  if (original['usageNote'] is String) 'usageNote': original['usageNote'],
};

/// 把模型的 `translations` 数组转成「原文 → 译文」映射。
///
/// 结构不符时抛 [AppErrorCode.aiSchemaInvalid] 而不是静默返回空表：
/// 「模型没按 schema 返回」与「模型返回了空列表」是两种不同的故障，
/// 前者要换模型，后者要重试。
Map<String, String> _translationMap(Object? value, String key) {
  if (value is! List) {
    throw const ExternalServiceError(
      AppErrorCode.aiSchemaInvalid,
      details: 'translations 不是数组',
    );
  }
  final result = <String, String>{};
  for (final item in value) {
    if (item is! Map) continue;
    final original = _text(item[key]);
    final translation = _text(item['translation']);
    if (original.isEmpty || translation.isEmpty) continue;
    result[original] = translation;
  }
  return result;
}

/// 取字符串字段的规整值；非字符串或空白返回空串。
String _text(Object? value) => value is String ? value.trim() : '';

String _mnemonicPrompt(_SupplementalWord word) {
  final example = jsonEncode(<String, Object?>{
    'term': word.term,
    'mnemonic': '...',
  });
  return '''
为英文词条「${word.term}」写一条简体中文助记词（至少 $aiMnemonicMinChineseChars 个汉字），用联想、拆词或谐音帮助记忆，不要复述释义。
只输出一个 JSON 对象： $example
没有自然联想时把 mnemonic 设为 null。
''';
}

String _definitionTranslationPrompt(
  _SupplementalWord word,
  List<String> pending,
) =>
    '把下列英文释义翻译成${word.targetLanguage}，保持释义的专业性与简洁。'
    '只输出一个 JSON 对象，translations 的 text 必须与输入逐字一致：\n'
    '{"term": "${word.term}", "translations": '
    '[{"text": "...", "translation": "..."}]}\n'
    '释义：\n${jsonEncode(pending)}';

String _summaryTranslationPrompt(_SupplementalWord word, String source) =>
    '把下列英文释义翻译成${word.targetLanguage}，只要一个简短的中文对释。'
    '只输出一个 JSON 对象：\n'
    '{"term": "${word.term}", "translation": "..."}\n'
    '释义：$source';

String _translationPrompt(
  _SupplementalWord word,
  List<Map<String, Object?>> examples,
) {
  final sentences = <String>[
    for (final example in examples) '${example['sentence']}',
  ];
  return '把下列英文例句翻译成${word.targetLanguage}。'
      '只输出一个 JSON 对象，translations 的顺序与输入一致：\n'
      '{"term": "${word.term}", "translations": '
      '[{"sentence": "...", "translation": "..."}]}\n'
      '例句：\n${jsonEncode(sentences)}';
}

void _assertTerm(Object? returned, String expected) {
  final actual = returned is String ? returned.trim().toLowerCase() : '';
  if (actual != expected.trim().toLowerCase()) {
    throw ExternalServiceError(
      AppErrorCode.aiTermMismatch,
      details: '模型返回了其他词条：$returned',
    );
  }
}

bool _needsTranslation(Map<String, Object?> example) {
  final sentence = example['sentence'];
  final translation = example['translation'];
  return sentence is String &&
      sentence.trim().isNotEmpty &&
      (translation is! String || translation.trim().isEmpty);
}

Map<String, Object?> _decodeObject(String? raw) {
  if (raw == null || raw.isEmpty) return <String, Object?>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, Object?>();
  } on FormatException {
    return <String, Object?>{};
  }
  return <String, Object?>{};
}
