/// 原生界面验收入口：独立内存库，关闭后台维护与外部词典/AI请求。
/// flutter run --no-pub -d macos -t tool/visual_preview.dart
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lexiloop/app.dart';
import 'package:lexiloop/app/desktop_window.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';

import '../test/data/dictionary/fake_http_fetcher.dart';
import '../test/services/audio/audio_fakes.dart';
import 'visual_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();
  final database = AppDatabase(NativeDatabase.memory());
  await seedDemoData(database);
  runApp(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(database),
        httpFetcherProvider.overrideWithValue(
          FakeHttpFetcher(
            (_, _) async =>
                const HttpFetchResponse(statusCode: 503, body: '视觉预览不连接外部服务'),
          ),
        ),
        audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
        audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
      ],
      child: const LexiLoopApp(),
    ),
  );
}
