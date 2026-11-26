/// 枚举列与数据库大写标识之间的转换。
///
/// 旧版把枚举存为大写下划线字符串（如 `PENDING`、`EN_TO_ZH`），
/// 这里保持一致，使 JSON 备份导入可以**直接映射**而无需转换表。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/domain/enums.dart';

/// 把 [WireEnum] 与数据库中的大写标识互转。
///
/// 反查失败时抛 [ArgumentError] 而非静默返回默认值——
/// 旧版多处「解析失败就吞掉」，导致脏数据无声无息地污染统计。
class WireEnumConverter<T extends WireEnum> extends TypeConverter<T, String> {
  /// 以该枚举的全部取值构造。
  const new(this.values);

  /// 该枚举的全部取值，用于反查。
  final List<T> values;

  @override
  T fromSql(String fromDb) {
    final value = wireLookup(values, fromDb);
    if (value == null) {
      throw ArgumentError.value(
        fromDb,
        'fromDb',
        '不是合法的 ${values.first.runtimeType} 标识',
      );
    }
    return value;
  }

  @override
  String toSql(T value) => value.wire;
}
