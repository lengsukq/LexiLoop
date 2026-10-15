/// 「测试连接」与「从 Models 接口获取」的联网动作。
///
/// 对应旧版 `/api/settings/test-provider` 与 `/api/settings/models`。
/// 区别在于旧版要绕到自己的服务器再回来（API Key 因此要过一趟后端），
/// 本版直接用 [HttpFetcher] 请求 provider——设置页在设备上，没有理由
/// 把 Key 发给自己的服务器。测试里注入假 fetcher 即可完全离线。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/dictionary_constants.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/services/llm/llm_client.dart';
import 'package:lexiloop/services/llm/llm_config.dart';

/// 探测请求的输出上限：只需要证明「能连通」，多要 token 只是浪费配额。
const int aiProbeMaxOutputTokens = 10;

/// 探测请求的超时沿用 [modelListTimeoutMs]，与旧版两个接口的 15 秒一致。
const int aiProbeTimeoutMs = modelListTimeoutMs;

/// 探测用的系统提示词。
const String aiProbeSystemPrompt = '你是一个连通性测试助手，请只回复一个字。';

/// 探测用的用户提示词（与旧版相同的最短输入）。
const String aiProbeUserPrompt = 'Hi';

/// 一次探测的结果。
class AiProbeResult {
  /// 以成败与面向用户的文案构造。
  const new({required this.success, required this.message});

  /// 是否成功。
  final bool success;

  /// 面向用户的文案（成功时含模型与耗时，失败时含原因）。
  final String message;
}

/// 拉取模型列表的结果。
class AiModelsResult {
  /// 以模型列表与面向用户的文案构造。
  const new({required this.models, required this.message});

  /// 读到的模型名。
  final List<String> models;

  /// 面向用户的文案。
  final String message;
}

/// 探测失败，文案已面向用户。
///
/// 独立于 [AppError]：这里的失败原因要拼上「请检查接口地址与 API Key」
/// 这类下一步指引，而 [AppError.message] 是给通用路径用的。
class AiProbeFailure implements Exception {
  /// 以文案构造。
  const new(this.message);

  /// 面向用户的文案。
  final String message;
}

/// 对单个 provider 发一次最小请求，返回模型与耗时。
///
/// **为什么临时造一份 [LlmConfig]**：[LlmClient.complete] 按 `ai.providerId`
/// 与 `ai.model` 选请求目标，而这里要测的是列表里任意一个 provider，
/// 与当前主配置无关。
///
/// 不抛异常：结果只有两种（可用 / 不可用），界面把文案显示出来即可。
Future<AiProbeResult> probeProviderConnection({
  required HttpFetcher fetcher,
  required LlmProviderConfig provider,
  required String model,
}) async {
  if (!provider.isUsable) {
    return const AiProbeResult(
      success: false,
      message: '接口地址或 API Key 为空，请先填写这两项。',
    );
  }
  final target = model.trim();
  if (target.isEmpty) {
    return const AiProbeResult(
      success: false,
      message: '请先通过 Models 接口获取或添加一个模型。',
    );
  }
  final client = LlmClient(fetcher, _probeConfig(provider, target));
  final stopwatch = Stopwatch()..start();
  try {
    final completion = await client.complete(
      const LlmCallOptions(
        system: aiProbeSystemPrompt,
        user: aiProbeUserPrompt,
        maxOutputTokens: aiProbeMaxOutputTokens,
      ),
    );
    stopwatch.stop();
    return AiProbeResult(
      success: true,
      message: '${completion.model} 响应正常（${stopwatch.elapsedMilliseconds} ms）',
    );
  } on AppError catch (error) {
    stopwatch.stop();
    return AiProbeResult(success: false, message: _failureMessage(error));
  } on Exception catch (error) {
    stopwatch.stop();
    return AiProbeResult(success: false, message: '连接失败：$error');
  }
}

/// 读取 provider 的模型列表（`GET {baseUrl}/models`）。
///
/// 失败时抛 [AiProbeFailure]：调用方要区分「拿到列表」与「拿不到」，
/// 拿不到时必须保留原有的模型配置，不能顺手清空。
Future<AiModelsResult> fetchProviderModels({
  required HttpFetcher fetcher,
  required LlmProviderConfig provider,
  required LlmConfig config,
}) async {
  try {
    final models = await LlmClient(fetcher, config).listModels(provider);
    if (models.isEmpty) {
      throw const AiProbeFailure('Models 接口没有返回可识别的模型列表。');
    }
    return AiModelsResult(
      models: models,
      message: '已读取 ${models.length} 个模型，请选择后应用。',
    );
  } on AiProbeFailure {
    rethrow;
  } on AppError catch (error) {
    throw AiProbeFailure(_failureMessage(error));
  } on Exception catch (error) {
    throw AiProbeFailure('读取模型失败：$error');
  }
}

LlmConfig _probeConfig(LlmProviderConfig provider, String model) => LlmConfig(
  providers: <LlmProviderConfig>[provider],
  ai: LlmAiConfig(
    enabled: true,
    providerId: provider.id,
    model: model,
    temperature: minLlmTemperature,
    maxOutputTokens: aiProbeMaxOutputTokens,
    timeoutMs: aiProbeTimeoutMs,
  ),
);

/// 只展示 [AppError] 的用户文案，细节（可能含 Key 片段）一律不展示。
String _failureMessage(AppError error) =>
    '${error.message}请检查接口地址、API Key 与模型名。';
