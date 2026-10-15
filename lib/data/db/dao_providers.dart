/// 数据访问与领域服务的提供者。
///
/// 集中在一处，使「谁依赖谁」一眼可见；各 feature 只 import 本文件，
/// 不直接构造 DAO，避免同一服务被构造多份（例如 [SettingsService] 内部有
/// 缓存，构造两份就会出现「改了设置另一份看不到」）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/review_dao.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/review_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/study_service.dart';
import 'package:lexiloop/services/tts_service.dart';

/// 词条查询。
final Provider<WordDao> wordDaoProvider = Provider<WordDao>(
  (ref) => WordDao(ref.watch(databaseProvider)),
);

/// 设置读写。
final Provider<SettingsDao> settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(ref.watch(databaseProvider)),
);

/// 设置服务（含内存缓存，必须单例）。
final Provider<SettingsService> settingsServiceProvider =
    Provider<SettingsService>(
      (ref) => SettingsService(ref.watch(settingsDaoProvider)),
    );

/// 作答处理。
final Provider<ReviewService> reviewServiceProvider = Provider<ReviewService>(
  (ref) => ReviewService(
    ref.watch(databaseProvider),
    ref.watch(settingsServiceProvider),
  ),
);

/// 学习会话编排。
final Provider<StudyService> studyServiceProvider = Provider<StudyService>(
  (ref) => StudyService(
    ref.watch(databaseProvider),
    ref.watch(settingsServiceProvider),
  ),
);

/// 复习读写（供只读查询使用）。
final Provider<ReviewDao> reviewDaoProvider = Provider<ReviewDao>(
  (ref) => ReviewDao(ref.watch(databaseProvider)),
);

/// 学习会话读写（供只读查询使用）。
final Provider<StudyDao> studyDaoProvider = Provider<StudyDao>(
  (ref) => StudyDao(ref.watch(databaseProvider)),
);

/// 语音朗读。
///
/// 界面层通过这个 provider 取服务，测试里用 `overrideWithValue` 换成假引擎，
/// 避免在测试进程里初始化平台通道。
final Provider<TtsService> ttsServiceProvider = Provider<TtsService>(
  (ref) => TtsService(FlutterTtsEngine()),
);

/// 当前应用设置。
final FutureProvider<AppSettings> appSettingsProvider =
    FutureProvider<AppSettings>(
      (ref) => ref.watch(settingsServiceProvider).load(),
    );
