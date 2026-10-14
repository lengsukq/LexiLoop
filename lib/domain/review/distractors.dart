/// 干扰项来源的抽象。
///
/// 选择题需要一个「其他词条的释义/文本」池。取池涉及数据库查询，
/// 属于 data 层；但**如何用这些候选拼出选项**是纯逻辑，属于 domain 层。
/// 这个接口就是两者的接缝：data 层实现它，domain/service 层消费它。
///
/// 这样切分的好处是选项生成逻辑可以用假数据完整单测，
/// 不需要为了测「干扰项去重」而搭一个数据库。
library;

/// 一个可用作干扰项的候选词条。
class DistractorRow {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.term,
    required this.definitionsJson,
  });

  /// 词条 ID。
  final int wordId;

  /// 词条文本。
  final String term;

  /// 释义 JSON 原文。
  final String definitionsJson;
}

/// 干扰项候选的来源。
abstract interface class DistractorSource {
  /// 按词条文本批量取候选（用于「易混词」优先）。
  ///
  /// [terms] 为空时返回空列表。实现方需要限制返回条数。
  Future<List<DistractorRow>> byTerms(List<String> terms, int excludedWordId);

  /// 取用户错词本中的候选（按错误次数降序）。
  Future<List<DistractorRow>> activeWrongWords(int excludedWordId);

  /// 从全局池中随机取候选。
  ///
  /// [excludedWordIds] 至少包含题干词条自身；[count] 是期望条数，
  /// 实际可能更少（池子耗尽或候选释义重复）。
  Future<List<DistractorRow>> randomPool(Set<int> excludedWordIds, int count);
}
