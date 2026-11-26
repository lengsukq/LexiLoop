/// 本地视觉验收共用的演示数据，只写调用方提供的内存库。
library;

import 'package:drift/drift.dart' show Value;
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

/// 塞入一批演示数据：不同掌握度、有作答记录、有初始化任务。
Future<void> seedDemoData(AppDatabase db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  const terms = <String>[
    'apple',
    'banana',
    'cherry',
    'dragonfruit',
    'elderberry',
    'fig',
    'grape',
    'honeydew',
  ];
  for (var i = 0; i < terms.length; i += 1) {
    final term = terms[i];
    await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term,
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: now - i * 86400000,
            updatedAt: now - i * 86400000,
          ),
        );
  }
  final ids = await db.select(db.words).get();
  for (final word in ids) {
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(word.id),
            summaryJson: const Value<String>(
              '{"shortDefinition":"a sample word","translation":"示例词"}',
            ),
            definitionsJson: Value<String>(
              '[{"language":"zh","text":"${word.term} 的示例释义"}]',
            ),
            pronunciationsJson: const Value<String>(
              '[{"accent":"US","phonetic":"æpl","source":"manual"}]',
            ),
            updatedAt: now,
          ),
        );
    await db
        .into(db.reviewCards)
        .insert(
          ReviewCardsCompanion.insert(
            wordId: Value<int>(word.id),
            dueAt: now - 1000,
            stability: 1,
            difficulty: 5,
            elapsedDays: 0,
            scheduledDays: 1,
            reps: 1,
            lapses: 0,
            fsrsState: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
  // 作答记录：让统计页的折线与表格有东西可画。
  for (var day = 0; day < 12; day += 1) {
    for (var n = 0; n < (day % 5) + 2; n += 1) {
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              clientAnswerId: 'shot-$day-$n',
              wordId: ids[day % ids.length].id,
              reviewedAt: now - day * 86400000 + n * 60000,
              rating: n.isEven ? ReviewRating.good : ReviewRating.again,
              questionType: QuestionType.enToZhChoice,
              isCorrect: n.isEven,
              durationMs: const Value<int>(4200),
              createdAt: now - day * 86400000 + n * 60000,
            ),
          );
    }
  }
}
