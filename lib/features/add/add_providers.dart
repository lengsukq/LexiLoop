/// 添加词条的状态与数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 词条写入服务。
final Provider<WordEditService> wordEditServiceProvider =
    Provider<WordEditService>(
      (ref) => WordEditService(ref.watch(databaseProvider)),
    );

/// 可选语言（代码 → 中文名）。
///
/// 代码取值与旧版 `lib/language.ts` 的 `LANGUAGE_MAP` 一致，**不是裸 ISO 639-1**：
/// 中文用 `zh-CN` 而不是 `zh`。这一点很关键——真实备份里
/// `words.target_language` 全是 `zh-CN`，而 `definitions_json` 里每条释义的
/// `language` 也是 `zh-CN`，判题时靠它筛「目标语言释义」。若这里写成 `zh`，
/// 手动添加的词条会与整库的语言代码不一致，释义将永远匹配不上。
const Map<String, String> supportedLanguages = <String, String>{
  'en': '英语',
  'zh-CN': '简体中文',
  'zh-TW': '繁体中文',
  'nl': '荷兰语',
  'ja': '日语',
  'ko': '韩语',
  'fr': '法语',
  'de': '德语',
  'es': '西班牙语',
  'it': '意大利语',
  'pt': '葡萄牙语',
  'ru': '俄语',
};

/// 默认目标语言。
///
/// 与真实备份一致（见 [supportedLanguages] 的说明）。
const String defaultTargetLanguage = 'zh-CN';

/// 默认源语言。
const String defaultSourceLanguage = 'en';

/// 手动录入表单的状态。
class ManualEntryState {
  /// 以各字段构造。
  const new({
    this.term = '',
    this.contentType = LexicalContentType.word,
    this.sourceLanguage = defaultSourceLanguage,
    this.targetLanguage = defaultTargetLanguage,
    this.definitionsText = '',
    this.phonetic = '',
    this.examplesText = '',
    this.tagsText = '',
    this.note = '',
    this.submitting = false,
    this.error,
    this.createdWordId,
  });

  /// 词条文本。
  final String term;

  /// 内容类型。
  final LexicalContentType contentType;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 释义文本（每行一条）。
  final String definitionsText;

  /// 音标。
  final String phonetic;

  /// 例句文本（每行「句子 | 翻译」）。
  final String examplesText;

  /// 标签文本（逗号或空格分隔）。
  final String tagsText;

  /// 用户笔记。
  final String note;

  /// 是否正在提交。
  final bool submitting;

  /// 提交错误的中文提示；无错误时为 `null`。
  final String? error;

  /// 创建成功后的词条 ID。
  final int? createdWordId;

  /// 是否已成功创建。
  bool get isCreated => createdWordId != null;

  /// 表单是否可提交。
  bool get canSubmit => term.trim().isNotEmpty && !submitting;

  /// 复制并覆盖部分字段。
  ManualEntryState copyWith({
    String? term,
    LexicalContentType? contentType,
    String? sourceLanguage,
    String? targetLanguage,
    String? definitionsText,
    String? phonetic,
    String? examplesText,
    String? tagsText,
    String? note,
    bool? submitting,
    String? error,
    bool clearError = false,
    int? createdWordId,
    bool clearCreated = false,
  }) => ManualEntryState(
    term: term ?? this.term,
    contentType: contentType ?? this.contentType,
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    definitionsText: definitionsText ?? this.definitionsText,
    phonetic: phonetic ?? this.phonetic,
    examplesText: examplesText ?? this.examplesText,
    tagsText: tagsText ?? this.tagsText,
    note: note ?? this.note,
    submitting: submitting ?? this.submitting,
    error: clearError ? null : (error ?? this.error),
    createdWordId: clearCreated ? null : (createdWordId ?? this.createdWordId),
  );

  /// 把释义文本切成条目列表。
  List<String> get definitions => splitLines(definitionsText);

  /// 把例句文本解析为草稿列表。
  List<WordExampleDraft> get examples => parseExamples(examplesText);

  /// 把标签文本切成列表。
  List<String> get tags => splitTags(tagsText);
}

/// 手动录入控制器。
class ManualEntryController extends Notifier<ManualEntryState> {
  @override
  ManualEntryState build() => const ManualEntryState();

  /// 覆盖表单字段。
  ///
  /// 顺带清掉上一次的报错与成功回执：用户继续编辑就说明他想重新提交，
  /// 此时还挂着「词条已存在」或「已添加」都会造成误解。
  void replace(ManualEntryState next) {
    state = next.copyWith(clearError: true, clearCreated: true);
  }

  /// 提交表单。
  Future<void> submit({required int now}) async {
    if (!state.canSubmit) return;
    state = state.copyWith(submitting: true, clearError: true);

    try {
      final wordId = await ref
          .read(wordEditServiceProvider)
          .create(
            draft: WordDraft(
              term: state.term,
              contentType: state.contentType,
              sourceLanguage: state.sourceLanguage,
              targetLanguage: state.targetLanguage,
              definitions: state.definitions,
              phonetic: state.phonetic,
              examples: state.examples,
              tags: state.tags,
              note: state.note,
            ),
            now: now,
          );
      state = state.copyWith(submitting: false, createdWordId: wordId);
    } on AppError catch (error) {
      state = state.copyWith(submitting: false, error: error.message);
    }
  }

  /// 回到空白表单，准备添加下一个。
  void reset() => state = const ManualEntryState();
}

/// 手动录入提供者。
final NotifierProvider<ManualEntryController, ManualEntryState>
manualEntryProvider = NotifierProvider<ManualEntryController, ManualEntryState>(
  ManualEntryController.new,
);

/// 按行切分并去掉空行。
List<String> splitLines(String value) => value
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

/// 按逗号、顿号或空白切分标签。
List<String> splitTags(String value) => value
    .split(RegExp(r'[,，、\s]+'))
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toList(growable: false);

/// 解析例句文本。
///
/// 每行格式为 `句子 | 翻译`，竖线可省略（只填句子）。
List<WordExampleDraft> parseExamples(String value) {
  final result = <WordExampleDraft>[];
  for (final line in splitLines(value)) {
    final parts = line.split('|');
    final sentence = parts.first.trim();
    if (sentence.isEmpty) continue;
    final translation = parts.length > 1 ? parts[1].trim() : '';
    result.add(
      WordExampleDraft(
        sentence: sentence,
        translation: translation.isEmpty ? null : translation,
      ),
    );
  }
  return result;
}
