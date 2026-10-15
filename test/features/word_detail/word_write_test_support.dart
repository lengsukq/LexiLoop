/// 词条写操作 widget 测试的共用假件与数据夹具。
///
/// 放在测试目录里而不是 `test/support/`：这些假件只服务于「词条详情 /
/// 词库」这一块的写操作测试，放在通用目录里会让别的 feature 误以为
/// 它们是可以随便复用的基础设施。
library;

import 'package:drift/drift.dart' show Value;
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/tts_service.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';

import '../../services/audio/audio_fakes.dart';

/// 记录调用参数并返回预置结果的假词典。
///
/// 全程不发网络请求：预览与应用两条路径都只经由它。
class FakeWordLookup implements WordLookup {
  /// 预置结果；为 `null` 时返回一份空内容。
  DictionaryLookupResult? result;

  /// 最近一次调用的入参。
  Map<String, Object?>? lastCall;

  /// 被调用的次数。
  int calls = 0;

  @override
  Future<DictionaryLookupResult> lookup({
    required AppSettings settings,
    required ProviderRequest request,
    required List<String> selectedProviders,
    required ProviderStrategy strategy,
  }) async {
    calls += 1;
    lastCall = <String, Object?>{
      'term': request.term,
      'selectedProviders': selectedProviders,
      'strategy': strategy,
    };
    return result ??
        DictionaryLookupResult(
          content: emptyDictionaryContent(),
          attempts: const <ProviderAttemptRecord>[],
          hasTransientFailure: false,
          contentSource: ContentSource.dictionaryOnly,
        );
  }
}

/// 记录发音请求、永远返回「播放了真人录音」的假发音服务。
///
/// 继承真实的 `WordSpeaker` 而不是自己实现一个接口：这里要验证的正是
/// 「界面层把请求交给 WordSpeaker 时带对了参数」，用真类才能覆盖
/// `humanAudioEnabled` 这类状态字段。
class RecordingSpeaker extends WordSpeaker {
  /// 以全部为假的底层依赖构造。
  new()
    : super(
        FakeAudioPlayer(),
        AudioCache(FakeAudioDownloader()),
        TtsService(RecordingSpeechEngine()),
      );

  /// 收到的发音请求。
  final List<SpeechRequest> requests = <SpeechRequest>[];

  @override
  Future<SpeechResult> speak(SpeechRequest request) async {
    requests.add(request);
    return const HumanRecordingPlayed();
  }
}

/// 插入一个词条（含内容行），返回 ID。
Future<int> insertWordRow(
  AppDatabase db, {
  String term = 'apple',
  String definitionsJson = '[]',
  String examplesJson = '[]',
  String pronunciationsJson = '[]',
  String summaryJson = '{}',
  String confusedWordsJson = '[]',
  String synonymsJson = '[]',
  String? userNote,
  LexicalContentType contentType = LexicalContentType.word,
  String sourceLanguage = 'en',
  String targetLanguage = 'zh',
  InitializationStatus status = InitializationStatus.pending,
  int? now,
}) async {
  final timestamp = now ?? DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  final id = await db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: term,
          normalizedTerm: term.toLowerCase(),
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
          entryType: EntryType.word,
          contentType: Value<LexicalContentType>(contentType),
          initializationStatus: Value<InitializationStatus>(status),
          userNote: Value<String?>(userNote),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
  await db
      .into(db.wordContents)
      .insert(
        WordContentsCompanion.insert(
          wordId: Value<int>(id),
          definitionsJson: Value<String>(definitionsJson),
          examplesJson: Value<String>(examplesJson),
          pronunciationsJson: Value<String>(pronunciationsJson),
          summaryJson: Value<String>(summaryJson),
          confusedWordsJson: Value<String>(confusedWordsJson),
          synonymsJson: Value<String>(synonymsJson),
          updatedAt: timestamp,
        ),
      );
  return id;
}
