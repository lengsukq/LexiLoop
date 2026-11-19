/// 发音来源和学习选项密度从设置表完整往返且旧配置自动兼容。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/study/study_texts.dart';

void main() {
  test('老设置默认选择自动语音和简洁选项', () {
    final settings = appSettingsFromRaw(const <String, Object?>{}).playback;
    expect(settings.speechSource, SpeechSource.automatic);
    expect(settings.speechFallbackEnabled, isTrue);
    expect(settings.choiceDefinitionStyle, ChoiceDefinitionStyle.compact);
    expect(settings.onlineTtsBaseUrl, isEmpty);
  });

  test('直连Edge、失败降级、在线地址及释义密度配置可往返', () {
    final settings = appSettingsFromRaw(const <String, Object?>{
      'speechSource': 'edge',
      'speechFallbackEnabled': false,
      'onlineTtsBaseUrl': 'https://voice.example.com',
      'choiceDefinitionStyle': 'standard',
    });
    final restored = appSettingsFromRaw(settings.toStorage()).playback;
    expect(restored.speechSource, SpeechSource.edge);
    expect(restored.speechFallbackEnabled, isFalse);
    expect(restored.onlineTtsBaseUrl, 'https://voice.example.com');
    expect(restored.choiceDefinitionStyle, ChoiceDefinitionStyle.standard);
  });

  test('简洁释义不改变提交用的完整选项文本', () {
    const answer = '大多数；多数票；成年法定年龄；绝大多数';
    expect(
      studyChoicePreview(answer, ChoiceDefinitionStyle.compact),
      '大多数；多数票…',
    );
    expect(studyChoicePreview(answer, ChoiceDefinitionStyle.full), answer);
  });
}
