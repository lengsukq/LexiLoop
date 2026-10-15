/// 导航目的地与页面的对应关系守卫。
///
/// **为什么需要它**：`AppDestination.path` 是字符串，编译器无法保证
/// 每个目的地都在 `pageForDestination` 里有分支。旧版就吃过这个亏——
/// 一个标注「后续阶段实现」的占位组件被当成已完成页面用了很久，点进去
/// 只能看到「此页面将在后续阶段实现」。
///
/// 这里遍历 [appDestinations] 逐个构造页面：少一个分支，测试立刻红。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';

void main() {
  test('每个导航目的地都能构造出页面', () {
    for (final destination in appDestinations) {
      expect(
        () => pageForDestination(destination),
        returnsNormally,
        reason: '目的地 ${destination.path}（${destination.label}）没有对应页面',
      );
    }
  });

  test('未知路径抛 StateError，而不是渲染一个能正常打开的空页面', () {
    expect(
      () => pageForDestination(
        AppDestination(
          path: '/does-not-exist',
          label: '不存在',
          icon: appDestinations.first.icon,
          shortcut: 99,
        ),
      ),
      throwsStateError,
    );
  });

  test('学习页在没有 mode 参数时兜底到每日综合', () {
    final study = appDestinations.firstWhere(
      (destination) => destination.path == '/study',
    );

    expect(() => pageForDestination(study), returnsNormally);
    expect(
      () => pageForDestination(study, studyModeWire: 'NOT_A_MODE'),
      returnsNormally,
      reason: '拼错的 mode 必须兜底：裸 /study 与旧书签都落在这里',
    );
  });
}
