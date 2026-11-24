/// 发音优先级链、旧配置迁移和学习选项密度往返单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/study/study_texts.dart';

void main() {
  test('默认配置启用有道 → Edge → 系统三级优先级链和简洁选项', () {
    final settings = appSettingsFromRaw(const <String, Object?>{}).playback;
    expect(settings.speechChain, defaultSpeechChain);
    expect(settings.enabledSpeechSources, <SpeechSource>[
      SpeechSource.youdao,
      SpeechSource.edge,
      SpeechSource.system,
    ]);
    expect(settings.speechEnabled, isTrue);
    expect(settings.choiceDefinitionStyle, ChoiceDefinitionStyle.compact);
  });

  test('自定义多选与拖动顺序可完整往返', () {
    final raw = <String, Object?>{
      'speechChain': <Map<String, Object?>>[
        <String, Object?>{'source': 'edge', 'enabled': true},
        <String, Object?>{'source': 'system', 'enabled': true},
        <String, Object?>{'source': 'youdao', 'enabled': false},
      ],
      'choiceDefinitionStyle': 'standard',
    };
    final settings = appSettingsFromRaw(raw);
    final restored = appSettingsFromRaw(settings.toStorage()).playback;

    expect(
      restored.speechChain.map((e) => (e.source, e.enabled)).toList(),
      <(SpeechSource, bool)>[
        (SpeechSource.edge, true),
        (SpeechSource.system, true),
        (SpeechSource.youdao, false),
      ],
    );
    expect(restored.enabledSpeechSources, <SpeechSource>[
      SpeechSource.edge,
      SpeechSource.system,
    ]);
    expect(restored.choiceDefinitionStyle, ChoiceDefinitionStyle.standard);
  });

  group('老配置平滑迁移', () {
    test('旧版 Edge 直连且关闭回落 → 仅启用 Edge', () {
      final playback = appSettingsFromRaw(const <String, Object?>{
        'speechSource': 'edge',
        'speechFallbackEnabled': false,
      }).playback;
      expect(playback.enabledSpeechSources, <SpeechSource>[SpeechSource.edge]);
    });

    test('已移除的 Next.js online 配置平滑迁移为直连 Edge 优先', () {
      final playback = appSettingsFromRaw(const <String, Object?>{
        'speechSource': 'online',
        'speechFallbackEnabled': true,
      }).playback;
      expect(playback.enabledSpeechSources, <SpeechSource>[
        SpeechSource.edge,
        SpeechSource.youdao,
        SpeechSource.system,
      ]);
    });

    test('旧版关闭发音 → 全部引擎关闭', () {
      final playback = appSettingsFromRaw(const <String, Object?>{
        'speechSource': 'off',
      }).playback;
      expect(playback.speechEnabled, isFalse);
      expect(playback.enabledSpeechSources, isEmpty);
    });

    test('旧版关闭真人录音 → 仅启用设备系统朗读', () {
      final playback = appSettingsFromRaw(const <String, Object?>{
        'humanAudioEnabled': false,
      }).playback;
      expect(playback.enabledSpeechSources, <SpeechSource>[
        SpeechSource.system,
      ]);
    });
  });

  test('简洁释义不改变提交用的完整选项文本', () {
    const answer = '大多数；多数票；成年法定年龄；绝大多数';
    expect(
      studyChoicePreview(answer, ChoiceDefinitionStyle.compact),
      '大多数；多数票…',
    );
    expect(studyChoicePreview(answer, ChoiceDefinitionStyle.full), answer);
  });

  test('离线语音磁盘缓存开关与上限支持持久化往返和边界夹取', () {
    final defaults = appSettingsFromRaw(const <String, Object?>{}).playback;
    expect(defaults.offlineAudioCacheEnabled, isTrue);
    expect(defaults.audioCacheMaxSizeMb, 200);
    expect(defaults.audioCacheMaxBytes, 200 * 1024 * 1024);

    final custom = appSettingsFromRaw(const <String, Object?>{
      'offlineAudioCacheEnabled': false,
      'audioCacheMaxSizeMb': 500,
    });
    final restored = appSettingsFromRaw(custom.toStorage()).playback;
    expect(restored.offlineAudioCacheEnabled, isFalse);
    expect(restored.audioCacheMaxSizeMb, 500);

    final unlimited = appSettingsFromRaw(const <String, Object?>{
      'audioCacheMaxSizeMb': 0,
    }).playback;
    expect(unlimited.audioCacheMaxBytes, 0);
  });
}
