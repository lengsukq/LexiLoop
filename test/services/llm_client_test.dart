/// LLM 客户端测试：三层降级、超时、截断、鉴权失败、结构化输出与模型列表。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/services/llm/llm_client.dart';
import 'package:lexiloop/services/llm/llm_config.dart';

import '../data/dictionary/fake_http_fetcher.dart';

/// OpenAI 兼容的成功响应。
String openAiBody(String text, {String finishReason = 'stop'}) =>
    jsonEncode(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'content': text},
          'finish_reason': finishReason,
        },
      ],
      'usage': <String, Object?>{'prompt_tokens': 10, 'completion_tokens': 20},
    });

/// Anthropic 的成功响应。
String anthropicBody(String text, {String stopReason = 'end_turn'}) =>
    jsonEncode(<String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
      'usage': <String, Object?>{'input_tokens': 5, 'output_tokens': 6},
      'stop_reason': stopReason,
    });

/// 构造一份含主模型、备用模型与备用 provider 的 LLM 配置。
LlmConfig llmConfig({
  String retryModel = 'm2',
  String retryProviderId = 'p2',
  int retryCount = 1,
  bool thinkingEnabled = false,
  String reasoningEffort = '',
}) => llmConfigFromRaw(<String, Object?>{
  'providers': <Object?>[
    <String, Object?>{
      'id': 'p1',
      'name': '主',
      'apiType': 'openai',
      'baseUrl': 'https://a.example/v1',
      'apiKey': 'k1',
    },
    <String, Object?>{
      'id': 'p2',
      'name': '备',
      'apiType': 'anthropic',
      'baseUrl': 'https://b.example',
      'apiKey': 'k2',
    },
  ],
  'ai': <String, Object?>{
    'enabled': true,
    'providerId': 'p1',
    'model': 'm1',
    'retryModel': retryModel,
    'retryProviderId': retryProviderId,
    'aiRetryCount': retryCount,
    'thinkingEnabled': thinkingEnabled,
    'reasoningEffort': reasoningEffort,
  },
});

Map<String, Object?> bodyAt(FakeHttpFetcher fetcher, int index) =>
    (jsonDecode(fetcher.bodies[index]!) as Map).cast<String, Object?>();

void main() {
  group('三层降级', () {
    test('主模型 → 同 provider 备用模型 → 备用 provider', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        const HttpFetchResponse(statusCode: 503, body: 'unavailable'),
        const HttpFetchResponse(statusCode: 429, body: 'slow down'),
        HttpFetchResponse(statusCode: 200, body: anthropicBody('好')),
      ]);
      final client = LlmClient(fetcher, llmConfig());

      final completion = await client.complete(
        const LlmCallOptions(system: 's', user: 'u'),
      );

      expect(completion.text, '好');
      expect(fetcher.calls, hasLength(3));
      expect(fetcher.calls[0], contains('a.example/v1/chat/completions'));
      expect(fetcher.calls[1], contains('a.example/v1/chat/completions'));
      expect(fetcher.calls[2], contains('b.example/messages'));
      expect(bodyAt(fetcher, 0)['model'], 'm1');
      expect(bodyAt(fetcher, 1)['model'], 'm2');
      expect(bodyAt(fetcher, 2)['model'], 'm2');
      expect(completion.providerId, 'p2');
      expect(completion.inputTokens, 5);
    });

    test('超时算瞬时错误，会触发降级', () async {
      var index = 0;
      final fetcher = FakeHttpFetcher((url, body) async {
        index += 1;
        if (index == 1) throw const HttpFailure(HttpFailureKind.timeout);
        // 第二个目标是同一 provider 的备用模型，协议仍是 OpenAI。
        return HttpFetchResponse(statusCode: 200, body: openAiBody('降级成功'));
      });
      final completion = await LlmClient(
        fetcher,
        llmConfig(),
      ).complete(const LlmCallOptions(system: 's', user: 'u'));
      expect(completion.text, '降级成功');
      expect(fetcher.calls, hasLength(2));
    });

    test('全部目标超时后抛 aiTimeout', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async => throw const HttpFailure(HttpFailureKind.timeout),
      );
      await expectLater(
        LlmClient(
          fetcher,
          llmConfig(retryProviderId: ''),
        ).complete(const LlmCallOptions(system: 's', user: 'u')),
        throwsA(
          isA<ExternalServiceError>()
              .having((error) => error.code, 'code', AppErrorCode.aiTimeout)
              .having((error) => error.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('鉴权失败不降级', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        const HttpFetchResponse(statusCode: 401, body: 'unauthorized'),
      ]);
      await expectLater(
        LlmClient(
          fetcher,
          llmConfig(),
        ).complete(const LlmCallOptions(system: 's', user: 'u')),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.isTransient,
            'isTransient',
            isFalse,
          ),
        ),
      );
      expect(fetcher.calls, hasLength(1));
    });

    test('aiRetryCount 决定候选链重放遍数', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        const HttpFetchResponse(statusCode: 503, body: 'x'),
        const HttpFetchResponse(statusCode: 503, body: 'x'),
        const HttpFetchResponse(statusCode: 503, body: 'x'),
        const HttpFetchResponse(statusCode: 503, body: 'x'),
      ]);
      await expectLater(
        LlmClient(
          fetcher,
          llmConfig(retryCount: 2),
        ).complete(const LlmCallOptions(system: 's', user: 'u')),
        throwsA(isA<ExternalServiceError>()),
      );
      // 2 遍 × 3 个目标。
      expect(fetcher.calls, hasLength(6));
    });
  });

  group('输出截断', () {
    test('finish_reason 为 length 时抛 aiOutputTruncated 且不降级', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        HttpFetchResponse(
          statusCode: 200,
          body: openAiBody('{"a":', finishReason: 'length'),
        ),
      ]);
      await expectLater(
        LlmClient(
          fetcher,
          llmConfig(),
        ).complete(const LlmCallOptions(system: 's', user: 'u')),
        throwsA(
          isA<ExternalServiceError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.aiOutputTruncated,
              )
              .having((error) => error.isTransient, 'isTransient', isFalse),
        ),
      );
      expect(fetcher.calls, hasLength(1));
    });
  });

  group('结构化输出', () {
    test('completeJson 解析出 JSON 对象', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        HttpFetchResponse(
          statusCode: 200,
          body: openAiBody('```json\n{"term":"hello"}\n```'),
        ),
      ]);
      final result = await LlmClient(fetcher, llmConfig()).completeJson(
        system: 's',
        user: 'u',
        schema: const <String, Object?>{'type': 'object'},
      );
      expect(result['term'], 'hello');
    });

    test('完全没有 JSON 时抛 aiResponseInvalid', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        HttpFetchResponse(statusCode: 200, body: openAiBody('不是 JSON')),
      ]);
      await expectLater(
        LlmClient(fetcher, llmConfig()).completeJson(
          system: 's',
          user: 'u',
          schema: const <String, Object?>{'type': 'object'},
        ),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiResponseInvalid,
          ),
        ),
      );
    });

    test('JSON 不是对象时抛 aiSchemaInvalid', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        HttpFetchResponse(statusCode: 200, body: openAiBody('[1, 2]')),
      ]);
      await expectLater(
        LlmClient(fetcher, llmConfig()).completeJson(
          system: 's',
          user: 'u',
          schema: const <String, Object?>{'type': 'object'},
        ),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiSchemaInvalid,
          ),
        ),
      );
    });

    test('网关不支持 response_format 时逐档降级到无约束', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        const HttpFetchResponse(statusCode: 400, body: 'unsupported'),
        const HttpFetchResponse(statusCode: 400, body: 'unsupported'),
        HttpFetchResponse(
          statusCode: 200,
          body: openAiBody('{"term":"hello"}'),
        ),
      ]);
      final result = await LlmClient(fetcher, llmConfig()).completeJson(
        system: 's',
        user: 'u',
        schema: const <String, Object?>{'type': 'object'},
      );
      expect(result['term'], 'hello');
      expect(fetcher.calls, hasLength(3));
      expect(bodyAt(fetcher, 0)['response_format'], isNotNull);
      expect(bodyAt(fetcher, 2)['response_format'], isNull);
    });
  });

  group('思考预算', () {
    test('Anthropic 带 thinking 且温度为 1', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        HttpFetchResponse(statusCode: 200, body: anthropicBody('ok')),
      ]);
      final config = llmConfigFromRaw(<String, Object?>{
        'providers': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'apiType': 'anthropic',
            'baseUrl': 'https://a.example',
            'apiKey': 'k1',
          },
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'claude',
        },
      });
      await LlmClient(fetcher, config).complete(
        const LlmCallOptions(
          system: 's',
          user: 'u',
          thinkingEnabled: true,
          thinkingBudgetTokens: 2048,
          maxOutputTokens: 1000,
        ),
      );
      final body = bodyAt(fetcher, 0);
      expect(body['temperature'], 1);
      expect(body['thinking'], containsPair('budget_tokens', 2048));
      // 思考 token 与正文共用预算，必须留出余量。
      expect(body['max_tokens'], greaterThan(1000));
    });

    test('OpenAI 推理模型用 reasoning_effort 而不是 temperature', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        HttpFetchResponse(statusCode: 200, body: openAiBody('ok')),
      ]);
      final config = llmConfigFromRaw(<String, Object?>{
        'providers': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'apiType': 'openai',
            'baseUrl': 'https://a.example/v1',
            'apiKey': 'k1',
          },
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'gpt-5-mini',
          'thinkingEnabled': true,
          'reasoningEffort': 'medium',
        },
      });
      await LlmClient(fetcher, config).complete(
        const LlmCallOptions(
          system: 's',
          user: 'u',
          thinkingEnabled: true,
          reasoningEffort: 'medium',
        ),
      );
      final body = bodyAt(fetcher, 0);
      expect(body['reasoning_effort'], 'medium');
      expect(body['max_completion_tokens'], isNotNull);
      expect(body.containsKey('temperature'), isFalse);
    });
  });

  group('模型列表', () {
    test('解析 data[].id', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[
        const HttpFetchResponse(
          statusCode: 200,
          body: '{"data":[{"id":"m1"},{"id":"m2"}]}',
        ),
      ]);
      final config = llmConfig();
      final models = await LlmClient(
        fetcher,
        config,
      ).listModels(config.providers.first);
      expect(models, <String>['m1', 'm2']);
      expect(fetcher.calls.single, contains('a.example/v1/models'));
    });

    test('缺少 Base URL 或 Key 时抛配置错误', () async {
      final fetcher = sequencedFetcher(<HttpFetchResponse>[]);
      const provider = LlmProviderConfig(
        id: 'p',
        name: 'p',
        apiType: LlmApiType.openai,
        baseUrl: '',
        apiKey: '',
      );
      await expectLater(
        LlmClient(fetcher, llmConfig()).listModels(provider),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiConfigIncomplete,
          ),
        ),
      );
    });
  });

  group('配置解析', () {
    test('未启用或配置不完整时 resolveTargets 为空', () {
      final config = llmConfigFromRaw(<String, Object?>{
        'providers': <Object?>[],
        'ai': <String, Object?>{
          'enabled': false,
          'providerId': 'p1',
          'model': 'm',
        },
      });
      expect(
        LlmClient(
          sequencedFetcher(<HttpFetchResponse>[]),
          config,
        ).resolveTargets(),
        isEmpty,
      );
      expect(config.isUsable, isFalse);
    });

    test('取值被夹到合法区间', () {
      final config = llmConfigFromRaw(<String, Object?>{
        'providers': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'apiType': 'openai',
            'baseUrl': 'https://a.example/v1/',
            'apiKey': 'k',
          },
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'm',
          'temperature': 5,
          'timeoutMs': 1,
          'thinkingBudgetTokens': 1,
          'aiRetryCount': 99,
        },
      });
      // 尾部斜杠被去掉，避免拼出 `//chat/completions`。
      expect(config.providers.first.baseUrl, 'https://a.example/v1');
      expect(config.ai.temperature, 1);
      expect(config.ai.timeoutMs, 5000);
      expect(config.ai.thinkingBudgetTokens, 1024);
      expect(config.ai.retryCount, 5);
    });
  });
}
