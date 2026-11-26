/// 选择题选项的构造。
///
/// 对应旧版 `modules/study/view.ts` 的 `generateMeaningChoices` 与
/// `generateWordChoices`。取候选（数据库查询）由 [DistractorSource] 负责，
/// 本类只决定「按什么优先级取、怎么去重、怎么打乱」——这条分界线让
/// 选项生成可以脱离数据库完整单测。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/distractors.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

/// 把词条内容变成一道题所需的选项。
class QuestionBuilder {
  /// 以干扰项来源构造（调用方写 `QuestionBuilder(source)`，签名不变）。
  const new(this._distractors);

  /// 干扰项候选来源（实现方负责限条数与排除题干词条）。
  final DistractorSource _distractors;

  /// 「看英选中」：返回打乱后的释义选项（含正确项）。
  ///
  /// 干扰项优先级：易混词释义 → 用户活跃错词释义 → 全局随机池。
  /// 凑不满时返回已凑到的（可能少于 [meaningChoiceCount]）——
  /// 三个来源都空时仍会给出一道「只有一个选项」的题，由调用方决定
  /// 是否改用别的题型，而不是在这里静默返回空。
  Future<List<String>> meaningChoices({
    required int wordId,
    required String targetLanguage,
    required List<DefinitionValue> definitions,
    required List<String> confusedTerms,
  }) async {
    final correct = targetDefinitionTexts(definitions, targetLanguage);
    // 没有正确项就没有题可出：其余三级补的都是干扰项。
    if (correct.isEmpty) return const <String>[];

    final choices = await _fillMeaningChoices(
      wordId: wordId,
      targetLanguage: targetLanguage,
      confusedTerms: confusedTerms,
      seed: <String>[correct],
    );
    return shuffleWith(choices, _random);
  }

  /// 「看汉选英」/听力选择：返回打乱后的词条选项与「选项 → 释义」映射。
  ///
  /// 每个选项都必须带释义：让用户面对一个没有释义的英文选项，
  /// 等于让他四选一乱猜。释义全空时返回空选项，调用方应改用别的题型。
  Future<QuestionChoices> wordChoices({
    required int wordId,
    required String term,
    required String targetLanguage,
    required List<DefinitionValue> definitions,
    required List<String> confusedTerms,
  }) async {
    final correct = term.trim();
    final correctDefinitions = targetDefinitionTexts(
      definitions,
      targetLanguage,
    );
    if (correct.isEmpty || correctDefinitions.isEmpty) {
      return const QuestionChoices(
        choices: <String>[],
        choiceDefinitions: <String, String>{},
      );
    }

    final definitionsByChoice = <String, String>{correct: correctDefinitions};
    final choices = await _fillWordChoices(
      wordId: wordId,
      targetLanguage: targetLanguage,
      confusedTerms: confusedTerms,
      seed: <String>[correct],
      definitionsByChoice: definitionsByChoice,
    );
    return QuestionChoices(
      choices: shuffleWith(choices, _random),
      choiceDefinitions: definitionsByChoice,
    );
  }

  /// 按「易混词 → 活跃错词 → 全局池」逐级补足释义选项，凑满即停。
  ///
  /// 三级共用同一份已选集合，所以跨来源的重复释义也会被剔除；
  /// 每级只在上一级没凑满时才发起查询，避免白跑数据库。
  Future<List<String>> _fillMeaningChoices({
    required int wordId,
    required String targetLanguage,
    required List<String> confusedTerms,
    required List<String> seed,
  }) async {
    var choices = seed;
    if (confusedTerms.isNotEmpty) {
      choices = await _appendMeaningStage(
        choices,
        targetLanguage,
        () => _distractors.byTerms(confusedTerms, wordId),
      );
    }
    if (choices.length < meaningChoiceCount) {
      choices = await _appendMeaningStage(
        choices,
        targetLanguage,
        () => _distractors.activeWrongWords(wordId),
      );
    }
    if (choices.length < meaningChoiceCount) {
      choices = await _appendMeaningStage(
        choices,
        targetLanguage,
        () => _distractors.randomPool(<int>{wordId}, distractorTakeSize),
      );
    }
    return choices;
  }

  /// 取一级候选并并入释义选项（内部完成判空、去重与截断）。
  Future<List<String>> _appendMeaningStage(
    List<String> choices,
    String targetLanguage,
    Future<List<DistractorRow>> Function() rows,
  ) async => collectDistinct(
    choices,
    _meaningCandidates(await rows(), targetLanguage),
    limit: meaningChoiceCount,
  );

  /// 按同一优先级逐级补足词条选项，并同步补上每个选项的释义。
  ///
  /// [definitionsByChoice] 是输出参数：新加入的选项会就地写入释义，
  /// 调用方据此构造 `QuestionChoices`。
  Future<List<String>> _fillWordChoices({
    required int wordId,
    required String targetLanguage,
    required List<String> confusedTerms,
    required List<String> seed,
    required Map<String, String> definitionsByChoice,
  }) async {
    var choices = seed;
    if (confusedTerms.isNotEmpty) {
      choices = await _appendWordStage(
        choices,
        targetLanguage,
        definitionsByChoice,
        () => _distractors.byTerms(confusedTerms, wordId),
      );
    }
    if (choices.length < meaningChoiceCount) {
      choices = await _appendWordStage(
        choices,
        targetLanguage,
        definitionsByChoice,
        () => _distractors.activeWrongWords(wordId),
      );
    }
    if (choices.length < meaningChoiceCount) {
      choices = await _appendWordStage(
        choices,
        targetLanguage,
        definitionsByChoice,
        () => _distractors.randomPool(<int>{wordId}, distractorTakeSize),
      );
    }
    return choices;
  }

  /// 取一级候选并并入词条选项：词条与释义都非空才收。
  ///
  /// 去重仍交给 [collectDistinct]，但词条还要带着自己的释义一起进映射，
  /// 故这里先建「选项 → 释义」再按去重结果回填。
  Future<List<String>> _appendWordStage(
    List<String> choices,
    String targetLanguage,
    Map<String, String> definitionsByChoice,
    Future<List<DistractorRow>> Function() rows,
  ) async {
    final candidates = _wordCandidates(await rows(), targetLanguage);
    final merged = collectDistinct(
      choices,
      candidates.keys,
      limit: meaningChoiceCount,
    );
    for (final choice in merged) {
      final definition = candidates[choice];
      if (definition == null) continue;
      definitionsByChoice.putIfAbsent(choice, () => definition);
    }
    return merged;
  }

  /// 把干扰项行映射成「目标语言首选释义」文本。
  ///
  /// 释义为空的行返回 `null`，由 [collectDistinct] 跳过——旧版在这里
  /// 各写了一次 `if (text && !seen.has(...))`，正是 6 处重复的来源。
  Iterable<String?> _meaningCandidates(
    List<DistractorRow> rows,
    String targetLanguage,
  ) => rows.map(
    (row) => preferredDefinitionText(
      parseDefinitionsJson(row.definitionsJson),
      targetLanguage,
    ),
  );

  /// 把候选行映射成「选项文本 → 目标语言释义」。
  ///
  /// 词条或释义为空的行直接丢弃；同一个词条重复出现时保留先来的那条，
  /// 与旧版「先到先得」的 `seen` 语义一致。
  Map<String, String> _wordCandidates(
    List<DistractorRow> rows,
    String targetLanguage,
  ) {
    final candidates = <String, String>{};
    for (final row in rows) {
      final choice = row.term.trim();
      final definition = targetDefinitionTexts(
        parseDefinitionsJson(row.definitionsJson),
        targetLanguage,
      );
      if (choice.isEmpty || definition.isEmpty) continue;
      candidates.putIfAbsent(choice, () => definition);
    }
    return candidates;
  }
}

/// 打乱选项用的随机源。
///
/// 刻意不做成构造参数：公开 API 由调用方约定为 `QuestionBuilder(source)`，
/// 而选项顺序对正确性没有影响（测试断言的是集合而非顺序），
/// 因此不为可测性给生产构造签名加参数。
final double Function() _random = math.Random().nextDouble;
