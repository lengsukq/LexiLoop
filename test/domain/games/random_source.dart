/// 测试用的确定性随机源。
///
/// 生产代码的随机都通过 `double Function()` 注入，测试因此可以断言
/// 「给定随机序列得到什么结果」，而不是只能断言「结果在集合内」。
library;

/// 依次返回 [values] 的随机源；用尽后从头循环。
///
/// 循环而不是抛错：状态机在打乱选项、分配洞位、生成下落时长时会多次取随机，
/// 测试只关心前几个值；循环让「不关心的地方」保持确定而不是让测试崩掉。
double Function() sequenceRandom(List<double> values) {
  var index = 0;
  return () {
    final value = values[index % values.length];
    index += 1;
    return value;
  };
}

/// 恒定随机源（等价于「不打乱」，便于断言顺序）。
double Function() constantRandom([double value = 0]) =>
    () => value;
