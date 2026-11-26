/// 配置器里的数据源选项。
///
/// **可用性不是界面自己算的**：这里直接复用 `selectProviders` 的三层判据
/// （启用 / 支持该请求 / 能力与字段有交集），只是把「被判掉」的结果翻译成
/// 一句能照着做的中文原因。判据一旦在界面里再写一遍，
/// 「界面说可用、跑起来被跳过」就会成为必然。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/lookup_service.dart';
import 'package:lexiloop/services/dictionary/selection.dart';

/// 有道词典的稳定标识。
const String youdaoProviderId = 'youdao';

/// 配置器里的展示与排序顺序。
///
/// 直接续在 [defaultTranslationProviderOrder] 后面：排序的唯一事实来源是
/// 执行时真正用的那份顺序，配置器另排一套只会让「界面第一」与
/// 「实际先调」对不上。AI 排最后——它是补充而不是词典的替代品。
const List<String> configuratorProviderOrder = <String>[
  ...defaultTranslationProviderOrder,
  aiProviderSelectorId,
];

/// 数据源的中文名。
const Map<String, String> configuratorProviderLabels = <String, String>{
  youdaoProviderId: '有道词典',
  'iciba': '爱词霸',
  'merriam-webster': 'Merriam-Webster',
  'dictionaryapi.dev': 'DictionaryAPI.dev',
  'mymemory': 'MyMemory 翻译',
  aiProviderSelectorId: 'AI 生成',
};

/// 数据源的一句话能力说明。
///
/// 逐条对照 [providerCapabilities] 写成**人话**，而不是把能力字段名罗列出来：
/// 罗列 13 项既读不下去，也说不出「同义词要另外配 Key」这类真正的差别。
const Map<String, String> configuratorProviderDescriptions = <String, String>{
  youdaoProviderId: '释义、音标、音频、例句、短语、词形、同根词与词根，词条覆盖最广',
  'iciba': '释义、音标、音频、例句、短语与词形，不支持句子类词条',
  'merriam-webster': '英文释义、音标、音频与例句；同义词与反义词另需同义词典 Key',
  'dictionaryapi.dev': '英文释义、音标、音频、例句、同义词与反义词',
  'mymemory': '只提供释义，作为兜底来源',
  aiProviderSelectorId: '可产出全部字段（含助记与句子分析），耗时与费用最高',
};

/// 配置器里的一个数据源选项。
class ConfiguratorProviderOption {
  /// 以标识、名称、说明、provider 实例与可用性构造。
  const new({
    required this.id,
    required this.label,
    required this.description,
    required this.provider,
    required this.availability,
  });

  /// 存进任务的来源标识（AI 用稳定的选择符而不是含模型名的实例 ID）。
  final String id;

  /// 中文名。
  final String label;

  /// 一句话能力说明。
  final String description;

  /// 真实的 provider 实例。
  ///
  /// 保留它是为了让界面能对**当前这份字段选择**再问一次
  /// `supportsRequestedFields`，而不是在界面里抄一份「能力是否与字段有交集」。
  final DictionaryProvider provider;

  /// 设置层面的可用性与不可用原因。
  final ProviderAvailability availability;

  /// 是否可用。
  bool get available => availability.available;

  /// 不可用原因；可用时为 `null`。
  String? get reason => availability.reason;
}

/// 构造配置器的数据源选项列表（按 [configuratorProviderOrder] 排序）。
///
/// [probe] 的字段集合留空：字段适配是**随勾选变化**的，由选择面板逐次
/// 现问；这里只回答「这个来源在设置里能不能用」。
List<ConfiguratorProviderOption> configuratorProviderOptions({
  required AppSettings settings,
  required List<DictionaryProvider> providers,
  required ProviderRequest probe,
}) {
  final options = <ConfiguratorProviderOption>[];
  for (final id in configuratorProviderOrder) {
    final provider = _resolve(id, providers);
    if (provider == null) continue;
    options.add(
      ConfiguratorProviderOption(
        id: id,
        label: configuratorProviderLabels[id] ?? id,
        description: configuratorProviderDescriptions[id] ?? '',
        provider: provider,
        availability: providerAvailability(
          provider: provider,
          settings: settings,
          request: probe,
        ),
      ),
    );
  }
  return options;
}

/// 配置器的数据源选项。
final FutureProvider<List<ConfiguratorProviderOption>>
configuratorProviderOptionsProvider =
    FutureProvider<List<ConfiguratorProviderOption>>((ref) async {
      final settings = await ref.watch(appSettingsProvider.future);
      final lookup = DictionaryLookupService(ref.watch(httpFetcherProvider));
      return configuratorProviderOptions(
        settings: settings,
        providers: lookup.buildProviders(settings),
        probe: configuratorProbe(const <String>{}),
      );
    });

/// 该来源的能力是否与当前勾选的字段有交集。
///
/// 判据直接取自 `selectProviders` 用的那个函数（[supportsRequestedFields]），
/// 界面因此不会与执行时的过滤规则漂移。
bool providerSupportsFields(
  ConfiguratorProviderOption option,
  List<String> fields,
) =>
    supportsRequestedFields(option.provider, configuratorProbe(fields.toSet()));

/// 取某个选项；标识未登记时返回 `null`。
ConfiguratorProviderOption? configuratorProviderOption(
  List<ConfiguratorProviderOption> options,
  String id,
) {
  for (final option in options) {
    if (option.id == id) return option;
  }
  return null;
}

/// 找出一个选项对应的 provider 实例。
DictionaryProvider? _resolve(String id, List<DictionaryProvider> providers) {
  for (final provider in providers) {
    if (provider.id == id) return provider;
    if (id == aiProviderSelectorId && isAiProviderId(provider.id)) {
      return provider;
    }
  }
  return null;
}

/// 探测用请求的源语言。
///
/// 队列页无从得知每个词条的语言对（那要查库），而判据里只有
/// `supports` 这一条真的依赖语言对；这里固定用应用导入时的默认语言对，
/// 与 `features/import` 的默认值一致。真正的逐词判定发生在 worker 里。
const String configuratorProbeSourceLanguage = 'en';

/// 探测用请求的目标语言。
const String configuratorProbeTargetLanguage = 'zh-CN';

/// 构造一次探测请求。
///
/// **不会真的发请求**：它只喂给 `isEnabled` / `supports` /
/// [supportsRequestedFields] 这些纯判定。
ProviderRequest configuratorProbe(Set<String> fields) => ProviderRequest(
  term: '',
  contentType: LexicalContentType.word,
  sourceLanguage: configuratorProbeSourceLanguage,
  targetLanguage: configuratorProbeTargetLanguage,
  wantedFields: fields,
);
