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
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/dictionary_constants.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/providers/ai_lexical_content.dart';
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
    final client = await _client();
    switch (taskType) {
      case JobTaskType.mnemonic:
        await _writeMnemonic(client, word, wordId, now);
      case JobTaskType.exampleTranslations:
        await _translateExamples(client, word, wordId, now);
      case JobTaskType.initialize:
        return;
    }
  }

  Future<LlmClient> _client() async {
    final settings = await _settings.load();
    final config = llmConfigFromRaw(settings.raw[llmConfigSettingsKey]);
    if (!config.isUsable) {
      throw const ExternalServiceError(
        AppErrorCode.aiDisabled,
        details: 'AI 未启用或配置不完整，无法执行补充任务',
      );
    }
    return LlmClient(_fetcher, config);
  }

  Future<_SupplementalWord> _loadWord(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT w.term, w.source_language, w.target_language, '
          'w.content_type, wc.learning_json, wc.examples_json FROM words w '
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

  Future<void> _translateExamples(
    LlmClient client,
    _SupplementalWord word,
    int wordId,
    int now,
  ) async {
    final examples = _decodeList(word.examplesJson);
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
    final translations = output['translations'];
    if (translations is! List) {
      throw const ExternalServiceError(
        AppErrorCode.aiSchemaInvalid,
        details: 'translations 不是数组',
      );
    }
    final bySentence = <String, String>{};
    for (final item in translations) {
      if (item is! Map) continue;
      final sentence = item['sentence'];
      final translation = item['translation'];
      if (sentence is String && translation is String) {
        bySentence[sentence.trim()] = translation.trim();
      }
    }
    if (bySentence.isEmpty) {
      throw const ExternalServiceError(
        AppErrorCode.aiSemanticInvalid,
        details: '例句翻译结果为空',
      );
    }
    for (final example in examples) {
      if (example is! Map) continue;
      final record = example.cast<String, Object?>();
      final sentence = record['sentence'];
      if (sentence is! String) continue;
      final translation = bySentence[sentence.trim()];
      if (translation != null && translation.isNotEmpty) {
        record['translation'] = translation;
      }
    }
    await _updateColumn(wordId, 'examples_json', examples, now);
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
  });

  final String term;
  final String sourceLanguage;
  final String targetLanguage;
  final String? learningJson;
  final String? examplesJson;
}

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

List<Object?> _decodeList(String? raw) {
  if (raw == null || raw.isEmpty) return <Object?>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
  } on FormatException {
    return <Object?>[];
  }
  return <Object?>[];
}
