/// `pronunciations_json` 的来源字段是否落到了视图模型上。
///
/// 旧版详情页靠 `pronunciations[].source === "youdao"` 决定是否优先播放
/// 真人录音。这一列必须一路传到 `PronunciationView`，否则
/// 「优先有道」这条策略在新版就只剩从 URL 形状反推。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';

void main() {
  group('parsePronunciations 的 source', () {
    test('来源与音频地址都被解析出来', () {
      final items = parsePronunciations(
        '[{"accent":"US","phonetic":"ˈæpəl",'
        '"audioUrl":"https://dict.youdao.com/dictvoice?audio=apple&type=2",'
        '"source":"youdao"}]',
      );

      expect(items.single.source, 'youdao');
      expect(
        items.single.audioUrl,
        'https://dict.youdao.com/dictvoice?audio=apple&type=2',
      );
    });

    test('缺失来源时为 null 而不是猜一个', () {
      final items = parsePronunciations('[{"accent":"UK","phonetic":"ˈæpəl"}]');

      expect(items.single.source, isNull);
      expect(items.single.audioUrl, isNull);
    });

    test('空白来源归一为 null', () {
      final items = parsePronunciations(
        '[{"accent":"US","phonetic":"kæt","source":"   "}]',
      );

      expect(items.single.source, isNull);
    });
  });
}
