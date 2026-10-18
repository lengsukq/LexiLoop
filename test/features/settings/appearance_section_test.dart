/// 「外观」设置分组的 widget 测试。
///
/// 这里只钉三件事：点色板写对键、切换模式写对 wire、恢复默认删掉三个键。
/// 颜色推导本身在 `test/ui/theme_palette_test.dart` 里逐对验对比度。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show InsertMode;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/settings/settings_page.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: LexiTheme.light, home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Object?> stored(String key) async {
    final rows = await db.select(db.settings).get();
    for (final row in rows) {
      if (row.key == key) return jsonDecode(row.valueJson);
    }
    return null;
  }

  testWidgets('点主色预设写入 themePrimaryColor', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(const Key('appearancePrimarySwatch-blue')));
    await tester.pumpAndSettle();

    expect(await stored('themePrimaryColor'), 0xFF0A84FF);
  });

  testWidgets('点次色预设写入 themeSecondaryColor', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(const Key('appearanceSecondarySwatch-pink')));
    await tester.pumpAndSettle();

    expect(await stored('themeSecondaryColor'), 0xFFFF2D55);
  });

  testWidgets('切换外观模式写入 themeMode', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(const Key('appearanceModeDark')));
    await tester.pumpAndSettle();

    expect(await stored('themeMode'), 'dark');
  });

  testWidgets('自定义色确认后写入色种', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(const Key('appearancePrimaryCustom')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearanceCustomConfirm')));
    await tester.pumpAndSettle();

    expect(await stored('themePrimaryColor'), isA<int>());
  });

  testWidgets('恢复默认删除三个键', (tester) async {
    await db
        .into(db.settings)
        .insert(
          SettingsCompanion.insert(
            key: 'themePrimaryColor',
            valueJson: jsonEncode(0xFF0A84FF),
            updatedAt: 1,
          ),
          mode: InsertMode.insertOrReplace,
        );
    await pumpSettings(tester);

    final reset = find.byKey(const Key('appearanceReset'));
    await tester.scrollUntilVisible(
      reset,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(reset);
    await tester.pumpAndSettle();

    expect(await stored('themePrimaryColor'), isNull);
    expect(await stored('themeMode'), isNull);
    expect(await stored('themeSecondaryColor'), isNull);
  });
}
