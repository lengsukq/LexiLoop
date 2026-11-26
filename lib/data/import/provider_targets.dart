/// 数据源标识与「按设置挑出启用的数据源」。
///
/// 导入批次入队初始化任务时，把当前启用的数据源写进
/// `initialization_jobs.requested_providers_json`。**为什么要在导入时就固化**：
/// 任务可能在用户改设置之后才被 worker 领取，若那时才读设置，同一批导入
/// 的词条会用上不同的数据源组合，出问题难以复现。
library;

import 'package:lexiloop/domain/models/app_settings.dart';

/// 有道。
const String providerYoudao = 'youdao';

/// 爱词霸。
const String providerIciba = 'iciba';

/// dictionaryapi.dev。
const String providerDictionaryApi = 'dictionaryapi.dev';

/// MyMemory 翻译。
const String providerMyMemory = 'mymemory';

/// Merriam-Webster 词典。
const String providerMerriamWebster = 'merriam-webster';

/// 按设置列出启用的数据源 id。
///
/// 顺序即优先级顺序（词典类在前，翻译类在后），与旧版
/// `PARALLEL_MERGE` 策略下的合并顺序一致。全部关闭时返回空列表，
/// 由调用方决定是否退化为 `null`（worker 用默认组合）。
List<String> enabledProviderIds(ProviderSettings settings) {
  return <String>[
    if (settings.youdaoEnabled) providerYoudao,
    if (settings.icibaEnabled) providerIciba,
    if (settings.dictionaryApiEnabled) providerDictionaryApi,
    if (settings.merriamWebsterEnabled) providerMerriamWebster,
    if (settings.myMemoryEnabled) providerMyMemory,
  ];
}
