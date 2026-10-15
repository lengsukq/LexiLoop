/// 48 音标目录的完整性测试。
///
/// 目录是**静态教学资产**，最怕的是「悬空引用」与「漏字段」：
/// 旧版 `catalog.ts` 里 `confusable` 指向不存在的符号时，界面上表现为
/// 「点开易混对比却什么都没有」，而这类问题只会在用户正好练到那个音标时
/// 才暴露。这里把「48 条、字段非空、引用可解析」变成断言。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/phonetics/catalog.dart';

void main() {
  group('目录规模', () {
    test('恰好 48 个音标', () {
      expect(phonemeCatalog.length, phonemeCatalogSize);
      expect(phonemeCatalogSize, 48);
    });

    test('元音 20 个、辅音 28 个', () {
      final vowels = phonemeCatalog
          .where((entry) => entry.kind != PhonemeKind.consonant)
          .length;
      final consonants = phonemeCatalog
          .where((entry) => entry.kind == PhonemeKind.consonant)
          .length;
      expect(vowels, phonemeVowelCount);
      expect(consonants, phonemeConsonantCount);
    });

    test('符号唯一', () {
      final symbols = phonemeCatalog.map((entry) => entry.symbol).toList();
      expect(symbols.toSet().length, symbols.length);
    });

    test('每个分类都有音标', () {
      for (final category in PhonemeCategory.values) {
        expect(
          phonemesInCategory(category),
          isNotEmpty,
          reason: '${category.label} 分类为空',
        );
      }
    });

    test('易混对比组、美英差异、学习路径均已移植', () {
      expect(contrastGroups.length, 8);
      expect(accentDiffs.length, 9);
      expect(learningPath.length, 7);
      expect(learningPath.first.step, 1);
    });
  });

  group('条目字段', () {
    test('符号、中文名、发音要领、口型、典型坑都非空', () {
      for (final entry in phonemeCatalog) {
        expect(entry.symbol.trim(), isNotEmpty);
        expect(entry.nameZh.trim(), isNotEmpty, reason: entry.symbol);
        expect(entry.description.trim(), isNotEmpty, reason: entry.symbol);
        expect(entry.guide.what.trim(), isNotEmpty, reason: entry.symbol);
        expect(entry.guide.mouthShape.trim(), isNotEmpty, reason: entry.symbol);
        expect(
          entry.relations.pitfalls.trim(),
          isNotEmpty,
          reason: entry.symbol,
        );
      }
    });

    test('每个音标至少 1 个示例词，且示例词含词义与音标', () {
      for (final entry in phonemeCatalog) {
        expect(
          entry.examples.exampleWords,
          isNotEmpty,
          reason: '${entry.symbol} 没有示例词',
        );
        for (final example in entry.examples.exampleWords) {
          expect(example.word.trim(), isNotEmpty, reason: entry.symbol);
          expect(example.meaning.trim(), isNotEmpty, reason: entry.symbol);
          expect(example.phonetic.trim(), isNotEmpty, reason: entry.symbol);
        }
      }
    });

    test('每个音标至少 1 条发音技巧与 1 条拼写规律', () {
      for (final entry in phonemeCatalog) {
        expect(entry.guide.tips, isNotEmpty, reason: entry.symbol);
        expect(entry.examples.spellings, isNotEmpty, reason: entry.symbol);
      }
    });

    test('展示形式带斜杠', () {
      expect(phonemeBySymbol('iː')!.display, '/iː/');
      expect(phonemeBySymbol('tʃ')!.display, '/tʃ/');
    });
  });

  group('引用完整性', () {
    test('易混音标全部能在目录里找到（无悬空引用）', () {
      final symbols = <String>{
        for (final entry in phonemeCatalog) entry.symbol,
      };
      for (final entry in phonemeCatalog) {
        for (final other in entry.similarPhonemes) {
          expect(
            symbols,
            contains(other),
            reason: '${entry.symbol} 的易混音标 $other 不在目录中',
          );
        }
      }
    });

    test('confusablePhonemes 能解析出条目', () {
      final confusables = confusablePhonemes('iː');
      expect(confusables, isNotEmpty);
      expect(confusables.map((entry) => entry.symbol), contains('ɪ'));
      expect(confusablePhonemes('不存在的音标'), isEmpty);
    });

    test('对比组引用的符号都在目录中', () {
      final symbols = <String>{
        for (final entry in phonemeCatalog) entry.symbol,
      };
      for (final group in contrastGroups) {
        for (final symbol in group.body.symbols) {
          expect(
            symbols,
            contains(symbol),
            reason: '对比组 ${group.id} 引用了不存在的 $symbol',
          );
        }
        expect(group.body.pairs, isNotEmpty, reason: group.id);
        expect(group.keyTip.trim(), isNotEmpty, reason: group.id);
      }
    });
  });

  group('自检函数', () {
    test('validatePhonemeCatalog 返回空列表', () {
      expect(validatePhonemeCatalog(), isEmpty);
    });

    test('phonemeBySymbol 未知符号返回 null，且忽略首尾空白', () {
      expect(phonemeBySymbol('zzz'), isNull);
      expect(phonemeBySymbol('  iː  ')?.symbol, 'iː');
    });

    test('分类与清浊取值与旧版一致', () {
      final sheep = phonemeBySymbol('iː')!;
      expect(sheep.category, PhonemeCategory.vowelFront);
      expect(sheep.identity.voicing, PhonemeVoicing.vowel);
      expect(sheep.kind, PhonemeKind.vowel);
      final affricate = phonemeBySymbol('tʃ')!;
      expect(affricate.category, PhonemeCategory.affricate);
      expect(affricate.kind, PhonemeKind.consonant);
      expect(phonemeBySymbol('aɪ')!.kind, PhonemeKind.diphthong);
    });

    test('primaryExample 返回第一个示例词', () {
      expect(phonemeBySymbol('iː')!.primaryExample.word, 'see');
    });
  });
}
