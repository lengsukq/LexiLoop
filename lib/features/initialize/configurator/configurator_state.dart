/// 配置器的草稿与动作。
///
/// 状态放在 provider 里而不是对话框的 State 里：来源列表、字段选择、
/// 预览这三样都要在对话框的不同区域之间来回对齐，放在 State 里只能靠
/// 一条条回调往下传——旧版那份 447 行的组件正是这么长的。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_fields.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_providers.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/services/dictionary/selection.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';

/// 配置器的作用范围。
enum ConfiguratorScope {
  /// 全部词条。
  all('全部词条'),

  /// 队列列表里已勾选的词条。
  selection('已选词条');

  new(this.label);

  /// 摘要里展示的名字。
  final String label;
}

/// 配置器正在执行的动作。
enum ConfiguratorBusy {
  /// 正在入队。
  create,
}

/// 配置器的一份草稿。
class ConfiguratorDraft {
  /// 以各字段构造。
  const new({
    required this.fields,
    required this.providers,
    required this.strategy,
    required this.mode,
    required this.scope,
    required this.youdaoOnly,
  });

  /// 打开配置器时的默认草稿：只补音标、仅补缺失、全部词条。
  ///
  /// 默认字段与旧版一致（`['pronunciations.phonetic']`）：用户点开配置器
  /// 最常见的场景就是「词典刚配上、音标还缺着」。
  /// 本次要请求的字段。
  final List<String> fields;

  /// 本次要请求的数据源（**顺序即优先级**）。
  final List<String> providers;

  /// 数据源调用策略。
  final ProviderStrategy strategy;

  /// 写入方式。
  final InitializationMode mode;

  /// 作用范围。
  final ConfiguratorScope scope;

  /// 来源是否被锁死为有道词典。
  final bool youdaoOnly;

  /// 复制并覆盖部分字段。
  ConfiguratorDraft copyWith({
    List<String>? fields,
    List<String>? providers,
    ProviderStrategy? strategy,
    InitializationMode? mode,
    ConfiguratorScope? scope,
    bool? youdaoOnly,
  }) => ConfiguratorDraft(
    fields: fields ?? this.fields,
    providers: providers ?? this.providers,
    strategy: strategy ?? this.strategy,
    mode: mode ?? this.mode,
    scope: scope ?? this.scope,
    youdaoOnly: youdaoOnly ?? this.youdaoOnly,
  );
}

/// 打开配置器时的默认草稿：只补音标、仅补缺失、传入的范围。
///
/// 默认字段与旧版一致（`['pronunciations.phonetic']`）：用户点开配置器
/// 最常见的场景就是「词典刚配上、音标还缺着」。
///
/// 写成顶层函数而不是静态方法：静态方法会被 `prefer_constructors_over_static_methods`
/// 判回构造函数，而具名工厂在这个工具链上又会触发
/// `unnecessary_type_name_in_constructor`。
ConfiguratorDraft initialConfiguratorDraft(ConfiguratorScope scope) =>
    ConfiguratorDraft(
      fields: phoneticOnlyFields,
      providers: const <String>[],
      strategy: ProviderStrategy.priorityFallback,
      mode: InitializationMode.fillMissingFields,
      scope: scope,
      youdaoOnly: false,
    );

/// 配置器的界面状态。
class ConfiguratorState {
  /// 以草稿、可选忙碌标记与可选提示构造。
  const new({
    required this.draft,
    this.busy,
    this.message,
    this.messageIsError = false,
  });

  /// 当前草稿。
  final ConfiguratorDraft draft;

  /// 正在执行的动作；`null` 表示空闲。
  final ConfiguratorBusy? busy;

  /// 校验失败或创建成功的提示。
  final String? message;

  /// [message] 是否是一条错误。
  final bool messageIsError;

  /// 当前是否有操作在执行。
  bool get isBusy => busy != null;
}

/// 配置器的状态控制器。
class ConfiguratorNotifier extends Notifier<ConfiguratorState> {
  /// 以可选的初始范围构造。
  ///
  /// 从浮条打开时把范围钉在「已选词条」——用户刚在列表上勾过词条，
  /// 点开配置器却又默认成「全部词条」等于把刚才的勾选作废。
  new([this.initialScope]);

  /// 打开时的作用范围；为空表示「全部词条」。
  final ConfiguratorScope? initialScope;

  /// 必须在 `build()` 里 watch 而不是 read：数据源选项来自
  /// `appSettingsProvider`，而设置是异步读的。首帧 build 时选项还没到，
  /// 只 read 会拿到空列表，于是草稿里的「数据源」永远是空的——
  /// 用户看到的是一个没有来源可选、点了创建只会报「请至少选择一个
  /// 可用数据来源」的配置器。watch 让选项到达时整个草稿重建一次。
  ///
  /// 代价是设置变化时草稿会回到初始值。配置器是对话框，生命周期只有
  /// 几十秒，用户不会在对话框打开期间去改设置，所以这个代价可以接受。
  @override
  ConfiguratorState build() {
    final options =
        ref.watch(configuratorProviderOptionsProvider).asData?.value ??
        const <ConfiguratorProviderOption>[];
    final draft = initialConfiguratorDraft(
      initialScope ?? ConfiguratorScope.all,
    );
    return ConfiguratorState(
      draft: draft.copyWith(
        providers: _eligibleProviders(options, draft.fields),
      ),
    );
  }

  /// 套用一个预设。
  void applyPreset(ConfiguratorPreset preset) => _edit(
    state.draft.copyWith(
      fields: preset.fields,
      providers: preset.youdaoOnly
          ? _youdaoOnlyProviders(_options())
          : _mergedProviders(state.draft.providers, preset.fields),
      strategy: preset.youdaoOnly
          ? ProviderStrategy.priorityFallback
          : state.draft.strategy,
      youdaoOnly: preset.youdaoOnly,
    ),
  );

  /// 从「仅有道词典」解锁回自定义来源。
  ///
  /// 解锁后按当前字段重新推一份可用来源，而不是清空——
  /// 用户解锁的意图是「换个来源再跑」，不是「自己从头勾」。
  void unlockSources() => _edit(
    state.draft.copyWith(
      youdaoOnly: false,
      providers: _eligibleProviders(_options(), state.draft.fields),
      strategy: ProviderStrategy.priorityFallback,
    ),
  );

  /// 勾选 / 取消勾选一个字段。
  ///
  /// 改字段会连带收敛来源：字段变少的来源对不上新字段，留着只会让
  /// 摘要写着「3 个来源」而实际只有 1 个会被调用。
  void toggleField(String field) {
    final fields = _toggled(state.draft.fields, field);
    _edit(
      state.draft.copyWith(
        fields: fields,
        providers: _mergedProviders(state.draft.providers, fields),
      ),
    );
  }

  /// 勾选 / 取消勾选一个数据源。
  void toggleProvider(String id) {
    if (state.draft.youdaoOnly) return;
    if (!_selectable(id, state.draft.fields)) return;
    _edit(state.draft.copyWith(providers: _toggled(state.draft.providers, id)));
  }

  /// 把一个数据源在优先级里上移或下移。
  void moveProvider(String id, int offset) {
    if (state.draft.youdaoOnly) return;
    final current = state.draft.providers;
    final index = current.indexOf(id);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= current.length) return;
    final next = <String>[...current];
    next[index] = next[target];
    next[target] = current[index];
    _edit(state.draft.copyWith(providers: next));
  }

  /// 切换调用策略。
  void setStrategy(ProviderStrategy strategy) =>
      _edit(state.draft.copyWith(strategy: strategy));

  /// 切换作用范围。
  void setScope(ConfiguratorScope scope) =>
      _edit(state.draft.copyWith(scope: scope));

  /// 切换写入方式。
  void setMode(InitializationMode mode) =>
      _edit(state.draft.copyWith(mode: mode));

  /// 入队。
  ///
  /// [overwriteConfirmed] 是「刷新所选字段」的二次确认：
  /// 强制覆盖会冲掉机器抓来的内容（用户手工编辑的释义与例句仍然保留），
  /// 不确认就放行等于用一个不可逆的默认项替用户做决定。
  ///
  /// 返回 `true` 表示已入队、对话框可以关闭。
  Future<bool> create({required bool overwriteConfirmed}) async {
    final draft = state.draft;
    final invalid = _invalidReason(draft);
    if (invalid != null) return _fail(invalid);
    final destructive = draft.mode == InitializationMode.forceOverwrite;
    if (destructive && !overwriteConfirmed) return false;
    state = ConfiguratorState(draft: draft, busy: ConfiguratorBusy.create);
    try {
      final preview = await _preview(draft);
      if (preview.selectedWords == 0) return _fail(emptyScopeReason);
      final report = await ref
          .read(queueActionsProvider)
          .enqueueRequests(_requests(draft, preview.selectedWordIds));
      state = ConfiguratorState(draft: draft, message: createdMessage(report));
      return true;
    } on AppError catch (error) {
      return _fail(error.message);
    }
  }

  /// 取已加载的数据源选项；未加载完时返回空列表。
  ///
  /// 绝大多数调用点在 `build()` 之后（用户交互），那时选项早已就绪。
  List<ConfiguratorProviderOption> _options() =>
      ref.read(configuratorProviderOptionsProvider).asData?.value ??
      const <ConfiguratorProviderOption>[];

  Future<InitializationPreview> _preview(ConfiguratorDraft draft) => ref
      .read(initializationQueriesProvider)
      .previewBulk(
        requestedFields: draft.fields,
        mode: draft.mode,
        wordIds: draft.scope == ConfiguratorScope.selection
            ? <int>[...ref.read(queueSelectionProvider)]
            : const <int>[],
      );

  /// 当前草稿的入队请求。
  List<EnqueueRequest> _requests(ConfiguratorDraft draft, List<int> wordIds) =>
      <EnqueueRequest>[
        for (final wordId in wordIds)
          EnqueueRequest(
            wordId: wordId,
            taskType: JobTaskType.initialize,
            mode: draft.mode,
            requestedFields: draft.fields,
            requestedProviders: draft.providers,
            strategy: draft.strategy,
            priority: jobPriorityManualBulk,
          ),
      ];

  /// 草稿是否还缺必要项；缺时返回可读的原因。
  String? _invalidReason(ConfiguratorDraft draft) {
    if (draft.fields.isEmpty) return emptyFieldsReason;
    if (draft.providers.isEmpty) return emptyProvidersReason;
    if (draft.scope == ConfiguratorScope.selection &&
        ref.read(queueSelectionProvider).isEmpty) {
      return emptySelectionReason;
    }
    return null;
  }

  /// 当前字段下可勾选的来源（按展示顺序）。
  List<String> _eligibleProviders(
    List<ConfiguratorProviderOption> options,
    List<String> fields,
  ) => <String>[
    for (final option in options)
      if (option.available && _supports(option, fields)) option.id,
  ];

  /// 改字段后的来源列表：保留仍然合规的，再按顺序补齐新变得可用的。
  ///
  /// 保留而不是清空：用户在「仅有道词典」之外手动排好的优先级，
  /// 不该因为勾了一个无关字段就被打散。
  List<String> _mergedProviders(List<String> current, List<String> fields) {
    final eligible = _eligibleProviders(_options(), fields);
    return <String>[
      for (final id in current)
        if (eligible.contains(id)) id,
      for (final id in eligible)
        if (!current.contains(id)) id,
    ];
  }

  /// 有道词典锁定时的来源列表（有道不可用则留空，由校验拦下）。
  List<String> _youdaoOnlyProviders(List<ConfiguratorProviderOption> options) {
    final youdao = configuratorProviderOption(options, youdaoProviderId);
    return <String>[if (youdao?.available ?? false) youdaoProviderId];
  }

  /// 该来源此刻能否被勾选。
  bool _selectable(String id, List<String> fields) {
    final option = configuratorProviderOption(_options(), id);
    if (option == null || !option.available) return false;
    return _supports(option, fields);
  }

  /// 能力是否与当前字段有交集——判据直接来自 `selectProviders`。
  bool _supports(ConfiguratorProviderOption option, List<String> fields) =>
      supportsRequestedFields(
        option.provider,
        configuratorProbe(fields.toSet()),
      );

  List<String> _toggled(List<String> current, String value) {
    final next = <String>[...current];
    if (!next.remove(value)) next.add(value);
    return next;
  }

  void _edit(ConfiguratorDraft draft) =>
      state = ConfiguratorState(draft: draft);

  bool _fail(String message) {
    state = ConfiguratorState(
      draft: state.draft,
      message: message,
      messageIsError: true,
    );
    return false;
  }
}

/// 配置器状态。
final NotifierProvider<ConfiguratorNotifier, ConfiguratorState>
configuratorProvider =
    NotifierProvider<ConfiguratorNotifier, ConfiguratorState>(
      ConfiguratorNotifier.new,
    );

/// 配置器的预览。
///
/// 跟着草稿自动重算：预览的每个数字都直接由字段、来源与范围决定，
/// 让用户点一次「刷新」才看到新数字只会制造一次「我改了怎么没变」的困惑。
///
/// **只盯真正影响结果的三个输入**：来源顺序与调用策略不影响
/// 「哪些词条会被处理」，却会各自触发一次全表扫描，白白卡住界面。
final FutureProvider<InitializationPreview> configuratorPreviewProvider =
    FutureProvider<InitializationPreview>((ref) {
      final fields = ref.watch(
        configuratorProvider.select((state) => state.draft.fields),
      );
      final mode = ref.watch(
        configuratorProvider.select((state) => state.draft.mode),
      );
      final scope = ref.watch(
        configuratorProvider.select((state) => state.draft.scope),
      );
      final selection = ref.watch(queueSelectionProvider);
      return ref
          .watch(initializationQueriesProvider)
          .previewBulk(
            requestedFields: fields,
            mode: mode,
            wordIds: scope == ConfiguratorScope.selection
                ? <int>[...selection]
                : const <int>[],
          );
    });

/// 未选字段时的提示。
const String emptyFieldsReason = '请至少选择一个内容补全字段。';

/// 未选来源时的提示。
const String emptyProvidersReason = '请至少选择一个可用数据来源。';

/// 选了「已选词条」但没勾词条时的提示。
const String emptySelectionReason = '请先在队列列表中勾选需要内容补全的词条。';

/// 范围内没有需要处理的词条时的提示。
const String emptyScopeReason = '范围内的词条都已满足所选字段，没有需要新建的任务。';

/// 入队成功的提示：新建与合并必须分开报。
///
/// 合并的那部分用户本来就有任务在跑，不报出来就会以为「创建了 N 个」，
/// 而队列里其实一个都没多。
String createdMessage(EnqueueBulkReport report) =>
    '已创建 ${report.created.length} 个任务，合并 ${report.merged.length} 个现有任务。';
