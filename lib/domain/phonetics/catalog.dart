/// 48 音标静态目录（IPA 学习知识库）。
///
/// **逐条移植**旧版 `src/modules/phonetics/catalog.ts`（1310 行）：
/// 48 个音标条目、8 个易混对比组、9 条美英差异、7 步学习路径，
/// 以及每个音标的分类、清浊、发音要领、口型、技巧、拼写规律、
/// 示例词、中国学习者典型坑与易混符号。**内容一字未删**——
/// 这份目录是教学资产，改写措辞只会引入错误。
///
/// **为什么按「音标条目 / 易混组 / 美英差异」拆成值对象**：
/// 旧版的 `PhonemeEntry` 一个接口 14 个字段，构造处全靠位置与顺序阅读；
/// 拆成 [PhonemeIdentity] / [PhonemeGuide] / [PhonemeExamples] /
/// [PhonemeRelations] 四个语义分组后，每个构造函数都不超过 5 个参数
/// （架构守卫的硬约束），阅读时也不必在一屏里对照 14 个字段名。
///
/// **与旧版的差异（两处，均为修正）**：
/// 1. 旧版 `CATEGORY_META` 里的 `color` 是 Tailwind 类名
///    （`bg-[#5856d6]`），Flutter 侧改用 `LexiColors` 的语义色，
///    因此只保留分类的中英标签，不再搬运颜色字符串；
/// 2. 旧版 `/ŋ/` 的 `confusable` 含 `ŋk`——它不是音标符号而是拼写组合
///    （该条目 `spellings` 里已有 `nk → think /θɪŋk/`），会让「易混对比」
///    指向不存在的条目，本版移除。悬空引用由 [validatePhonemeCatalog]
///    与 `test/domain/phonetics/catalog_test.dart` 持续看守。
library;

import 'package:lexiloop/core/constants.dart';

/// 音标分类（对应旧版 `PhonemeCategory` 的 10 个取值）。
enum PhonemeCategory {
  /// 前元音。
  vowelFront('vowel-front', '前元音', 'Front'),

  /// 中元音。
  vowelCentral('vowel-central', '中元音', 'Central'),

  /// 后元音。
  vowelBack('vowel-back', '后元音', 'Back'),

  /// 双元音。
  diphthong('diphthong', '双元音', 'Diphthong'),

  /// 爆破音。
  plosive('plosive', '爆破音', 'Plosive'),

  /// 摩擦音。
  fricative('fricative', '摩擦音', 'Fricative'),

  /// 破擦音。
  affricate('affricate', '破擦音', 'Affricate'),

  /// 鼻音。
  nasal('nasal', '鼻音', 'Nasal'),

  /// 舌侧音。
  lateral('lateral', '舌侧音', 'Lateral'),

  /// 半元音 / 近音。
  approximant('approximant', '半元音/近音', 'Approximant');

  new(this.wire, this.label, this.labelEn);

  /// 稳定标识（与旧版字符串一致）。
  final String wire;

  /// 中文标签。
  final String label;

  /// 英文标签。
  final String labelEn;

  /// 该分类是否属于元音（单元音或双元音）。
  bool get isVowel =>
      this != PhonemeCategory.plosive &&
      this != PhonemeCategory.fricative &&
      this != PhonemeCategory.affricate &&
      this != PhonemeCategory.nasal &&
      this != PhonemeCategory.lateral &&
      this != PhonemeCategory.approximant;
}

/// 音标大类：元音 / 双元音 / 辅音。
///
/// 旧版没有这个枚举，界面靠 `category` 的字符串前缀判断；
/// 出题时只需要「元音还是辅音」这一层，单独成枚举后 switch 可穷尽。
enum PhonemeKind {
  /// 单元音。
  vowel('元音'),

  /// 双元音。
  diphthong('双元音'),

  /// 辅音。
  consonant('辅音');

  new(this.label);

  /// 中文标签。
  final String label;
}

/// 清浊（对应旧版 `Voicing`）。
enum PhonemeVoicing {
  /// 浊音。
  voiced('voiced', '浊音'),

  /// 清音。
  voiceless('voiceless', '清音'),

  /// 元音（无所谓清浊）。
  vowel('vowel', '元音');

  new(this.wire, this.label);

  /// 稳定标识。
  final String wire;

  /// 中文标签。
  final String label;
}

/// 一个音标的身份与分类。
class PhonemeIdentity {
  /// 以各字段构造。
  const new({
    required this.symbol,
    required this.nameZh,
    required this.category,
    required this.groupLabel,
    required this.voicing,
  });

  /// 音标符号（不含斜杠，如 `iː`）。
  final String symbol;

  /// 中文名称（如「长衣音」）。
  final String nameZh;

  /// 分类。
  final PhonemeCategory category;

  /// 分组标签（如「单元音 · 前元音」）。
  final String groupLabel;

  /// 清浊。
  final PhonemeVoicing voicing;
}

/// 一个音标的发音要领。
class PhonemeGuide {
  /// 以各字段构造。
  const new({
    required this.what,
    required this.articulation,
    required this.mouthShape,
    required this.tips,
  });

  /// 一句话定义：这个音是什么。
  final String what;

  /// 发音要领：舌、唇、口、声带怎么动。
  final String articulation;

  /// 口型描述。
  final String mouthShape;

  /// 练习技巧。
  final List<String> tips;
}

/// 一条拼写规律。
class SpellingPattern {
  /// 以各字段构造。
  const new({required this.pattern, required this.example, this.note});

  /// 拼写模式。
  final String pattern;

  /// 例词（含音标）。
  final String example;

  /// 备注。
  final String? note;
}

/// 一个发音示例词。
class PhonemeExample {
  /// 以各字段构造。
  const new({
    required this.word,
    required this.phonetic,
    required this.meaning,
  });

  /// 示例词。
  final String word;

  /// 该词的音标（含斜杠）。
  final String phonetic;

  /// 中文词义。
  final String meaning;
}

/// 一个音标的拼写规律与示例词。
class PhonemeExamples {
  /// 以各字段构造。
  const new({required this.spellings, required this.exampleWords});

  /// 拼写规律。
  final List<SpellingPattern> spellings;

  /// 示例词。
  final List<PhonemeExample> exampleWords;
}

/// 一个音标的易混关系与口音备注。
class PhonemeRelations {
  /// 以各字段构造。
  const new({
    required this.pitfalls,
    required this.confusable,
    this.accentNote,
  });

  /// 中国学习者典型坑。
  final String pitfalls;

  /// 易混符号。
  final List<String> confusable;

  /// 美英差异备注。
  final String? accentNote;
}

/// 一个音标条目。
class PhonemeEntry {
  /// 以各字段构造。
  const new({
    required this.identity,
    required this.guide,
    required this.examples,
    required this.relations,
  });

  /// 身份与分类。
  final PhonemeIdentity identity;

  /// 发音要领。
  final PhonemeGuide guide;

  /// 拼写规律与示例词。
  final PhonemeExamples examples;

  /// 易混关系与口音备注。
  final PhonemeRelations relations;

  /// 音标符号。
  String get symbol => identity.symbol;

  /// 中文名称。
  String get nameZh => identity.nameZh;

  /// 分类。
  PhonemeCategory get category => identity.category;

  /// 音标大类（元音 / 双元音 / 辅音）。
  PhonemeKind get kind => switch (identity.category) {
    PhonemeCategory.diphthong => PhonemeKind.diphthong,
    PhonemeCategory.plosive ||
    PhonemeCategory.fricative ||
    PhonemeCategory.affricate ||
    PhonemeCategory.nasal ||
    PhonemeCategory.lateral ||
    PhonemeCategory.approximant => PhonemeKind.consonant,
    _ => PhonemeKind.vowel,
  };

  /// 中文发音要领（对应旧版 `articulation`）。
  String get description => guide.articulation;

  /// 易混音标（对应旧版 `confusable`）。
  List<String> get similarPhonemes => relations.confusable;

  /// 带斜杠的展示形式（如 `/iː/`）。
  String get display => '/$symbol/';

  /// 第一个示例词；目录保证每个音标至少有一个示例词。
  PhonemeExample get primaryExample => examples.exampleWords.first;
}

/// 一组最小对立词对。
class MinimalPair {
  /// 以各字段构造。
  const new({
    required this.left,
    required this.right,
    required this.leftPhonetic,
    required this.rightPhonetic,
    required this.meanings,
  });

  /// 左侧词。
  final String left;

  /// 右侧词。
  final String right;

  /// 左侧音标。
  final String leftPhonetic;

  /// 右侧音标。
  final String rightPhonetic;

  /// 两侧词义。
  final MinimalPairMeanings meanings;
}

/// 最小对立词对的两侧词义。
class MinimalPairMeanings {
  /// 以各字段构造。
  const new({required this.left, required this.right});

  /// 左侧词义。
  final String left;

  /// 右侧词义。
  final String right;
}

/// 易混对比组的内容。
class ContrastGroupBody {
  /// 以各字段构造。
  const new({
    required this.description,
    required this.symbols,
    required this.pairs,
  });

  /// 对比说明。
  final String description;

  /// 参与对比的音标符号。
  final List<String> symbols;

  /// 最小对立词对。
  final List<MinimalPair> pairs;
}

/// 一个易混对比组。
class ContrastGroup {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.body,
    required this.keyTip,
  });

  /// 稳定标识。
  final String id;

  /// 中文标题。
  final String title;

  /// 英文标题（音标形式）。
  final String titleEn;

  /// 组内容。
  final ContrastGroupBody body;

  /// 关键提示。
  final String keyTip;
}

/// 美英差异的两侧音标。
class AccentSamples {
  /// 以各字段构造。
  const new({required this.uk, required this.us});

  /// 英式音标。
  final String uk;

  /// 美式音标。
  final String us;
}

/// 一条美英差异。
class AccentDiff {
  /// 以各字段构造。
  const new({
    required this.symbol,
    required this.samples,
    required this.word,
    required this.description,
    required this.note,
  });

  /// 差异涉及的符号（可能含 `→`）。
  final String symbol;

  /// 两侧音标。
  final AccentSamples samples;

  /// 例词。
  final String word;

  /// 差异说明。
  final String description;

  /// 备注。
  final String note;
}

/// 学习路径的一步。
class LearningStep {
  /// 以各字段构造。
  const new({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.points,
  });

  /// 步骤序号。
  final int step;

  /// 标题。
  final String title;

  /// 英文副标题。
  final String subtitle;

  /// 要点。
  final List<String> points;
}

/// 48 音标目录（逐条对应旧版 `modules/phonetics/catalog.ts` 的 `PHONEMES`）。
///
/// 顺序沿用旧版：单元音（前 / 中 / 后）→ 双元音 → 爆破音 → 摩擦音 →
/// 破擦音 → 鼻音 → 舌侧音 → 半元音 / 近音，最后是 4 个中国学习者
/// 常见的破擦音组合（`tr` / `dr` / `ts` / `dz`）。
const List<PhonemeEntry> phonemeCatalog = <PhonemeEntry>[
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'iː',
      nameZh: '长衣音',
      category: PhonemeCategory.vowelFront,
      groupLabel: '单元音 · 前元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '前元音里最紧、嘴角最咧的长元音，中文没有对应，/ɪ/ 是它的松短版。',
      articulation: '舌尖抵下齿，舌前部高高抬向硬腭，嘴角向两边咧开，声带振动，气流自由通过。',
      mouthShape: '微笑状，上下齿接近、嘴唇扁平，舌身紧张。',
      tips: <String>[
        '不要发成中文 yi，要保持舌面紧张',
        '时长是 /ɪ/ 的 1.5-2 倍，刻意拉长就对',
        '收尾保持嘴角咧开不松',
      ],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ee', example: 'see /siː/', note: '最常见'),
        SpellingPattern(pattern: 'ea', example: 'sea /siː/'),
        SpellingPattern(pattern: 'e + 辅音 + e', example: 'these /ðiːz/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'see', phonetic: '/siː/', meaning: '看见'),
        PhonemeExample(word: 'beat', phonetic: '/biːt/', meaning: '打、节拍'),
        PhonemeExample(word: 'sheep', phonetic: '/ʃiːp/', meaning: '绵羊'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '中国学习者常把 ship /ʃɪp/ 念成 sheep /ʃiːp/，长短不分会直接变词。',
      confusable: <String>['ɪ'],
      accentNote: '美英一致。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɪ',
      nameZh: '短衣音',
      category: PhonemeCategory.vowelFront,
      groupLabel: '单元音 · 前元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '/iː/ 的松短版，短促放松，舌位稍低、肌肉不紧张。',
      articulation: '舌前部稍抬但不顶腭，嘴角略咧但不紧张，短促一带而过。',
      mouthShape: '比 /iː/ 口型略开、肌肉放松，发音短促。',
      tips: <String>['不要刻意拉长，点到为止', '和中文衣的短促感接近，但更放松'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'i', example: 'sit /sɪt/'),
        SpellingPattern(pattern: 'y', example: 'myth /mɪθ/'),
        SpellingPattern(pattern: 'e', example: 'pretty /ˈprɪti/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'sit', phonetic: '/sɪt/', meaning: '坐'),
        PhonemeExample(word: 'ship', phonetic: '/ʃɪp/', meaning: '船'),
        PhonemeExample(word: 'bit', phonetic: '/bɪt/', meaning: '一点'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '最常被拉长成 /iː/，记住 bit vs beat 是一组最小对立。',
      confusable: <String>['iː', 'e'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'e',
      nameZh: '短欸音',
      category: PhonemeCategory.vowelFront,
      groupLabel: '单元音 · 前元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '半开口前元音，介于 /ɪ/ 和 /æ/ 之间，中文没有，开口比欸稍大。',
      articulation: '舌前部中高，舌尖抵下齿，口半开，声带振动。',
      mouthShape: '口自然张开约一指宽，嘴角稍咧。',
      tips: <String>['不要发成中文欸(ei)的滑音', '保持单音色，不往 /ɪ/ 滑'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'e', example: 'bed /bed/'),
        SpellingPattern(pattern: 'ea', example: 'head /hed/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'bed', phonetic: '/bed/', meaning: '床'),
        PhonemeExample(word: 'pen', phonetic: '/pen/', meaning: '笔'),
        PhonemeExample(word: 'head', phonetic: '/hed/', meaning: '头'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '容易与 /æ/ 混：bed /bed/ vs bad /bæd/ 必须靠开口大小区分。',
      confusable: <String>['æ', 'ɪ'],
      accentNote: '教材常写作 /e/ 或 /ɛ/，美音偏 /ɛ/，英音偏 /e/，听感接近。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'æ',
      nameZh: '短啊音',
      category: PhonemeCategory.vowelFront,
      groupLabel: '单元音 · 前元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '前元音里开口最大的一个，比 /e/ 更张、更亮。',
      articulation: '舌前部低，舌尖抵下齿，下颌明显下降，声带振动。',
      mouthShape: '张大嘴，下颌下拉，像说啊但舌位更前。',
      tips: <String>['刻意张大，下巴掉下来就对了', '不要发成 /e/，/æ/ 更夸张', '美音里这个音比英音更夸张'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'a', example: 'cat /kæt/'),
        SpellingPattern(pattern: 'al', example: 'halve /hæv/  (美)'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'cat', phonetic: '/kæt/', meaning: '猫'),
        PhonemeExample(word: 'man', phonetic: '/mæn/', meaning: '男人'),
        PhonemeExample(word: 'bad', phonetic: '/bæd/', meaning: '坏的'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '中文没有，很多人发成 /e/，cat 念成 ket，老外会听成另一个词。',
      confusable: <String>['e', 'ɑː', 'ʌ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɜː',
      nameZh: '长呃音',
      category: PhonemeCategory.vowelCentral,
      groupLabel: '单元音 · 中元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '中元音最紧张的长音，英音卷舌不明显，美音带明显 r 卷舌 /ɝː/。',
      articulation: '舌中部抬起，舌尖不卷(英)或轻卷(美)，口半合，双唇平展。',
      mouthShape: '口半开，唇平，不圆，英音不卷舌、美音轻卷。',
      tips: <String>['英音 bird /bɜːd/ 不卷舌，美音 /bɝːd/ 卷舌', '不要发成 /ə/，/ɜː/ 更长更重'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ir', example: 'bird /bɜːd/'),
        SpellingPattern(pattern: 'ur', example: 'burn /bɜːn/'),
        SpellingPattern(pattern: 'or', example: 'word /wɜːd/'),
        SpellingPattern(pattern: 'er', example: 'her /hɜː/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(
          word: 'bird',
          phonetic: '/bɜːd/ (美 /bɝːd/)',
          meaning: '鸟',
        ),
        PhonemeExample(word: 'nurse', phonetic: '/nɜːs/', meaning: '护士'),
        PhonemeExample(word: 'learn', phonetic: '/lɜːn/', meaning: '学习'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '中文 er 音过重，英音要克制不卷，美音则要卷，这是美英最明显分野之一。',
      confusable: <String>['ə'],
      accentNote: '英 /ɜː/ = 美 /ɝː/，美音带 r。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ə',
      nameZh: '弱读央元音',
      category: PhonemeCategory.vowelCentral,
      groupLabel: '单元音 · 中元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '英语最常用、却最松最弱的元音，只出现在非重读音节。',
      articulation: '舌中部平放，口半开，唇完全放松，短促模糊。',
      mouthShape: '完全放松，嘴几乎不动，轻轻带过。',
      tips: <String>['这是弱读的灵魂，不要用力', 'about /əˈbaʊt/ 的第一个音就是它，轻轻一带'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'a', example: 'about /əˈbaʊt/'),
        SpellingPattern(pattern: 'e', example: 'taken /ˈteɪkən/'),
        SpellingPattern(pattern: 'o', example: 'lemon /ˈlemən/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'about', phonetic: '/əˈbaʊt/', meaning: '关于'),
        PhonemeExample(word: 'sofa', phonetic: '/ˈsəʊfə/', meaning: '沙发'),
        PhonemeExample(
          word: 'teacher',
          phonetic: '/ˈtiːtʃə/ (美 /-tʃər/)',
          meaning: '老师',
        ),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '中文学习者总想把每个音节读清楚，但 /ə/ 就是要含糊弱读，越用力越错。',
      confusable: <String>['ɜː', 'ʌ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ʌ',
      nameZh: '短阿音',
      category: PhonemeCategory.vowelCentral,
      groupLabel: '单元音 · 中元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '中元音的短音，比 /ɑː/ 短促、开口更小，和 /æ/ 易混但舌位更靠后。',
      articulation: '舌中部稍抬，口半开，唇平，下颌稍降。',
      mouthShape: '口张开度在 /æ/ 和 /ɑː/ 之间，短促。',
      tips: <String>['不要发成中文阿，/ʌ/ 更短更含糊', 'cup /kʌp/ 不要拖长'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'u', example: 'cup /kʌp/'),
        SpellingPattern(pattern: 'o', example: 'love /lʌv/'),
        SpellingPattern(pattern: 'ou', example: 'touch /tʌtʃ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'cup', phonetic: '/kʌp/', meaning: '杯子'),
        PhonemeExample(word: 'luck', phonetic: '/lʌk/', meaning: '运气'),
        PhonemeExample(word: 'blood', phonetic: '/blʌd/', meaning: '血'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '易与 /æ/、/ɑː/ 混：cup /kʌp/ vs cap /kæp/ vs carp /kɑːp/ 三组要分开练。',
      confusable: <String>['æ', 'ɑː', 'ə'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɑː',
      nameZh: '长啊音',
      category: PhonemeCategory.vowelBack,
      groupLabel: '单元音 · 后元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '后元音开口最大的长音，英音标志，美音多与 /ɒ/ 合并为 /ɑ/。',
      articulation: '舌后部低平，口大开，下颌下降，双唇不圆。',
      mouthShape: '张大嘴，舌后部下沉，像看医生张嘴。',
      tips: <String>[
        '英音 car /kɑː/ 要拉长，美音 /kɑr/ 带 r 且稍短',
        '不要发成 /ʌ/，/ɑː/ 开口更大、时长更长',
      ],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ar', example: 'car /kɑː/'),
        SpellingPattern(pattern: 'a', example: 'fast /fɑːst/ (英)'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'car', phonetic: '/kɑː/ (美 /kɑr/)', meaning: '汽车'),
        PhonemeExample(word: 'start', phonetic: '/stɑːt/', meaning: '开始'),
        PhonemeExample(word: 'father', phonetic: '/ˈfɑːðə/', meaning: '父亲'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '美音不区分 /ɒ/，hot 和 father 同元音，英音则分开，这是听力大坑。',
      confusable: <String>['ʌ', 'ɒ'],
      accentNote: '英 /ɑː/ vs 美 /ɑ/，长度和 r 有别。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɒ',
      nameZh: '短奥音',
      category: PhonemeCategory.vowelBack,
      groupLabel: '单元音 · 后元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '后元音短促圆唇版，英音专属，美音并入 /ɑ/。',
      articulation: '舌后部稍抬，口半开，双唇稍圆，短促。',
      mouthShape: '口半开，唇略圆，下颌不下拉太狠。',
      tips: <String>['只在英音里练，美音直接按 /ɑ/ 学', 'hot /hɒt/ (英) vs /hɑt/ (美) 对比听'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'o', example: 'hot /hɒt/ (英)'),
        SpellingPattern(pattern: 'a', example: 'want /wɒnt/ (英)'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'hot', phonetic: '/hɒt/ (美 /hɑt/)', meaning: '热的'),
        PhonemeExample(
          word: 'box',
          phonetic: '/bɒks/ (美 /bɑks/)',
          meaning: '盒子',
        ),
        PhonemeExample(word: 'got', phonetic: '/ɡɒt/', meaning: '得到'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '学美音可忽略，学英音必须与 /ɔː/ 分开：hot /hɒt/ vs caught /kɔːt/。',
      confusable: <String>['ɔː', 'ɑː'],
      accentNote: '英 /ɒ/ 在美音中多为 /ɑ/。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɔː',
      nameZh: '长奥音',
      category: PhonemeCategory.vowelBack,
      groupLabel: '单元音 · 后元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '后元音圆唇长音，口型圆而紧。',
      articulation: '舌后部中高，双唇收圆并突出，时长明显。',
      mouthShape: '圆唇、噘嘴，口型比 /ɒ/ 更收紧、更长。',
      tips: <String>['发音时用力噘嘴，照镜子看唇形', '不要滑向双元音，保持纯元音'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'or', example: 'four /fɔː/'),
        SpellingPattern(pattern: 'al', example: 'call /kɔːl/'),
        SpellingPattern(pattern: 'au', example: 'law /lɔː/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'law', phonetic: '/lɔː/', meaning: '法律'),
        PhonemeExample(
          word: 'more',
          phonetic: '/mɔː/ (美 /mɔr/)',
          meaning: '更多',
        ),
        PhonemeExample(word: 'thought', phonetic: '/θɔːt/', meaning: '想法'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '美音 non-rhotic 地区也分，但口音弱化时易与 /ɑ/ 混。',
      confusable: <String>['ɒ', 'əʊ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ʊ',
      nameZh: '短乌音',
      category: PhonemeCategory.vowelBack,
      groupLabel: '单元音 · 后元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '/uː/ 的松短版，短促圆唇但不紧。',
      articulation: '舌后部稍高，唇轻圆，肌肉放松，短促。',
      mouthShape: '轻度圆唇，比 /uː/ 更松、开口稍大。',
      tips: <String>['put /pʊt/ 短促，boot /buːt/ 拉长', '不要发成中文乌，/ʊ/ 更松'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'oo', example: 'look /lʊk/'),
        SpellingPattern(pattern: 'u', example: 'put /pʊt/'),
        SpellingPattern(pattern: 'ou', example: 'would /wʊd/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'put', phonetic: '/pʊt/', meaning: '放'),
        PhonemeExample(word: 'look', phonetic: '/lʊk/', meaning: '看'),
        PhonemeExample(word: 'good', phonetic: '/ɡʊd/', meaning: '好的'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /uː/ 混淆重灾：look vs Luke。',
      confusable: <String>['uː'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'uː',
      nameZh: '长乌音',
      category: PhonemeCategory.vowelBack,
      groupLabel: '单元音 · 后元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '后元音最高、最圆、最紧的长音。',
      articulation: '舌后部高抬贴近软腭，双唇紧圆前突，气流长而稳。',
      mouthShape: '用力噘嘴，唇形小圆，像吹口哨。',
      tips: <String>['刻意噘嘴、拉长', '不要在尾巴加 /w/ 滑音'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'oo', example: 'food /fuːd/'),
        SpellingPattern(pattern: 'ue', example: 'blue /bluː/'),
        SpellingPattern(pattern: 'ew', example: 'chew /tʃuː/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'food', phonetic: '/fuːd/', meaning: '食物'),
        PhonemeExample(word: 'school', phonetic: '/skuːl/', meaning: '学校'),
        PhonemeExample(word: 'true', phonetic: '/truː/', meaning: '真的'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /ʊ/ 最小对立必须分清。',
      confusable: <String>['ʊ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'eɪ',
      nameZh: '欸衣滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /e/ 滑向 /ɪ/，重心在前、轻收于 /ɪ/。',
      articulation: '起点 /e/，舌前部中高，滑向 /ɪ/ 时舌略抬、口略合。',
      mouthShape: '口先半开再略合，嘴角从开展到收。',
      tips: <String>['不要发成中文欸的纯单元音，要有滑动', '收尾轻，不重读 /ɪ/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'a + e', example: 'name /neɪm/'),
        SpellingPattern(pattern: 'ai', example: 'rain /reɪn/'),
        SpellingPattern(pattern: 'ay', example: 'day /deɪ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'face', phonetic: '/feɪs/', meaning: '脸'),
        PhonemeExample(word: 'make', phonetic: '/meɪk/', meaning: '制作'),
        PhonemeExample(word: 'great', phonetic: '/ɡreɪt/', meaning: '伟大的'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '发得不够滑会被听成 /e/，过度滑会像 /aɪ/。',
      confusable: <String>['aɪ', 'e', 'ɪə'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'aɪ',
      nameZh: '啊衣滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /a/ 滑向 /ɪ/，开口大、动程大。',
      articulation: '起点接近 /æ/ 与 /ɑ/ 之间，张大口，滑向 /ɪ/ 时快速收口。',
      mouthShape: '大开口起，重心在前，收尾点到为止。',
      tips: <String>['起点要张大，否则像 /eɪ/', 'my /maɪ/、time /taɪm/ 都是它'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'i + e', example: 'time /taɪm/'),
        SpellingPattern(pattern: 'y', example: 'my /maɪ/'),
        SpellingPattern(pattern: 'igh', example: 'high /haɪ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'time', phonetic: '/taɪm/', meaning: '时间'),
        PhonemeExample(word: 'like', phonetic: '/laɪk/', meaning: '喜欢'),
        PhonemeExample(word: 'my', phonetic: '/maɪ/', meaning: '我的'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '起点不开会被听成 /eɪ/。',
      confusable: <String>['eɪ', 'aʊ', 'ɔɪ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɔɪ',
      nameZh: '奥衣滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /ɔ/ 滑向 /ɪ/，先圆唇后展唇。',
      articulation: '起点圆唇 /ɔ/，滑向展唇 /ɪ/。',
      mouthShape: '先噘嘴再咧嘴，动程明显。',
      tips: <String>['boy /bɔɪ/ 先奥后衣，连起来要快'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'oi', example: 'choice /tʃɔɪs/'),
        SpellingPattern(pattern: 'oy', example: 'boy /bɔɪ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'boy', phonetic: '/bɔɪ/', meaning: '男孩'),
        PhonemeExample(word: 'voice', phonetic: '/vɔɪs/', meaning: '声音'),
        PhonemeExample(word: 'enjoy', phonetic: '/ɪnˈdʒɔɪ/', meaning: '享受'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '不要读成中文帷，起点要圆。',
      confusable: <String>['aɪ', 'əʊ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'aʊ',
      nameZh: '啊乌滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /a/ 滑向 /ʊ/，开口大、收口圆。',
      articulation: '起点张大，滑向 /ʊ/ 时双唇收圆。',
      mouthShape: '大开口起，收尾噘嘴。',
      tips: <String>['now /naʊ/、how /haʊ/ 都是它', '收尾不要太重'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ou', example: 'house /haʊs/'),
        SpellingPattern(pattern: 'ow', example: 'now /naʊ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'house', phonetic: '/haʊs/', meaning: '房子'),
        PhonemeExample(word: 'now', phonetic: '/naʊ/', meaning: '现在'),
        PhonemeExample(word: 'about', phonetic: '/əˈbaʊt/', meaning: '关于'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /əʊ/ 混：how /haʊ/ vs hoe /həʊ/。',
      confusable: <String>['əʊ', 'aɪ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'əʊ',
      nameZh: '呃乌滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /ə/ 滑向 /ʊ/，英式 /əʊ/，美式 /oʊ/ 起点更靠后更圆。',
      articulation: '起点中元音，滑向圆唇 /ʊ/，唇从平到圆。',
      mouthShape: '先平后圆，轻轻滑。',
      tips: <String>['英 go /ɡəʊ/，美 /ɡoʊ/ 圆一点', '是英美口音试金石之一'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'o + e', example: 'go /ɡəʊ/'),
        SpellingPattern(pattern: 'oa', example: 'boat /bəʊt/'),
        SpellingPattern(pattern: 'ow', example: 'know /nəʊ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'go', phonetic: '/ɡəʊ/ (美 /ɡoʊ/)', meaning: '去'),
        PhonemeExample(word: 'home', phonetic: '/həʊm/', meaning: '家'),
        PhonemeExample(word: 'show', phonetic: '/ʃəʊ/', meaning: '展示'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '中文没有，发成纯 /o/ 会很中式，要滑。',
      confusable: <String>['ɔː', 'aʊ', 'ʌ'],
      accentNote: '英 /əʊ/ = 美 /oʊ/，起点不同。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɪə',
      nameZh: '衣呃滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /ɪ/ 滑向 /ə/，英音双元音，美音多为 /ɪr/。',
      articulation: '起点 /ɪ/，向中央 /ə/ 滑，重心在前。',
      mouthShape: '先咧后平，轻滑。',
      tips: <String>['英 near /nɪə/，美 /nɪr/ 带卷舌', '学英音才重练，美音可淡化'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ear', example: 'near /nɪə/'),
        SpellingPattern(pattern: 'ere', example: 'here /hɪə/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(
          word: 'near',
          phonetic: '/nɪə/ (美 /nɪr/)',
          meaning: '近的',
        ),
        PhonemeExample(word: 'idea', phonetic: '/aɪˈdɪə/', meaning: '主意'),
        PhonemeExample(word: 'beer', phonetic: '/bɪə/', meaning: '啤酒'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '美音学习者不必纠结，按 /ɪr/ 即可。',
      confusable: <String>['eə', 'ʊə'],
      accentNote: '英三元音，美简化为 r 音。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'eə',
      nameZh: '欸呃滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /e/ 滑向 /ə/，英音，美音为 /er/。',
      articulation: '起点 /e/，向 /ə/ 滑。',
      mouthShape: '先半开再放松。',
      tips: <String>['英 square /skweə/，美 /skwer/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'are', example: 'square /skweə/'),
        SpellingPattern(pattern: 'air', example: 'air /eə/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(
          word: 'square',
          phonetic: '/skweə/ (美 /skwer/)',
          meaning: '广场',
        ),
        PhonemeExample(word: 'care', phonetic: '/keə/', meaning: '关心'),
        PhonemeExample(word: 'where', phonetic: '/weə/', meaning: '哪里'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '同上，美音按 r 音处理。',
      confusable: <String>['ɪə', 'ɜː'],
      accentNote: '英 /eə/ = 美 /er/。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ʊə',
      nameZh: '乌呃滑音',
      category: PhonemeCategory.diphthong,
      groupLabel: '双元音',
      voicing: PhonemeVoicing.vowel,
    ),
    guide: PhonemeGuide(
      what: '从 /ʊ/ 滑向 /ə/，英音，美音几乎消失，多读 /ʊr/。',
      articulation: '起点圆唇 /ʊ/，向 /ə/ 滑。',
      mouthShape: '先圆后平。',
      tips: <String>['英 cure /kjʊə/，美 /kjʊr/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ure', example: 'cure /kjʊə/'),
        SpellingPattern(pattern: 'oor', example: 'poor /pʊə/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'cure', phonetic: '/kjʊə/', meaning: '治愈'),
        PhonemeExample(word: 'tour', phonetic: '/tʊə/', meaning: '旅行'),
        PhonemeExample(word: 'sure', phonetic: '/ʃʊə/', meaning: '确定的'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '使用频率低，英音精进再练。',
      confusable: <String>['ɔː', 'ɪə'],
      accentNote: '英保留，美多简化。',
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'p',
      nameZh: '泼',
      category: PhonemeCategory.plosive,
      groupLabel: '爆破音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '清爆破音，/b/ 的清音版，送气强。',
      articulation: '双唇紧闭，气流在口腔积聚，突然爆开，声带不振动。',
      mouthShape: '双唇闭合后爆开，像轻咳。',
      tips: <String>['纸巾测试：发 /p/ 时纸巾会动，/b/ 不会', 'pin /pɪn/ vs bin /bɪn/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'p', example: 'pen /pen/'),
        SpellingPattern(pattern: 'pp', example: 'happy /ˈhæpi/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'pen', phonetic: '/pen/', meaning: '笔'),
        PhonemeExample(word: 'open', phonetic: '/ˈəʊpən/', meaning: '打开'),
        PhonemeExample(word: 'cup', phonetic: '/kʌp/', meaning: '杯子'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾 /p/ 不要加元音，cup 不是咖剖。',
      confusable: <String>['b'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'b',
      nameZh: '拨',
      category: PhonemeCategory.plosive,
      groupLabel: '爆破音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '浊爆破音，声带振动，不送气或弱送气。',
      articulation: '同 /p/ 的口型，但声带振动，气流弱。',
      mouthShape: '双唇爆开，带声。',
      tips: <String>['手按喉咙，发 /b/ 会震手', '与 /p/ 最小对立多练'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'b', example: 'book /bʊk/'),
        SpellingPattern(pattern: 'bb', example: 'rabbit /ˈræbɪt/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'book', phonetic: '/bʊk/', meaning: '书'),
        PhonemeExample(word: 'cab', phonetic: '/kæb/', meaning: '出租车'),
        PhonemeExample(word: 'number', phonetic: '/ˈnʌmbə/', meaning: '数字'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾浊音不要清化，cab 的 /b/ 要震动。',
      confusable: <String>['p', 'v'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 't',
      nameZh: '特',
      category: PhonemeCategory.plosive,
      groupLabel: '爆破音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '清爆破，舌尖顶上齿龈，送气。',
      articulation: '舌尖抵上齿龈，堵塞气流后爆开，声带不振动。',
      mouthShape: '舌尖顶住上牙龈后弹开。',
      tips: <String>[
        '美音中 water /ˈwɔːtə/ 的 /t/ 常闪音成 /ɾ/，像轻 /d/',
        'ten /ten/ 送气，pen 的 /p/ 同理',
      ],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 't', example: 'time /taɪm/'),
        SpellingPattern(pattern: 'tt', example: 'letter /ˈletə/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'time', phonetic: '/taɪm/', meaning: '时间'),
        PhonemeExample(
          word: 'water',
          phonetic: '/ˈwɔːtə/ (美 /ˈwɑːtər/)',
          meaning: '水',
        ),
        PhonemeExample(word: 'cat', phonetic: '/kæt/', meaning: '猫'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '美音闪音别误以为是 /d/，是 /t/ 的变体。',
      confusable: <String>['d', 'θ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'd',
      nameZh: '得',
      category: PhonemeCategory.plosive,
      groupLabel: '爆破音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '浊爆破，/t/ 的浊音版。',
      articulation: '同 /t/ 口型，声带振动，弱送气。',
      mouthShape: '舌尖爆开，带声。',
      tips: <String>['喉咙震动即对'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'd', example: 'dog /dɒɡ/'),
        SpellingPattern(pattern: 'dd', example: 'middle /ˈmɪdl/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'dog', phonetic: '/dɒɡ/', meaning: '狗'),
        PhonemeExample(word: 'day', phonetic: '/deɪ/', meaning: '天'),
        PhonemeExample(word: 'road', phonetic: '/rəʊd/', meaning: '路'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾 /d/ 不要吞掉，good /ɡʊd/ 的 /d/ 要轻触。',
      confusable: <String>['t', 'ð'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'k',
      nameZh: '克',
      category: PhonemeCategory.plosive,
      groupLabel: '爆破音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '清爆破，后舌抵软腭，送气。',
      articulation: '舌后部抬起抵软腭，堵塞后爆开，声带不振动。',
      mouthShape: '舌根用力后爆。',
      tips: <String>['key /kiː/、cat /kæt/ 都是它', '词尾 /k/ 不要加呃'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'k', example: 'key /kiː/'),
        SpellingPattern(pattern: 'c', example: 'cat /kæt/'),
        SpellingPattern(pattern: 'ck', example: 'back /bæk/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'key', phonetic: '/kiː/', meaning: '钥匙'),
        PhonemeExample(word: 'school', phonetic: '/skuːl/', meaning: '学校'),
        PhonemeExample(word: 'book', phonetic: '/bʊk/', meaning: '书'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与中文 k 接近但更送气，纸巾会动。',
      confusable: <String>['ɡ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ɡ',
      nameZh: '哥',
      category: PhonemeCategory.plosive,
      groupLabel: '爆破音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '浊爆破，/k/ 的浊音版。',
      articulation: '同 /k/，声带振动。',
      mouthShape: '舌根爆开带声。',
      tips: <String>['go /ɡəʊ/、get /ɡet/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'g', example: 'go /ɡəʊ/'),
        SpellingPattern(pattern: 'gg', example: 'egg /eɡ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'go', phonetic: '/ɡəʊ/', meaning: '去'),
        PhonemeExample(word: 'big', phonetic: '/bɪɡ/', meaning: '大的'),
        PhonemeExample(word: 'get', phonetic: '/ɡet/', meaning: '得到'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾不要清化，big /bɪɡ/ 的 /ɡ/ 要震动。',
      confusable: <String>['k'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'f',
      nameZh: '夫',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '清摩擦，上齿轻触下唇，气流从缝隙挤出。',
      articulation: '上齿轻触下唇内侧，气流摩擦而出，声带不振动。',
      mouthShape: '轻咬下唇，吹气。',
      tips: <String>['不要用 /h/ 代替，上齿必须碰唇', 'five /faɪv/ 起点就是它'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'f', example: 'five /faɪv/'),
        SpellingPattern(pattern: 'ph', example: 'phone /fəʊn/'),
        SpellingPattern(pattern: 'gh', example: 'enough /ɪˈnʌf/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'five', phonetic: '/faɪv/', meaning: '五'),
        PhonemeExample(word: 'phone', phonetic: '/fəʊn/', meaning: '电话'),
        PhonemeExample(word: 'leaf', phonetic: '/liːf/', meaning: '叶子'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '中国学习者常把 very /ˈveri/ 读成 /ˈferi/，清浊要分。',
      confusable: <String>['v', 'h'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'v',
      nameZh: '吾夫',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '/f/ 的浊音版，声带振动是唯一区别。',
      articulation: '口型同 /f/，声带振动。',
      mouthShape: '轻咬下唇，喉咙震动。',
      tips: <String>['手摸喉咙，/v/ 震、/f/ 不震', 'very /ˈveri/ 不要读成 /weli/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'v', example: 'very /ˈveri/'),
        SpellingPattern(pattern: 've', example: 'have /hæv/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'very', phonetic: '/ˈveri/', meaning: '非常'),
        PhonemeExample(word: 'voice', phonetic: '/vɔɪs/', meaning: '声音'),
        PhonemeExample(word: 'love', phonetic: '/lʌv/', meaning: '爱'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /w/ 混淆重灾：very /ˈveri/ vs wary /ˈweəri/。',
      confusable: <String>['f', 'w'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'θ',
      nameZh: '咬舌清擦',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '咬舌清音，舌尖轻伸于上下齿间，气流摩擦。',
      articulation: '舌尖轻伸出上下齿间，气流从舌齿缝挤出，声带不振动。',
      mouthShape: '舌尖伸出，轻吹气。',
      tips: <String>['必须伸舌，不伸就是 /s/', 'think /θɪŋk/ 舌尖要看得见'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'th', example: 'think /θɪŋk/'),
        SpellingPattern(pattern: 'th', example: 'thank /θæŋk/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'think', phonetic: '/θɪŋk/', meaning: '想'),
        PhonemeExample(word: 'thank', phonetic: '/θæŋk/', meaning: '谢谢'),
        PhonemeExample(word: 'month', phonetic: '/mʌnθ/', meaning: '月'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '最易被读成 /s/：think 读成 sink 会变词。',
      confusable: <String>['ð', 's'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ð',
      nameZh: '咬舌浊擦',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '/θ/ 的浊音版，声带振动，常见于虚词。',
      articulation: '口型同 /θ/，声带振动，气流更弱更短。',
      mouthShape: '伸舌，喉咙震动。',
      tips: <String>['this /ðɪs/、that /ðæt/、the /ðə/ 都是它', '虚词里高频，要伸舌'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'th', example: 'this /ðɪs/'),
        SpellingPattern(pattern: 'th', example: 'that /ðæt/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'this', phonetic: '/ðɪs/', meaning: '这个'),
        PhonemeExample(word: 'that', phonetic: '/ðæt/', meaning: '那个'),
        PhonemeExample(word: 'they', phonetic: '/ðeɪ/', meaning: '他们'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '易被读成 /z/ 或 /d/，this 读成 zis 是典型中式。',
      confusable: <String>['θ', 'z', 'd'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 's',
      nameZh: '丝',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '清齿龈擦音，舌尖近齿龈，气流细而强。',
      articulation: '舌尖靠近上齿龈，留窄缝，气流摩擦而出，声带不振动。',
      mouthShape: '舌尖上抬，嘴角咧开，嘶嘶声。',
      tips: <String>['与 /θ/ 对比：/s/ 舌不伸', 'sun /sʌn/ 就是它'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 's', example: 'sun /sʌn/'),
        SpellingPattern(pattern: 'c', example: 'city /ˈsɪti/'),
        SpellingPattern(pattern: 'ss', example: 'class /klɑːs/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'sun', phonetic: '/sʌn/', meaning: '太阳'),
        PhonemeExample(word: 'see', phonetic: '/siː/', meaning: '看见'),
        PhonemeExample(word: 'bus', phonetic: '/bʌs/', meaning: '公交车'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /θ/、/ʃ/ 区分是听力重点。',
      confusable: <String>['z', 'θ', 'ʃ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'z',
      nameZh: '兹',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '/s/ 的浊音版。',
      articulation: '口型同 /s/，声带振动。',
      mouthShape: '舌尖摩擦，喉咙震动。',
      tips: <String>['zoo /zuː/、zero /ˈzɪərəʊ/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'z', example: 'zoo /zuː/'),
        SpellingPattern(pattern: 's', example: 'has /hæz/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'zoo', phonetic: '/zuː/', meaning: '动物园'),
        PhonemeExample(word: 'has', phonetic: '/hæz/', meaning: '有'),
        PhonemeExample(word: 'easy', phonetic: '/ˈiːzi/', meaning: '容易'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾 -s 在浊音后读 /z/：dogs /dɒɡz/。',
      confusable: <String>['s', 'ð', 'ʒ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ʃ',
      nameZh: '诗',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '清腭擦音，比 /s/ 更后、更钝、唇稍圆。',
      articulation: '舌身抬向硬腭，舌尖稍卷，双唇稍圆，气流摩擦。',
      mouthShape: '唇略圆，舌面抬起，像嘘。',
      tips: <String>['she /ʃiː/、shop /ʃɒp/ 就是它', '不要发成 /s/，/ʃ/ 更钝'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'sh', example: 'she /ʃiː/'),
        SpellingPattern(pattern: 'ti', example: 'nation /ˈneɪʃn/'),
        SpellingPattern(pattern: 'ch', example: 'chef /ʃef/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'she', phonetic: '/ʃiː/', meaning: '她'),
        PhonemeExample(word: 'shop', phonetic: '/ʃɒp/', meaning: '商店'),
        PhonemeExample(word: 'wash', phonetic: '/wɒʃ/', meaning: '洗'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /s/、/ʒ/ 最小对立：sip /sɪp/ vs ship /ʃɪp/。',
      confusable: <String>['s', 'ʒ', 'tʃ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ʒ',
      nameZh: '日诗浊',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '/ʃ/ 的浊音版，出现频率低但关键。',
      articulation: '口型同 /ʃ/，声带振动。',
      mouthShape: '唇圆，喉震。',
      tips: <String>['vision /ˈvɪʒn/、measure /ˈmeʒə/ 就是它'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'sion', example: 'vision /ˈvɪʒn/'),
        SpellingPattern(pattern: 'sure', example: 'measure /ˈmeʒə/'),
        SpellingPattern(pattern: 'ge', example: 'garage /ˈɡærɑːʒ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'vision', phonetic: '/ˈvɪʒn/', meaning: '视力'),
        PhonemeExample(word: 'measure', phonetic: '/ˈmeʒə/', meaning: '测量'),
        PhonemeExample(word: 'usually', phonetic: '/ˈjuːʒəli/', meaning: '通常'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '很多人读成 /dʒ/，vision 读成 vidʒn 是错的，中间没有爆破。',
      confusable: <String>['ʃ', 'dʒ', 'z'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'h',
      nameZh: '哈',
      category: PhonemeCategory.fricative,
      groupLabel: '摩擦音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '声门摩擦，只有送气，无舌位，靠后接元音定口型。',
      articulation: '声门张开，气流直接送出，经口腔的元音口型共振。',
      mouthShape: '轻哈气，口型随元音而变。',
      tips: <String>['he /hiː/ 口型是 /iː/，who /huː/ 口型是 /uː/，/h/ 本身无固定口型'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'h', example: 'he /hiː/'),
        SpellingPattern(pattern: 'wh', example: 'who /huː/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'he', phonetic: '/hiː/', meaning: '他'),
        PhonemeExample(word: 'house', phonetic: '/haʊs/', meaning: '房子'),
        PhonemeExample(word: 'how', phonetic: '/haʊ/', meaning: '怎么'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '不要用中文赫的喉擦，/h/ 更轻，只是一阵气。',
      confusable: <String>['f'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'tʃ',
      nameZh: '吃',
      category: PhonemeCategory.affricate,
      groupLabel: '破擦音',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '清破擦，先爆破再摩擦，/t/ + /ʃ/ 的融合。',
      articulation: '舌尖抵齿龈爆破，立即滑向 /ʃ/ 的摩擦，声带不振动。',
      mouthShape: '先顶后嘘，连成一气。',
      tips: <String>['chair /tʃeə/、China /ˈtʃaɪnə/ 就是它', '不要拆成 t+sh 两段，要一气呵成'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ch', example: 'chair /tʃeə/'),
        SpellingPattern(pattern: 'tch', example: 'watch /wɒtʃ/'),
        SpellingPattern(pattern: 'ture', example: 'future /ˈfjuːtʃə/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'chair', phonetic: '/tʃeə/', meaning: '椅子'),
        PhonemeExample(word: 'watch', phonetic: '/wɒtʃ/', meaning: '看'),
        PhonemeExample(word: 'cheap', phonetic: '/tʃiːp/', meaning: '便宜'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '易与 /ʃ/ 混：chip /tʃɪp/ vs ship /ʃɪp/。',
      confusable: <String>['dʒ', 'ʃ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'dʒ',
      nameZh: '之',
      category: PhonemeCategory.affricate,
      groupLabel: '破擦音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '/tʃ/ 的浊音版，声带振动。',
      articulation: '口型同 /tʃ/，声带振动。',
      mouthShape: '带声的吃。',
      tips: <String>['job /dʒɒb/、just /dʒʌst/ 就是它'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'j', example: 'job /dʒɒb/'),
        SpellingPattern(pattern: 'g', example: 'page /peɪdʒ/'),
        SpellingPattern(pattern: 'dge', example: 'bridge /brɪdʒ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'job', phonetic: '/dʒɒb/', meaning: '工作'),
        PhonemeExample(word: 'page', phonetic: '/peɪdʒ/', meaning: '页'),
        PhonemeExample(word: 'bridge', phonetic: '/brɪdʒ/', meaning: '桥'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '不要读成 /ʒ/，/dʒ/ 有爆破感，/ʒ/ 只有摩擦。',
      confusable: <String>['tʃ', 'ʒ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'm',
      nameZh: '姆',
      category: PhonemeCategory.nasal,
      groupLabel: '鼻音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '双唇鼻音，气流走鼻腔。',
      articulation: '双唇闭合，软腭下降，气流从鼻腔出，声带振动。',
      mouthShape: '闭唇，鼻腔共振。',
      tips: <String>['me /miː/、come /kʌm/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'm', example: 'me /miː/'),
        SpellingPattern(pattern: 'mm', example: 'summer /ˈsʌmə/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'me', phonetic: '/miː/', meaning: '我'),
        PhonemeExample(word: 'come', phonetic: '/kʌm/', meaning: '来'),
        PhonemeExample(word: 'name', phonetic: '/neɪm/', meaning: '名字'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾 /m/ 闭唇要到位，time /taɪm/ 唇要合。',
      confusable: <String>['n', 'ŋ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'n',
      nameZh: '恩',
      category: PhonemeCategory.nasal,
      groupLabel: '鼻音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '齿龈鼻音，舌尖鼻音。',
      articulation: '舌尖抵上齿龈，软腭下降，气流走鼻腔，声带振动。',
      mouthShape: '舌尖顶龈，鼻腔出气。',
      tips: <String>['no /nəʊ/、ten /ten/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'n', example: 'no /nəʊ/'),
        SpellingPattern(pattern: 'nn', example: 'dinner /ˈdɪnə/'),
        SpellingPattern(pattern: 'kn', example: 'know /nəʊ/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'no', phonetic: '/nəʊ/', meaning: '不'),
        PhonemeExample(word: 'ten', phonetic: '/ten/', meaning: '十'),
        PhonemeExample(word: 'sun', phonetic: '/sʌn/', meaning: '太阳'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /l/ 易混：night /naɪt/ vs light /laɪt/。',
      confusable: <String>['m', 'ŋ', 'l'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ŋ',
      nameZh: '嗯歌',
      category: PhonemeCategory.nasal,
      groupLabel: '鼻音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '后鼻音，/n/ 的后舌版，只在音节尾出现。',
      articulation: '舌后部抬起抵软腭，舌尖不参与，气流走鼻腔。',
      mouthShape: '舌根抬起，舌尖平放。',
      tips: <String>[
        'sing /sɪŋ/ vs sin /sɪn/ 最小对立',
        '不要在 /ŋ/ 后加 /ɡ/，sing 不是 singge',
      ],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ng', example: 'sing /sɪŋ/'),
        SpellingPattern(pattern: 'nk', example: 'think /θɪŋk/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'sing', phonetic: '/sɪŋ/', meaning: '唱歌'),
        PhonemeExample(word: 'long', phonetic: '/lɒŋ/', meaning: '长的'),
        PhonemeExample(word: 'think', phonetic: '/θɪŋk/', meaning: '想'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '中国学习者常把 /ŋ/ 发成 /n/，或多加 /ɡ/，这是口音标志。',
      // 旧版此处还写了 `ŋk`。它不是音标符号而是拼写组合（该条目 spellings 里
      // 已有 `nk → think /θɪŋk/`），留着会让「易混对比」指向不存在的条目。
      confusable: <String>['n'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'l',
      nameZh: '乐',
      category: PhonemeCategory.lateral,
      groupLabel: '近音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '舌侧音，气流从舌两侧通过，有清晰 /l/ 与模糊 /l/ 之分。',
      articulation: '舌尖抵上齿龈，气流从舌两边出，声带振动。',
      mouthShape: '舌尖顶龈，两侧留缝。',
      tips: <String>[
        'light /laɪt/ 是清晰 l（舌尖顶），feel /fiːl/ 是模糊 l（舌后部抬）',
        '与 /r/ 对比：/l/ 舌尖碰龈，/r/ 不碰',
      ],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'l', example: 'like /laɪk/'),
        SpellingPattern(pattern: 'll', example: 'call /kɔːl/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'like', phonetic: '/laɪk/', meaning: '喜欢'),
        PhonemeExample(word: 'light', phonetic: '/laɪt/', meaning: '光'),
        PhonemeExample(word: 'feel', phonetic: '/fiːl/', meaning: '感觉'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /r/、/n/ 混淆重灾，必须舌尖顶龈。',
      confusable: <String>['r', 'n'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'r',
      nameZh: '日',
      category: PhonemeCategory.approximant,
      groupLabel: '近音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '近音，舌尖不碰任何部位，靠舌的卷曲度形成。',
      articulation: '舌尖抬向硬腭但不接触，舌身收束，双唇稍圆，声带振动。',
      mouthShape: '舌尖悬空，唇略圆，像轻度卷舌。',
      tips: <String>['不要弹舌，不要发成中文日', 'red /red/、right /raɪt/ 舌尖不碰龈'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'r', example: 'red /red/'),
        SpellingPattern(pattern: 'rr', example: 'borrow /ˈbɒrəʊ/'),
        SpellingPattern(pattern: 'wr', example: 'write /raɪt/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'red', phonetic: '/red/', meaning: '红色'),
        PhonemeExample(word: 'right', phonetic: '/raɪt/', meaning: '正确的'),
        PhonemeExample(word: 'sorry', phonetic: '/ˈsɒri/', meaning: '抱歉'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '与 /l/ 混淆是中式口音主因：right vs light。',
      confusable: <String>['l', 'w'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'j',
      nameZh: '耶',
      category: PhonemeCategory.approximant,
      groupLabel: '半元音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '半元音，/iː/ 的快速滑入版。',
      articulation: '舌前部高抬如 /iː/，快速滑向元音。',
      mouthShape: '从 /i/ 的口型快速打开。',
      tips: <String>['yes /jes/、you /juː/ 起点就是它', '不要发成中文机，/j/ 更轻更快'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'y', example: 'yes /jes/'),
        SpellingPattern(pattern: 'u', example: 'use /juːz/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'yes', phonetic: '/jes/', meaning: '是的'),
        PhonemeExample(word: 'you', phonetic: '/juː/', meaning: '你'),
        PhonemeExample(word: 'use', phonetic: '/juːz/', meaning: '使用'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: 'you /juː/ 不要读成 zu。',
      confusable: <String>['dʒ', 'ʒ'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'w',
      nameZh: '乌阿',
      category: PhonemeCategory.approximant,
      groupLabel: '半元音',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '半元音，/uː/ 的快速滑入版，双唇收圆。',
      articulation: '双唇紧圆如 /uː/，快速滑向元音。',
      mouthShape: '先噘嘴再打开。',
      tips: <String>[
        'we /wiː/、window /ˈwɪndəʊ/ 就是它',
        '与 /v/ 对比：/w/ 不碰唇，/v/ 咬唇',
      ],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'w', example: 'we /wiː/'),
        SpellingPattern(pattern: 'wh', example: 'what /wɒt/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'we', phonetic: '/wiː/', meaning: '我们'),
        PhonemeExample(word: 'window', phonetic: '/ˈwɪndəʊ/', meaning: '窗户'),
        PhonemeExample(word: 'what', phonetic: '/wɒt/', meaning: '什么'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: 'very /ˈveri/ (咬唇) vs wary /ˈweəri/ (噘嘴) 必须分。',
      confusable: <String>['v', 'r'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'tr',
      nameZh: '戳',
      category: PhonemeCategory.affricate,
      groupLabel: '破擦音 · 教材扩展',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '教材扩展：/t/ + /r/ 的腭化破擦，常标为 /tr/。',
      articulation: '舌尖抵齿龈爆破后立即进入 /r/ 的近音摩擦。',
      mouthShape: '先特后日，连读。',
      tips: <String>[
        'tree /triː/、try /traɪ/ 就是它',
        '严格 IPA 记为 /tʃr/ 变体，教材为方便单列',
      ],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'tr', example: 'tree /triː/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'tree', phonetic: '/triː/', meaning: '树'),
        PhonemeExample(word: 'try', phonetic: '/traɪ/', meaning: '尝试'),
        PhonemeExample(word: 'train', phonetic: '/treɪn/', meaning: '火车'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '不要读成中文戳的翘舌，要轻。',
      confusable: <String>['tʃ', 'dr'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'dr',
      nameZh: '捉',
      category: PhonemeCategory.affricate,
      groupLabel: '破擦音 · 教材扩展',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '/tr/ 的浊音版。',
      articulation: '同 /tr/，声带振动。',
      mouthShape: '带声的戳。',
      tips: <String>['dream /driːm/、drive /draɪv/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'dr', example: 'dream /driːm/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'dream', phonetic: '/driːm/', meaning: '梦'),
        PhonemeExample(word: 'drive', phonetic: '/draɪv/', meaning: '驾驶'),
        PhonemeExample(word: 'draw', phonetic: '/drɔː/', meaning: '画'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '同上，轻浊有别。',
      confusable: <String>['dʒ', 'tr'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'ts',
      nameZh: '次',
      category: PhonemeCategory.affricate,
      groupLabel: '破擦音 · 教材扩展',
      voicing: PhonemeVoicing.voiceless,
    ),
    guide: PhonemeGuide(
      what: '教材扩展：/t/ + /s/，cats /kæts/ 词尾。',
      articulation: '齿龈爆破后接齿龈摩擦。',
      mouthShape: '特丝连读。',
      tips: <String>['cats /kæts/、gets /ɡets/ 词尾就是它'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ts', example: 'cats /kæts/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'cats', phonetic: '/kæts/', meaning: '猫(复数)'),
        PhonemeExample(word: 'gets', phonetic: '/ɡets/', meaning: '得到'),
        PhonemeExample(
          word: 'students',
          phonetic: '/ˈstjuːdnts/',
          meaning: '学生',
        ),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾复数 -s 在清音后读 /s/，连起来像 /ts/。',
      confusable: <String>['dz', 's'],
    ),
  ),
  PhonemeEntry(
    identity: PhonemeIdentity(
      symbol: 'dz',
      nameZh: '自',
      category: PhonemeCategory.affricate,
      groupLabel: '破擦音 · 教材扩展',
      voicing: PhonemeVoicing.voiced,
    ),
    guide: PhonemeGuide(
      what: '/ts/ 的浊音版，dogs /dɒɡz/ 词尾的浊 s 在浊音后归为 /z/，连读似 /dz/。',
      articulation: '浊爆破后接浊摩擦。',
      mouthShape: '得兹连读。',
      tips: <String>['dogs /dɒɡz/、reads /riːdz/'],
    ),
    examples: PhonemeExamples(
      spellings: <SpellingPattern>[
        SpellingPattern(pattern: 'ds', example: 'reads /riːdz/'),
      ],
      exampleWords: <PhonemeExample>[
        PhonemeExample(word: 'dogs', phonetic: '/dɒɡz/', meaning: '狗(复数)'),
        PhonemeExample(word: 'reads', phonetic: '/riːdz/', meaning: '读'),
        PhonemeExample(word: 'words', phonetic: '/wɜːdz/', meaning: '单词'),
      ],
    ),
    relations: PhonemeRelations(
      pitfalls: '词尾浊 s 不要清化。',
      confusable: <String>['ts', 'z'],
    ),
  ),
];

/// 易混对比组（旧版 `CONTRAST_GROUPS`）：8 组最小对立，用于解析面板。
const List<ContrastGroup> contrastGroups = <ContrastGroup>[
  ContrastGroup(
    id: 'long-short',
    title: '长短元音',
    titleEn: 'Long vs Short',
    body: ContrastGroupBody(
      description: '长短不分直接变词，中文没有长短对立，必须靠时长+口型区分。',
      symbols: <String>['iː', 'ɪ', 'uː', 'ʊ', 'ɑː', 'ʌ', 'ɔː', 'ɒ'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'sheep',
          right: 'ship',
          leftPhonetic: '/ʃiːp/',
          rightPhonetic: '/ʃɪp/',
          meanings: MinimalPairMeanings(left: '绵羊', right: '船'),
        ),
        MinimalPair(
          left: 'beat',
          right: 'bit',
          leftPhonetic: '/biːt/',
          rightPhonetic: '/bɪt/',
          meanings: MinimalPairMeanings(left: '打', right: '一点'),
        ),
        MinimalPair(
          left: 'pool',
          right: 'pull',
          leftPhonetic: '/puːl/',
          rightPhonetic: '/pʊl/',
          meanings: MinimalPairMeanings(left: '池', right: '拉'),
        ),
        MinimalPair(
          left: 'cart',
          right: 'cut',
          leftPhonetic: '/kɑːt/',
          rightPhonetic: '/kʌt/',
          meanings: MinimalPairMeanings(left: '手推车', right: '切'),
        ),
        MinimalPair(
          left: 'caught',
          right: 'cot',
          leftPhonetic: '/kɔːt/',
          rightPhonetic: '/kɒt/',
          meanings: MinimalPairMeanings(left: '抓住', right: '床(英)'),
        ),
      ],
    ),
    keyTip: '长元音肌肉紧张、时长拉满；短元音放松、点到为止。照镜子看口型是否咧/噘到位。',
  ),
  ContrastGroup(
    id: 'front-vowels',
    title: '前元音重灾',
    titleEn: '/e/ vs /æ/ vs /ʌ/',
    body: ContrastGroupBody(
      description: '中文没有 /æ/，很多人把 bed、bad、bud 读成同一个音。',
      symbols: <String>['e', 'æ', 'ʌ'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'bed',
          right: 'bad',
          leftPhonetic: '/bed/',
          rightPhonetic: '/bæd/',
          meanings: MinimalPairMeanings(left: '床', right: '坏的'),
        ),
        MinimalPair(
          left: 'pen',
          right: 'pan',
          leftPhonetic: '/pen/',
          rightPhonetic: '/pæn/',
          meanings: MinimalPairMeanings(left: '笔', right: '平底锅'),
        ),
        MinimalPair(
          left: 'cut',
          right: 'cat',
          leftPhonetic: '/kʌt/',
          rightPhonetic: '/kæt/',
          meanings: MinimalPairMeanings(left: '切', right: '猫'),
        ),
        MinimalPair(
          left: 'luck',
          right: 'lack',
          leftPhonetic: '/lʌk/',
          rightPhonetic: '/læk/',
          meanings: MinimalPairMeanings(left: '运气', right: '缺乏'),
        ),
      ],
    ),
    keyTip: '/æ/ 下巴掉下来，/e/ 半开，/ʌ/ 舌位靠后，三者张口度递增：/ʌ/ < /e/ < /æ/。',
  ),
  ContrastGroup(
    id: 'th-s',
    title: '咬舌音',
    titleEn: '/θ ð/ vs /s z/',
    body: ContrastGroupBody(
      description: '不伸舌就是中式，think 读成 sink 是最典型的口音。',
      symbols: <String>['θ', 'ð', 's', 'z'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'think',
          right: 'sink',
          leftPhonetic: '/θɪŋk/',
          rightPhonetic: '/sɪŋk/',
          meanings: MinimalPairMeanings(left: '想', right: '下沉'),
        ),
        MinimalPair(
          left: 'three',
          right: 'see',
          leftPhonetic: '/θriː/',
          rightPhonetic: '/siː/',
          meanings: MinimalPairMeanings(left: '三', right: '看见'),
        ),
        MinimalPair(
          left: 'they',
          right: 'day',
          leftPhonetic: '/ðeɪ/',
          rightPhonetic: '/deɪ/',
          meanings: MinimalPairMeanings(left: '他们', right: '天'),
        ),
        MinimalPair(
          left: 'breathe',
          right: 'breeze',
          leftPhonetic: '/briːð/',
          rightPhonetic: '/briːz/',
          meanings: MinimalPairMeanings(left: '呼吸', right: '微风'),
        ),
      ],
    ),
    keyTip: '发 /θ ð/ 舌尖必须伸出上下齿间，对镜子能看见舌尖；/s z/ 舌尖在齿后。',
  ),
  ContrastGroup(
    id: 'l-r',
    title: 'L / R 不分',
    titleEn: '/l/ vs /r/',
    body: ContrastGroupBody(
      description: '中式口音第一特征，right 读成 light 老外会懵。',
      symbols: <String>['l', 'r'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'right',
          right: 'light',
          leftPhonetic: '/raɪt/',
          rightPhonetic: '/laɪt/',
          meanings: MinimalPairMeanings(left: '正确的', right: '光'),
        ),
        MinimalPair(
          left: 'collect',
          right: 'correct',
          leftPhonetic: '/kəˈlekt/',
          rightPhonetic: '/kəˈrekt/',
          meanings: MinimalPairMeanings(left: '收集', right: '纠正'),
        ),
        MinimalPair(
          left: 'play',
          right: 'pray',
          leftPhonetic: '/pleɪ/',
          rightPhonetic: '/preɪ/',
          meanings: MinimalPairMeanings(left: '玩', right: '祈祷'),
        ),
        MinimalPair(
          left: 'glass',
          right: 'grass',
          leftPhonetic: '/ɡlɑːs/',
          rightPhonetic: '/ɡrɑːs/',
          meanings: MinimalPairMeanings(left: '玻璃', right: '草'),
        ),
      ],
    ),
    keyTip: '/l/ 舌尖必须碰上齿龈，/r/ 舌尖悬空不碰，唇略圆。',
  ),
  ContrastGroup(
    id: 'v-w',
    title: 'V / W 不分',
    titleEn: '/v/ vs /w/',
    body: ContrastGroupBody(
      description: 'very 读成 wary 是高频错误。',
      symbols: <String>['v', 'w'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'very',
          right: 'wary',
          leftPhonetic: '/ˈveri/',
          rightPhonetic: '/ˈweəri/',
          meanings: MinimalPairMeanings(left: '非常', right: '谨慎'),
        ),
        MinimalPair(
          left: 'vine',
          right: 'wine',
          leftPhonetic: '/vaɪn/',
          rightPhonetic: '/waɪn/',
          meanings: MinimalPairMeanings(left: '藤', right: '酒'),
        ),
        MinimalPair(
          left: 'west',
          right: 'vest',
          leftPhonetic: '/west/',
          rightPhonetic: '/vest/',
          meanings: MinimalPairMeanings(left: '西', right: '背心'),
        ),
      ],
    ),
    keyTip: '/v/ 上齿咬下唇+喉震，/w/ 双唇噘嘴不碰唇。',
  ),
  ContrastGroup(
    id: 's-sh',
    title: 'S / SH / ZH',
    titleEn: '/s ʃ ʒ/',
    body: ContrastGroupBody(
      description: 'sip vs ship vs vision，三档摩擦要分层。',
      symbols: <String>['s', 'ʃ', 'ʒ'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'sip',
          right: 'ship',
          leftPhonetic: '/sɪp/',
          rightPhonetic: '/ʃɪp/',
          meanings: MinimalPairMeanings(left: '啜饮', right: '船'),
        ),
        MinimalPair(
          left: 'measure',
          right: 'mesh',
          leftPhonetic: '/ˈmeʒə/',
          rightPhonetic: '/meʃ/',
          meanings: MinimalPairMeanings(left: '测量', right: '网'),
        ),
        MinimalPair(
          left: 'cheap',
          right: 'sheep',
          leftPhonetic: '/tʃiːp/',
          rightPhonetic: '/ʃiːp/',
          meanings: MinimalPairMeanings(left: '便宜', right: '绵羊'),
        ),
      ],
    ),
    keyTip: '/s/ 嘶、/ʃ/ 嘘(钝)、/ʒ/ 嘘+震，按舌位由前到后。',
  ),
  ContrastGroup(
    id: 'n-ng',
    title: '鼻尾音',
    titleEn: '/n/ vs /ŋ/',
    body: ContrastGroupBody(
      description: 'sin vs sing，舌尖 vs 舌根，老外一听就知。',
      symbols: <String>['n', 'ŋ'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'sin',
          right: 'sing',
          leftPhonetic: '/sɪn/',
          rightPhonetic: '/sɪŋ/',
          meanings: MinimalPairMeanings(left: '罪', right: '唱'),
        ),
        MinimalPair(
          left: 'thin',
          right: 'thing',
          leftPhonetic: '/θɪn/',
          rightPhonetic: '/θɪŋ/',
          meanings: MinimalPairMeanings(left: '薄', right: '东西'),
        ),
        MinimalPair(
          left: 'run',
          right: 'rung',
          leftPhonetic: '/rʌn/',
          rightPhonetic: '/rʌŋ/',
          meanings: MinimalPairMeanings(left: '跑', right: '梯级'),
        ),
      ],
    ),
    keyTip: '/n/ 舌尖顶龈，/ŋ/ 舌根抬起抵软腭，/ŋ/ 后不要加 /ɡ/。',
  ),
  ContrastGroup(
    id: 'voiced-voiceless',
    title: '清浊对立',
    titleEn: 'Voiced vs Voiceless',
    body: ContrastGroupBody(
      description: '词尾清浊决定复数与过去式的发音，清浊不分语法都受影响。',
      symbols: <String>['p', 'b', 't', 'd', 'k', 'ɡ', 'f', 'v', 's', 'z'],
      pairs: <MinimalPair>[
        MinimalPair(
          left: 'pin',
          right: 'bin',
          leftPhonetic: '/pɪn/',
          rightPhonetic: '/bɪn/',
          meanings: MinimalPairMeanings(left: '别针', right: '垃圾箱'),
        ),
        MinimalPair(
          left: 'coat',
          right: 'goat',
          leftPhonetic: '/kəʊt/',
          rightPhonetic: '/ɡəʊt/',
          meanings: MinimalPairMeanings(left: '外套', right: '山羊'),
        ),
        MinimalPair(
          left: 'safe',
          right: 'save',
          leftPhonetic: '/seɪf/',
          rightPhonetic: '/seɪv/',
          meanings: MinimalPairMeanings(left: '安全', right: '拯救'),
        ),
        MinimalPair(
          left: 'price',
          right: 'prize',
          leftPhonetic: '/praɪs/',
          rightPhonetic: '/praɪz/',
          meanings: MinimalPairMeanings(left: '价格', right: '奖品'),
        ),
      ],
    ),
    keyTip: '手摸喉咙：浊音震手，清音不震；词尾 -s 在清音后读 /s/ (cats)，浊音/元音后读 /z/ (dogs)。',
  ),
];

/// 美英差异表（旧版 `ACCENT_DIFFS`）：9 条高频分野。
const List<AccentDiff> accentDiffs = <AccentDiff>[
  AccentDiff(
    symbol: 'ɒ → ɑ',
    samples: AccentSamples(uk: '/hɒt/', us: '/hɑt/'),
    word: 'hot',
    description: '英短奥，美并入啊',
    note: '学美音可忽略 /ɒ/',
  ),
  AccentDiff(
    symbol: 'ɑː → ɑ + r',
    samples: AccentSamples(uk: '/kɑː/', us: '/kɑr/'),
    word: 'car',
    description: '英长啊不卷，美带 r',
    note: '是否卷舌是分野',
  ),
  AccentDiff(
    symbol: 'ɔː → ɔr',
    samples: AccentSamples(uk: '/mɔː/', us: '/mɔr/'),
    word: 'more',
    description: '英奥不卷，美带 r',
    note: '同上',
  ),
  AccentDiff(
    symbol: 'ɜː → ɝː',
    samples: AccentSamples(uk: '/bɜːd/', us: '/bɝːd/'),
    word: 'bird',
    description: '英呃不卷，美重卷',
    note: '美音标志',
  ),
  AccentDiff(
    symbol: 'əʊ → oʊ',
    samples: AccentSamples(uk: '/ɡəʊ/', us: '/ɡoʊ/'),
    word: 'go',
    description: '英呃乌，美哦乌',
    note: '口型起点不同',
  ),
  AccentDiff(
    symbol: 'ɪə → ɪr',
    samples: AccentSamples(uk: '/nɪə/', us: '/nɪr/'),
    word: 'near',
    description: '英双元音，美按 r 音',
    note: '美简化',
  ),
  AccentDiff(
    symbol: 'eə → er',
    samples: AccentSamples(uk: '/keə/', us: '/ker/'),
    word: 'care',
    description: '英欸呃，美欸r',
    note: '美简化',
  ),
  AccentDiff(
    symbol: 't → ɾ (闪音)',
    samples: AccentSamples(uk: '/ˈwɔːtə/', us: '/ˈwɑːtər/ → [ˈwɑɾər]'),
    word: 'water',
    description: '美音 t 在元音间常闪音似 d',
    note: 'water、better 高频',
  ),
  AccentDiff(
    symbol: 'æ 抬高',
    samples: AccentSamples(uk: '/mæn/', us: '/mæn/ (更张更大)'),
    word: 'man',
    description: '美音 /æ/ 更夸张',
    note: '美音开口更大',
  ),
];

/// 学习路径（旧版 `LEARNING_PATH`）：7 步，从「音标是什么」到「回到词中练」。
///
/// `step` 的序号是数据本身（1–7），逐行用 `// guard:allow-magic` 豁免
/// 魔法数字守卫——为 7 个序号各造一个常量只会让数据更难读。
const List<LearningStep> learningPath = <LearningStep>[
  LearningStep(
    step: 1,
    title: '先懂音标是什么',
    subtitle: 'Why IPA',
    points: <String>[
      '音标是声音的文字，一符一音，不猜拼写',
      '英式 RP 与美式 GA 口音不同，但 IPA 符号共通',
      '本区按 48 音框架 + 美英对照，兼容双口音',
    ],
  ),
  LearningStep(
    step: 2, // guard:allow-magic
    title: '元音打底：12 单元音',
    subtitle: 'Monophthongs',
    points: <String>[
      '前 /iː ɪ e æ/、中 /ɜː ə ʌ/、后 /ɑː ɒ ɔː ʊ uː/ 三区',
      '先练长短对立 /iː-ɪ/ /uː-ʊ/ /ɑː-ʌ/ /ɔː-ɒ/',
      '再攻前元音陷阱 /e-æ/',
    ],
  ),
  LearningStep(
    step: 3, // guard:allow-magic
    title: '滑音：8 双元音',
    subtitle: 'Diphthongs',
    points: <String>[
      '本质是滑动：/eɪ aɪ ɔɪ aʊ əʊ ɪə eə ʊə/',
      '重心在起点，收尾轻点到为止',
      '英美差异集中在 /əʊ→oʊ/ 与带 r 的三组',
    ],
  ),
  LearningStep(
    step: 4, // guard:allow-magic
    title: '辅音：按发音方法分组',
    subtitle: 'Consonants',
    points: <String>[
      '爆破 /p b t d k ɡ/ — 送气与清浊',
      '摩擦 /f v θ ð s z ʃ ʒ h/ — 咬舌与唇齿',
      '破擦 /tʃ dʒ tr dr/ 与鼻音 /m n ŋ/ + 近音 /l r j w/',
    ],
  ),
  LearningStep(
    step: 5, // guard:allow-magic
    title: '易混对比：最小对立',
    subtitle: 'Minimal Pairs',
    points: <String>[
      '用一音之差的词对来验是否真分清：ship/sheep、l/r、v/w、s/th',
      '每组 3-5 对，听辨+跟读循环',
      '过关标准：能盲听分辨',
    ],
  ),
  LearningStep(
    step: 6, // guard:allow-magic
    title: '美英分流与拼写规律',
    subtitle: 'Accent & Spelling',
    points: <String>[
      '美英差异表：/ɒ→ɑ/、/ɑː→ɑr/、/əʊ→oʊ/、闪音',
      '拼写不等于发音：ough 有 6 种读法，a 有 /æ eɪ ɑː ə/ 四读',
      '掌握规律后回单词本验音标',
    ],
  ),
  LearningStep(
    step: 7, // guard:allow-magic
    title: '回到词中练',
    subtitle: 'Practice in Words',
    points: <String>[
      '选当前薄弱的 2-3 个音，挑例词用 TTS 跟读',
      '再进音标训练营做 75 秒听辨挑战',
      '错词会自动进入复习队列',
    ],
  ),
];

/// 按符号查音标；未知符号返回 `null`。
///
/// 目录查找用线性扫描而非 Map：48 条数据，建索引的收益小于多一份
/// 需要同步维护的结构；调用点都在界面交互路径上，不在热循环里。
PhonemeEntry? phonemeBySymbol(String symbol) {
  final target = symbol.trim();
  for (final entry in phonemeCatalog) {
    if (entry.symbol == target) return entry;
  }
  return null;
}

/// 某个分类下的全部音标。
List<PhonemeEntry> phonemesInCategory(PhonemeCategory category) =>
    <PhonemeEntry>[
      for (final entry in phonemeCatalog)
        if (entry.category == category) entry,
    ];

/// 与给定音标易混的条目（悬空引用已被测试排除）。
List<PhonemeEntry> confusablePhonemes(String symbol) {
  final entry = phonemeBySymbol(symbol);
  if (entry == null) return const <PhonemeEntry>[];
  return <PhonemeEntry>[
    for (final other in entry.similarPhonemes) ?phonemeBySymbol(other),
  ];
}

/// 目录自检：48 个音标、每个都有示例词与发音要领、易混引用不悬空。
///
/// 放在生产代码而不是只放测试里，是因为旧版 `catalog.ts` 的悬空引用
/// （`confusable` 指向不存在的符号）在界面上表现为「点开对比却什么都没有」，
/// 而这类问题只会在用户点到的那个音标上暴露。界面启动时可调用它做一次
/// 廉价自检，测试也直接断言它返回空列表。
List<String> validatePhonemeCatalog() {
  final problems = <String>[];
  if (phonemeCatalog.length != phonemeCatalogSize) {
    problems.add('音标数量应为 $phonemeCatalogSize，实际 ${phonemeCatalog.length}');
  }
  final symbols = <String>{for (final entry in phonemeCatalog) entry.symbol};
  for (final entry in phonemeCatalog) {
    if (entry.symbol.trim().isEmpty) problems.add('存在空符号的音标条目');
    if (entry.description.trim().isEmpty) {
      problems.add('${entry.symbol} 缺少发音要领');
    }
    if (entry.examples.exampleWords.isEmpty) {
      problems.add('${entry.symbol} 缺少示例词');
    }
    for (final other in entry.similarPhonemes) {
      if (!symbols.contains(other)) {
        problems.add('${entry.symbol} 的易混音标 $other 不在目录中');
      }
    }
  }
  return problems;
}
