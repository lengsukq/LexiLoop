/// 学习揭示扩展区（易混词、句法解析、详情入口）与按标签专项复习测试。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/answer_evaluator.dart';
import 'package:lexiloop/features/study/study_reveal.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/study_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() => db.close());

  Future<int> insertWord({
    required String term,
    required String definition,
    String tagsJson = '[]',
    String confusedWordsJson = '[]',
    String sentenceAnalysisJson = '{}',
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh-CN',
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
              '[{"language":"zh-CN","text":"$definition"}]',
            ),
            tagsJson: Value<String>(tagsJson),
            confusedWordsJson: Value<String>(confusedWordsJson),
            sentenceAnalysisJson: Value<String>(sentenceAnalysisJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  test('loadStudyRevealContent 读取易混词与句法解析', () async {
    final id = await insertWord(
      term: 'adapt',
      definition: '适应',
      confusedWordsJson:
          '[{"word":"adopt","translation":"采纳；收养", '
          '"difference":"adapt 强调适应，adopt 强调采用"}]',
      sentenceAnalysisJson:
          '{"grammarPattern":"S + V + to + N", '
          '"grammarNotes":["不及物动词需接介词 to"]}',
    );

    final content = await loadStudyRevealContent(db, id);
    expect(content.isEmpty, isFalse);
    expect(content.confusedWords, hasLength(1));
    expect(content.confusedWords.single.word, 'adopt');
    expect(content.confusedWords.single.difference, contains('adopt'));
    expect(content.sentenceAnalysis.grammarPattern, 'S + V + to + N');
    expect(content.sentenceAnalysis.grammarNotes, <String>['不及物动词需接介词 to']);
  });

  test('StudyService.startSession(tag:) 仅抽取带指定标签的词条', () async {
    await insertWord(
      term: 'resilient',
      definition: '有韧性的',
      tagsJson: '["IELTS"]',
    );
    await insertWord(
      term: 'ubiquitous',
      definition: '无处不在的',
      tagsJson: '["GRE"]',
    );
    final service = StudyService(db, SettingsService(SettingsDao(db)));

    final session = await service.startSession(
      mode: StudyMode.daily,
      now: now,
      tag: 'IELTS',
    );

    expect(session.items, hasLength(1));
    expect(session.items.single.word.term, 'resilient');
    expect(session.sourceType, 'TAG:IELTS');
  });

  testWidgets('StudyRevealPanel 展示易混词辨析、句法解析并触发详情入口', (tester) async {
    var openedDetail = false;
    const item = StudyItemView(
      itemId: 1,
      position: 0,
      taskType: StudyTaskType.newWord,
      questionType: QuestionType.enToZh,
      status: StudyItemStatus.pending,
      word: StudyWordView(
        id: 7,
        term: 'adapt',
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
        contentType: LexicalContentType.word,
        definitions: <DefinitionValue>[
          DefinitionValue(language: 'zh-CN', text: '适应'),
        ],
        pronunciations: <PronunciationView>[],
        examples: <ExampleView>[],
      ),
    );
    const reveal = StudyRevealContent(
      confusedWords: <RelatedWordView>[
        RelatedWordView(
          word: 'adopt',
          translation: '采用',
          difference: 'adapt=适应，adopt=采用',
        ),
      ],
      sentenceAnalysis: SentenceAnalysisView(
        grammarPattern: 'adapt to + N',
        grammarNotes: <String>['常用于被动或不及物结构'],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LexiTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudyRevealPanel(
                item: item,
                preview: const AnswerPreview(
                  isCorrect: true,
                  expectedAnswer: '适应',
                ),
                answer: '适应',
                usedHint: false,
                accent: Accent.us,
                revealContent: reveal,
                onOpenDetail: () => openedDetail = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('易混词辨析'), findsOneWidget);
    expect(find.text('句法解析'), findsOneWidget);

    await tester.tap(find.text('易混词辨析'));
    await tester.pumpAndSettle();
    expect(find.text('adopt · 采用'), findsOneWidget);
    expect(find.text('adapt=适应，adopt=采用'), findsOneWidget);

    await tester.tap(find.text('句法解析'));
    await tester.pumpAndSettle();
    expect(find.text('句型：adapt to + N'), findsOneWidget);

    await tester.tap(find.byKey(const Key('study.openWordDetail')));
    expect(openedDetail, isTrue);
  });
}
