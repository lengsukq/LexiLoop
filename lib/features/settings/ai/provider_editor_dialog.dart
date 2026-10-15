/// 新增 / 编辑 provider 的对话框。
///
/// **为什么用对话框而不是卡片内联编辑**：provider 的 `id` 被
/// `ai.providerId` / `ai.retryProviderId` 引用，内联边打字边存会产生一批
/// 「id 只改了一半」的中间状态，而且空值无法拦截——按一下退格键就把配置
/// 写坏了。对话框把一次编辑收成一个原子提交，顺带有了展示校验信息的地方。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 展示新增 / 编辑对话框。
///
/// 返回 `null` 表示用户取消；[takenIds] 用于拒绝重复 ID。
Future<LlmProviderConfig?> showProviderEditor(
  BuildContext context, {
  required Set<String> takenIds,
  LlmProviderConfig? provider,
}) => showDialog<LlmProviderConfig>(
  context: context,
  builder: (dialogContext) =>
      ProviderEditorDialog(takenIds: takenIds, provider: provider),
);

/// provider 编辑表单。
class ProviderEditorDialog extends StatefulWidget {
  /// 以已占用的 ID 集合与（可选的）被编辑项构造。
  const new({required this.takenIds, this.provider, super.key});

  /// 已被其他 provider 占用的 ID。
  final Set<String> takenIds;

  /// 被编辑的 provider；为空表示新增。
  final LlmProviderConfig? provider;

  @override
  State<ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<ProviderEditorDialog> {
  late final TextEditingController _id = TextEditingController(
    text: widget.provider?.id ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.provider?.name ?? '',
  );
  late final TextEditingController _baseUrl = TextEditingController(
    text: widget.provider?.baseUrl ?? '',
  );
  late final TextEditingController _apiKey = TextEditingController(
    text: widget.provider?.apiKey ?? '',
  );
  late LlmApiType _apiType = widget.provider?.apiType ?? LlmApiType.openai;

  /// API Key 默认隐藏：设置页可能被截图分享。
  bool _obscured = true;

  /// 校验失败的原因；为空表示当前可以提交。
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final error = _error;
    return AlertDialog(
      title: Text(widget.provider == null ? '添加 Provider' : '编辑 Provider'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _field(
              fieldKey: const Key('aiProviderEditorId'),
              label: 'ID',
              hint: '唯一标识，如 my-openai',
              controller: _id,
            ),
            const SizedBox(height: 10),
            _field(
              fieldKey: const Key('aiProviderEditorName'),
              label: '名称',
              hint: '显示名，可留空',
              controller: _name,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<LlmApiType>(
              key: const Key('aiProviderEditorApiType'),
              initialValue: _apiType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'API 类型'),
              items: <DropdownMenuItem<LlmApiType>>[
                for (final apiType in LlmApiType.values)
                  DropdownMenuItem<LlmApiType>(
                    value: apiType,
                    child: Text(apiTypeLabel(apiType)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _apiType = value);
              },
            ),
            const SizedBox(height: 10),
            _field(
              fieldKey: const Key('aiProviderEditorBaseUrl'),
              label: '接口地址',
              hint: baseUrlHint(_apiType),
              controller: _baseUrl,
            ),
            const SizedBox(height: 10),
            _secretField(),
            if (error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                error,
                key: const Key('aiProviderEditorError'),
                style: TextStyle(color: colors.danger, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('aiProviderEditorCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('aiProviderEditorSubmit'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _field({
    required Key fieldKey,
    required String label,
    required String hint,
    required TextEditingController controller,
  }) => TextField(
    key: fieldKey,
    controller: controller,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(
        color: context.lexiColors.tertiaryLabel,
        fontSize: 13,
      ),
    ),
  );

  Widget _secretField() => TextField(
    key: const Key('aiProviderEditorApiKey'),
    controller: _apiKey,
    obscureText: _obscured,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: 'API Key',
      suffixIcon: IconButton(
        key: const Key('aiProviderEditorRevealApiKey'),
        tooltip: _obscured ? '显示' : '隐藏',
        icon: Icon(
          _obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          size: 18,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    ),
  );

  void _submit() {
    final id = _id.text.trim();
    final baseUrl = normalizeBaseUrl(_baseUrl.text);
    final apiKey = _apiKey.text.trim();
    final error = _validate(id: id, baseUrl: baseUrl, apiKey: apiKey);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final existing = widget.provider;
    Navigator.of(context).pop(
      LlmProviderConfig(
        id: id,
        name: _name.text.trim(),
        apiType: _apiType,
        baseUrl: baseUrl,
        apiKey: apiKey,
        // 编辑时保留已选模型：模型不在这个对话框里改，误清空会让用户
        // 不得不重新拉一次 `/models`。
        models: existing?.models ?? const <String>[],
        defaultModel: existing?.defaultModel ?? '',
      ),
    );
  }

  /// 校验三项必填与 ID 唯一性。
  ///
  /// 判据与 [LlmProviderConfig.isUsable] 对齐（接口地址与 Key 必须都有），
  /// 界面上提前拦住与「保存了却发不出请求」是同一件事。
  String? _validate({
    required String id,
    required String baseUrl,
    required String apiKey,
  }) {
    if (id.isEmpty) return 'ID 不能为空，它会被 AI 配置引用。';
    final originalId = widget.provider?.id;
    if (id != originalId && widget.takenIds.contains(id)) {
      return 'ID「$id」已被另一个 Provider 占用。';
    }
    if (baseUrl.isEmpty) return '接口地址不能为空，例如 https://api.openai.com/v1';
    if (apiKey.isEmpty) return 'API Key 不能为空。';
    return null;
  }
}

/// 接口协议的中文名。
String apiTypeLabel(LlmApiType apiType) => switch (apiType) {
  LlmApiType.openai => 'OpenAI 兼容',
  LlmApiType.anthropic => 'Anthropic',
};

/// 按协议给出接口地址示例。
///
/// 末尾的 `/v1` 是最容易漏的一段——漏了会拿到 200 + HTML，
/// 而旧版的前端没法区分「返回了」和「返回的是模型响应」。
String baseUrlHint(LlmApiType apiType) => switch (apiType) {
  LlmApiType.openai => 'https://api.openai.com/v1',
  LlmApiType.anthropic => 'https://api.anthropic.com/v1',
};
