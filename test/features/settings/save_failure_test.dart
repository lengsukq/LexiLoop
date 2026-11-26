/// 设置写库失败的可见性测试。
///
/// **它守的是什么**：收敛前十几处设置调用都写成
/// `unawaited(saveSettings(...))`——写失败既没有提示，也不会回滚。
/// 用户看到的是一次「成功」的切换，下次冷启动值又弹回来，
/// 于是得出结论「这个设置不生效」，而实际上是一次被吞掉的写入异常。
///
/// 这里钉住两条契约：失败时**界面上必须出现一句话**，并且调用本身
/// 不再把异常抛给调用方（抛出去就会被 `unawaited` 吞掉）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/feedback/messenger.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 每次写入都失败的设置服务。
class _ThrowingSettingsService extends SettingsService {
  new(super._dao);

  @override
  Future<AppSettings> update(
    Map<String, Object?> changes, {
    required int now,
  }) async {
    throw const ValidationError(AppErrorCode.validationError);
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(
          overrides: <Override>[
            databaseProvider.overrideWithValue(db),
            settingsServiceProvider.overrideWithValue(
              _ThrowingSettingsService(SettingsDao(db)),
            ),
          ],
        ),
        child: MaterialApp(
          theme: LexiTheme.light,
          scaffoldMessengerKey: appMessengerKey,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    saveSettings(ref, <String, Object?>{'dailyNewWords': 20}),
                child: const Text('写设置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('写库失败时界面出现提示，而不是静默', (tester) async {
    await pump(tester);

    await tester.tap(find.text('写设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('设置未保存'),
      findsOneWidget,
      reason: '失败必须说给用户听；静默失败会让设置看起来「不生效」',
    );
  });

  testWidgets('失败不再抛给调用方（否则会被 unawaited 吞掉）', (tester) async {
    await pump(tester);

    // 点击回调里没有 try/catch，能走到这一步就说明异常没有逃逸。
    await tester.tap(find.text('写设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
