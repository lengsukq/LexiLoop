/// 有内容的路由在明暗模式、大字体和低高度下仍可操作。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/dashboard/cards/statistics_card.dart';
import 'package:lexiloop/features/dashboard/cards/today_plan_card.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/services/tts_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

import '../../tool/visual_fixture.dart';
import '../services/audio/audio_fakes.dart';

const routes = <String>[
  '/',
  '/study',
  '/words',
  '/words/1',
  '/add',
  '/initialize',
  '/statistics',
  '/settings',
  '/phonetics',
  '/import',
  '/article',
  '/games',
  '/match',
];

void main() {
  for (final route in routes) {
    for (final dark in <bool>[false, true]) {
      testWidgets('$route 有内容 ${dark ? "深" : "浅"}色与大字体', (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await seedDemoData(db);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final router = createAppRouter(initialLocation: route);
        addTearDown(router.dispose);
        for (final (size, factor) in <(Size, double)>[
          (const Size(360, 900), 2),
          (const Size(390, 844), 1),
          (const Size(1280, 560), 1),
          (const Size(1023, 900), 1),
          (const Size(1024, 900), 1),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            ProviderScope(
              overrides: <Override>[
                databaseProvider.overrideWithValue(db),
                audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
                audioDownloaderProvider.overrideWithValue(
                  FakeAudioDownloader(),
                ),
                ttsServiceProvider.overrideWithValue(
                  TtsService(RecordingSpeechEngine()),
                ),
                studyClockFactoryProvider.overrideWithValue(
                  () => StudyClock(
                    now: () => DateTime.now().millisecondsSinceEpoch,
                  ),
                ),
              ],
              child: MaterialApp.router(
                theme: dark ? LexiTheme.dark : LexiTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(factor)),
                  child: AdaptiveTypography(child: child!),
                ),
                routerConfig: router,
              ),
            ),
          );
          for (var frame = 0; frame < 15; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '$route $size × $factor',
          );
          if (route == '/' && size == const Size(390, 844)) {
            for (final finder in <Finder>[
              find.byKey(startStudyButtonKey),
              find.byKey(totalWordsKey),
              find.text('限时配对'),
              find.text('音标辨音'),
            ]) {
              expect(tester.getTopLeft(finder).dy, greaterThanOrEqualTo(0));
              expect(
                tester.getBottomLeft(finder).dy,
                lessThan(772),
                reason: '首屏主操作、概览与两个练习入口均应在底栏上方',
              );
            }
          }
        }
      });
    }
  }
}
