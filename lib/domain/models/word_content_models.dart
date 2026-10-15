/// 词条内容写操作（有道刷新、关联词）的视图模型。
///
/// 对应旧版 `src/app/(main)/words/[id]/word-detail-types.ts` 的
/// `RelationType` / `RelatedPreview`，以及 `src/modules/words/related.ts`
/// 的 `previewRelatedWord` 返回值。
///
/// **为什么放在 `lib/domain/` 而不是服务文件里**：这些结构是界面与服务
/// 之间的**共同语言**（弹窗要渲染它、服务要产出它），放在 `lib/services/`
/// 会让界面反向依赖某一个服务实现。这里全部是纯数据 + 一个纯函数，
/// 不引入 Flutter、Drift 或任何 IO 包。
library;

import 'package:lexiloop/domain/enums.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// 关联词与父词条的关系类型。
///
/// 与旧版 `RelationType` 逐字对应；`wire` 值同时是写入
/// `synonyms_json` 等列里 `relation` 字段的取值。
enum RelationType implements WireEnum {
  /// 近义词。
  synonym('SYNONYM'),

  /// 反义词。
  antonym('ANTONYM'),

  /// 同根词 / 词族。
  wordFamily('WORD_FAMILY'),

  /// 易混词。
  confusedWith('CONFUSED_WITH');

  new(this.wire);

  @override
  final String wire;
}

/// 关联词在词库中已有的词条。
///
/// 只带弹窗需要的四项：状态徽标、掌握分与「打开词条」要用的 ID。
/// 不把整行搬过来——那会让弹窗多出一堆它不显示的字段。
class RelatedWordExisting {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.initializationStatus,
    required this.masteryLevel,
    required this.masteryScore,
  });

  /// 词条 ID。
  final int id;

  /// 词条文本。
  final String term;

  /// 初始化状态。
  final InitializationStatus initializationStatus;

  /// 掌握等级。
  final MasteryLevel masteryLevel;

  /// 掌握分。
  final int masteryScore;

  /// 该词条是否已具备可用内容（`READY` 或 `PARTIAL`）。
  ///
  /// 旧版把这条判据内联在弹窗与 `addRelatedWord` 两处（`!["READY",
  /// "PARTIAL"].includes(status)`），这里收成一处，避免两处漂移。
  bool get hasUsableContent =>
      initializationStatus == InitializationStatus.ready ||
      initializationStatus == InitializationStatus.partial;
}

/// 关联词预览结果。
///
/// 对应旧版 `previewRelatedWord` 的返回值。`existing` 为 `null` 表示
/// 该词尚未进入词库。
class RelatedWordPreview {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.relation,
    this.translation,
    this.partOfSpeech,
    this.difference,
    this.source,
    this.existing,
  });

  /// 用户点选的原始词形。
  final String term;

  /// 归一化文本。
  final String normalizedTerm;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 父词条内容里记载的关系；父词条里找不到时退回近义词。
  final RelationType relation;

  /// 译文。
  final String? translation;

  /// 词性。
  final String? partOfSpeech;

  /// 与父词条的区别说明（易混词常见）。
  final String? difference;

  /// 数据来源标识。
  final String? source;

  /// 词库中已有的同名词条；不存在时为 `null`。
  final RelatedWordExisting? existing;

  /// 是否可以「加入词库 / 加入初始化」。
  ///
  /// 不存在，或存在但内容还不完整时可以加；已经就绪的词条再点一次只会
  /// 建一个永远跳过的任务，因此直接不给按钮。
  bool get canAdd => existing == null || !existing!.hasUsableContent;
}

/// 关联词加入词库的结果。
///
/// 对应旧版 `addRelatedWord` 的返回值；界面据此决定提示文案。
class RelatedAddResult {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.term,
    required this.created,
    required this.queued,
    required this.relation,
    required this.initializationStatus,
    this.jobId,
  });

  /// 词条 ID（可能是复用的既有词条）。
  final int wordId;

  /// 词条文本。
  final String term;

  /// 是否本次新建了词条。
  final bool created;

  /// 是否排入了初始化任务。
  final bool queued;

  /// 初始化任务 ID；未入队时为 `null`。
  final int? jobId;

  /// 用户点选的关系类型。
  final RelationType relation;

  /// 加入后的初始化状态。
  final InitializationStatus initializationStatus;
}

/// 关联词比对用的归一化键：NFKC + 去首尾空白 + 小写。
///
/// 与旧版 `findRelatedContent` 的
/// `term.normalize("NFKC").trim().toLocaleLowerCase()` 逐字对应。
/// **不复用 `normalizeTerm`**：那个函数只对「小写语言族」取小写，
/// 而父词条里的关联词文本可能来自任意语言，比对口径必须与旧版一致。
String relatedWordLookupKey(String value) =>
    unorm.nfkc(value).trim().toLowerCase();
