/// 四档评级的间隔预览文案。
///
/// 服务层的 `FsrsIntervalPreview` 只在学习页与评级条之间传递一次：这里把它翻
/// 译成 `ReviewRating → 短文案`，评级条因此不必认识 FSRS 的模型，也不必知道
/// 「几天」该怎么写。旧版把这段换算内联在 `study-client.tsx` 的按钮 JSX 里。
library;

import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';

/// 把服务返回的四条预览翻译成评级按钮下方的短文案。
///
/// 预览可能为空（尚未取到或取失败），此时返回空表，按钮显示占位符而不是
/// 假装有一个间隔。
Map<ReviewRating, String> studyIntervalTexts(
  List<FsrsIntervalPreview> previews,
) => <ReviewRating, String>{
  for (final preview in previews)
    preview.rating: studyIntervalText(preview.scheduledDays),
};
