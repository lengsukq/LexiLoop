/// 音标训练编排的集成测试。
///
/// 最重要的一条：**音标训练不写 `review_logs`**。
/// 旧版 `modules/phonetics/service.ts` 复用 `completePracticeSession`，
/// 因此旧版实际上会写复习日志并把那些词条的 FSRS 一起推进（详见
/// `PhoneticService` 的类文档）；本版按规格改为只记 `study_sessions`
/// 与 `game_high_scores`，这个测试就是那条边界的守卫。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/phonetics/quiz.dart';
import 'package:lexiloop/domain/phonetics/selection.dart';
import 'package:lexiloop/services/phonetic_service.dart';

import '../domain/games/random_source.dart';

void main() {
  late AppDatabase db;
  late PhoneticService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = PhoneticService(StudyDao(db), GameDao(db));
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 插入一个带发音的词条。
  Future<void> insertWord({
    required String term,
    required String meaning,
    required String usPhonetic,
    String? ukPhonetic,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final uk = ukPhonetic == null
        ? ''
        : ',{"accent":"UK","phonetic":"$ukPhonetic"}';
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(
              '[{"language":"zh","text":"$meaning"}]',
            ),
            pronunciationsJson: Value<String>(
              '[{"accent":"US","phonetic":"$usPhonetic"}$uk]',
            ),
            updatedAt: now,
          ),
        );
  }

  /// 插入 6 个带美音音标的词条。
  Future<void> insertPhoneticWords() async {
    const samples = <List<String>>[
      <String>['sheep', '绵羊', 'ʃiːp'],
      <String>['ship', '船', 'ʃɪp'],
      <String>['bed', '床', 'bed'],
      <String>['bad', '坏的', 'bæd'],
      <String>['food', '食物', 'fuːd'],
      <String>['bird', '鸟', 'bɜːd'],
    ];
    for (final sample in samples) {
      await insertWord(
        term: sample[0],
        meaning: sample[1],
        usPhonetic: sample[2],
      );
    }
  }

  test('没有可用音标时抛 notEnoughPhoneticWords', () async {
    // 有 4 个词条，但都没有发音。
    for (var index = 0; index < 4; index += 1) {
      final suffix = String.fromCharCode(97 + index);
      final id = await db
          .into(db.words)
          .insert(
            WordsCompanion.insert(
              term: 'term$suffix',
              normalizedTerm: 'term$suffix',
              sourceLanguage: 'en',
              targetLanguage: 'zh',
              entryType: EntryType.word,
              initializationStatus: const Value<InitializationStatus>(
                InitializationStatus.ready,
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.wordContents)
          .insert(
            WordContentsCompanion.insert(
              wordId: Value<int>(id),
              definitionsJson: Value<String>(
                '[{"language":"zh","text":"释义$suffix"}]',
              ),
              updatedAt: now,
            ),
          );
    }
    await expectLater(
      service.start(accent: Accent.us, now: now),
      throwsA(
        isA<ConflictError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.notEnoughPhoneticWords,
        ),
      ),
    );
  });

  test('缺少目标口音时同样抛错（不回退到另一口音）', () async {
    await insertPhoneticWords();
    await expectLater(
      service.start(accent: Accent.uk, now: now),
      throwsA(isA<ConflictError>()),
    );
  });

  test('开局创建会话、题型为听音拼写、来源为 PHONETIC_TRAINING', () async {
    await insertPhoneticWords();
    final session = await service.start(
      accent: Accent.us,
      now: now,
      random: constantRandom(),
    );
    expect(session.accent, Accent.us);
    expect(session.questions, isNotEmpty);
    expect(session.questions.length, lessThanOrEqualTo(phoneticItemCount));
    expect(session.plan.durationMs, phoneticDurationSeconds * 1000);
    for (final question in session.questions) {
      expect(question.base.choices.options.length, phoneticChoiceCount);
      expect(question.sound.phonetic, startsWith('/'));
      expect(question.entry.symbol, isNotEmpty);
    }
    final row = await (db.select(
      db.studySessions,
    )..where((item) => item.id.equals(session.sessionId))).getSingle();
    expect(row.sourceType, phoneticTrainingSourceType);
    expect(row.sessionType, StudyMode.listening);
    final items = await (db.select(
      db.studySessionItems,
    )..where((item) => item.studySessionId.equals(session.sessionId))).get();
    expect(
      items.every(
        (item) => item.questionType == QuestionType.listeningSpelling,
      ),
      isTrue,
    );
    expect(
      items.every((item) => item.taskType == StudyTaskType.listening),
      isTrue,
    );
  });

  test('口音决定出题：英音音标单独可用', () async {
    await insertWord(
      term: 'car',
      meaning: '汽车',
      usPhonetic: 'kɑr',
      ukPhonetic: 'kɑː',
    );
    await insertWord(
      term: 'hot',
      meaning: '热',
      usPhonetic: 'hɑt',
      ukPhonetic: 'hɒt',
    );
    await insertWord(
      term: 'bird',
      meaning: '鸟',
      usPhonetic: 'bɝːd',
      ukPhonetic: 'bɜːd',
    );
    await insertWord(
      term: 'more',
      meaning: '更多',
      usPhonetic: 'mɔr',
      ukPhonetic: 'mɔː',
    );
    final session = await service.start(
      accent: Accent.uk,
      now: now,
      random: constantRandom(),
    );
    expect(session.accent, Accent.uk);
    for (final question in session.questions) {
      final usForms = <String>{'/kɑr/', '/hɑt/', '/bɝːd/', '/mɔr/'};
      expect(usForms, isNot(contains(question.sound.phonetic)));
    }
  });

  test('结算只写会话与高分榜，不写复习日志', () async {
    await insertPhoneticWords();
    final session = await service.start(
      accent: Accent.us,
      now: now,
      random: constantRandom(),
    );
    var quiz = startPhoneticQuiz(
      plan: session.plan,
      questions: session.questions,
    );
    quiz = phoneticQuizNext(quiz, const StartPhoneticQuiz());
    // 第 1 题答对，第 2 题答错后跳过，其余靠时间耗尽。
    final first = quiz.current!;
    quiz = phoneticQuizNext(quiz, ChoosePhonetic(first.answer));
    quiz = phoneticQuizNext(quiz, const ContinuePhonetic());
    final second = quiz.current!;
    final wrong = second.base.choices.options.firstWhere(
      (option) => option != second.answer,
    );
    quiz = phoneticQuizNext(quiz, ChoosePhonetic(wrong));
    quiz = phoneticQuizNext(quiz, const ContinuePhonetic());
    quiz = phoneticQuizNext(quiz, const SkipPhonetic());
    quiz = phoneticQuizNext(quiz, const ContinuePhonetic());

    final result = await service.complete(
      session: session,
      state: quiz,
      now: now + 20000,
    );
    expect(result.mode, GameMode.phonetics);
    expect(result.summary.firstTryCorrect, 1);
    expect(result.summary.missed, session.questions.length - 2);

    final logs = await db
        .customSelect('SELECT count(*) AS c FROM review_logs')
        .getSingle();
    expect(logs.read<int>('c'), 0, reason: '音标训练不写复习日志');

    final sessionRow = await (db.select(
      db.studySessions,
    )..where((row) => row.id.equals(session.sessionId))).getSingle();
    expect(sessionRow.completedAt, isNotNull);
    expect(sessionRow.correctCount, 1);
    expect(sessionRow.durationMs, greaterThan(0));

    final scores = await (db.select(db.gameHighScores)).get();
    expect(scores.single.gameMode, 'PHONETICS');
    expect(scores.single.score, result.score);
  });

  test('跳过与超时的题目记为过期跳过', () async {
    await insertPhoneticWords();
    final session = await service.start(
      accent: Accent.us,
      now: now,
      random: constantRandom(),
    );
    var quiz = phoneticQuizNext(
      startPhoneticQuiz(plan: session.plan, questions: session.questions),
      const StartPhoneticQuiz(),
    );
    quiz = phoneticQuizNext(
      quiz,
      TickPhoneticQuiz(phoneticDurationSeconds * 1000),
    );
    expect(quiz.core.isFinished, isTrue);
    await service.complete(session: session, state: quiz, now: now + 75000);
    final skipped = await (db.select(
      db.studySessionItems,
    )..where((row) => row.status.equalsValue(StudyItemStatus.skipped))).get();
    expect(skipped.length, session.questions.length);
    expect(
      skipped.every((item) => item.skipReason == 'SESSION_EXPIRED'),
      isTrue,
    );
  });

  test('再次开局会收尾上一局未完成的音标会话', () async {
    await insertPhoneticWords();
    final first = await service.start(
      accent: Accent.us,
      now: now,
      random: constantRandom(),
    );
    await service.start(
      accent: Accent.us,
      now: now + 1000,
      random: constantRandom(),
    );
    final row = await (db.select(
      db.studySessions,
    )..where((item) => item.id.equals(first.sessionId))).getSingle();
    expect(row.completedAt, isNotNull);
  });
}
