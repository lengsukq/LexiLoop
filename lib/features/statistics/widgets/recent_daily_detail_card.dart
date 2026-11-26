/// 「最近学习明细」卡片。
///
/// 对应旧版 `app/(main)/statistics/page.tsx:51` 的最后一张卡片：数据取
/// `daily` 倒序（最新在前）并只取前 30 天，窄屏渲染成一叠小卡片、宽屏渲染成表格。
///
/// **为什么两种形态各写一遍**：旧版用 `sm:hidden` / `hidden sm:block` 同时渲染
/// 两块 DOM，窄屏那块是三列小字（`正确 3` / `正确率 75%` / `有效 2 分钟`），宽屏
/// 那块是带列标题的表格——字段相同但排版与文案都不同，硬塞进一个组件只会让
/// 每个 `Text` 都带一个「窄屏时叫什么」的分支。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/stat_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 最近学习明细。
class RecentDailyDetailCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncStatCard<List<DailyReviewStat>>(
        title: '最近学习明细',
        value: ref.watch(dailyTrendProvider),
        builder: (context, data) => _DetailBody(stats: data),
      );
}

/// 明细主体：截断 + 空态 + 宽窄两态。
class _DetailBody extends StatelessWidget {
  const new({required this.stats});

  /// 当前档位的逐日统计（升序）。
  final List<DailyReviewStat> stats;

  @override
  Widget build(BuildContext context) {
    final recent = stats.reversed
        .take(statisticsDailyDetailLimit)
        .toList(growable: false);
    if (!_hasActivity(recent)) {
      return const EmptyHint(message: '这段时间还没有学习记录');
    }
    return MediaQuery.sizeOf(context).width >= detailTableBreakpoint
        ? _DetailTable(stats: recent)
        : _DetailDayList(stats: recent);
  }
}

/// 这段窗口里是否有任何学习痕迹。
///
/// **与旧版的差异**：旧版无条件渲染 30 行（全是 0 也照渲染），一屏零值既看不出
/// 「最近发生了什么」也容易读成「今天全错了」。这里改成全零时给空态——与同一页
/// 趋势卡的「这段时间还没有复习记录」保持一致。
///
/// 判据是「有作答或有已完成会话」：只要有会话（哪怕没有复习记录）就算有痕迹，
/// 否则「跳过 3 道题」会连同这一天一起消失。
bool _hasActivity(List<DailyReviewStat> stats) =>
    stats.any((stat) => stat.reviewed > 0 || stat.sessions > 0);

/// 正确率的展示文本；当天没有作答时显示 `—`。
///
/// 旧版的 `accuracy` 在无作答时是 `null`，界面显示 `—`。本版
/// [DailyReviewStat.accuracy] 把无作答压成了 0，所以这里必须用 `reviewed == 0`
/// 判空——否则「今天还没开始」会被显示成「今天全错」，比少显示一个数严重得多。
String accuracyText(DailyReviewStat stat) =>
    stat.reviewed == 0 ? '—' : '${formatPercent(stat.accuracy)}%';

/// 当天有效时长的分钟数。
///
/// 用四舍五入而非截断：旧版累加浮点分钟后 `Math.round(item.minutes)`，
/// 截断会让 59.6 分钟显示成 59。
int minutesOf(DailyReviewStat stat) => (stat.durationMs / minuteMs).round();

/// 给文本样式加上等宽数字（旧版的 `num-tabular`）。
///
/// 逐行对齐的数字才能一眼比出「今天比昨天多了多少」；比例字体下
/// `111` 比 `999` 窄，一列数字会看起来是歪的。
TextStyle? tabularFigures(TextStyle? style) => style?.copyWith(
  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
);

/// 窄屏：一天一张小卡片（旧版 `sm:hidden` 那一块）。
class _DetailDayList extends StatelessWidget {
  const new({required this.stats});

  /// 倒序后的明细。
  final List<DailyReviewStat> stats;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final stat in stats)
        Padding(
          padding: const EdgeInsets.only(bottom: dayCardGap),
          child: _DetailDayCard(stat: stat),
        ),
    ],
  );
}

/// 一天的小卡片：日期 + 次数，下面两行三列小字。
class _DetailDayCard extends StatelessWidget {
  const new({required this.stat});

  /// 这一天的统计。
  final DailyReviewStat stat;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final textTheme = Theme.of(context).textTheme;
    return Surface(
      variant: SurfaceVariant.inset,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      padding: const EdgeInsets.all(dayCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  stat.dateKey,
                  style: tabularFigures(
                    textTheme.labelLarge?.copyWith(color: colors.label),
                  ),
                ),
              ),
              Text(
                '${stat.reviewed} 次',
                style: tabularFigures(
                  textTheme.labelLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: dayCardInnerGap),
          _DetailLine(
            first: _DetailCell('正确 ${stat.correct}'),
            second: _DetailCell('正确率 ${accuracyText(stat)}'),
            third: _DetailCell('有效 ${minutesOf(stat)} 分钟'),
          ),
          _DetailLine(
            first: _DetailCell('忘记 ${stat.again}', colors.danger),
            second: _DetailCell('跳过 ${stat.skipped}', colors.warning),
            third: _DetailCell('会话 ${stat.sessions}'),
          ),
        ],
      ),
    );
  }
}

/// 窄屏卡片里的一行三列小字。
class _DetailLine extends StatelessWidget {
  const new({required this.first, required this.second, required this.third});

  /// 第一列。
  final _DetailCell first;

  /// 第二列。
  final _DetailCell second;

  /// 第三列。
  final _DetailCell third;

  @override
  Widget build(BuildContext context) {
    final style = tabularFigures(
      Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: context.lexiColors.secondaryLabel),
    );
    return Row(
      children: <Widget>[
        for (final cell in <_DetailCell>[first, second, third])
          Expanded(
            child: Text(
              cell.label,
              style: cell.color == null
                  ? style
                  : style?.copyWith(color: cell.color),
            ),
          ),
      ],
    );
  }
}

/// 窄屏卡片里的一个单元格。
class _DetailCell {
  /// 以文案与可选颜色构造。
  const new(this.label, [this.color]);

  /// 文案。
  final String label;

  /// 文案颜色；为空时用次级文本色。
  final Color? color;
}

/// 宽屏：表格形态（旧版 `hidden sm:block` 那一块）。
class _DetailTable extends StatelessWidget {
  const new({required this.stats});

  /// 倒序后的明细。
  final List<DailyReviewStat> stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // 装不下时横向滚动，而不是把列压到换行——旧版同一处是
      // `overflow-auto` + `min-w-[640px]`。
      final available = constraints.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: available < detailTableMinWidth
              ? detailTableMinWidth
              : available,
          child: _buildTable(context),
        ),
      );
    },
  );

  Widget _buildTable(BuildContext context) {
    final colors = context.lexiColors;
    return Table(
      columnWidths: detailColumnWidths(),
      border: TableBorder(
        horizontalInside: BorderSide(color: colors.borderSubtle),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        _headerRow(context, colors),
        for (final stat in stats) _dataRow(context, colors, stat),
      ],
    );
  }
}

/// 表格列宽：日期列吃掉剩余宽度，其余列按内容自适应。
///
/// 除首列外都用 [IntrinsicColumnWidth]：旧版的 `<table>` 是 `table-layout: auto`，
/// 「有效做题时长」这类表头比数字宽得多的列由浏览器撑开；写死宽度会把它压成
/// 省略号或折行。
Map<int, TableColumnWidth> detailColumnWidths() => <int, TableColumnWidth>{
  0: const FlexColumnWidth(),
  for (var index = 1; index < detailColumnTitles.length; index += 1)
    index: const IntrinsicColumnWidth(),
};

/// 表头行。
///
/// 带一层浅底（旧版 `<thead>` 的 `bg-white/60`）：表格有 30 行时，
/// 表头与数据之间只靠一条分隔线区分太弱。
TableRow _headerRow(BuildContext context, LexiColors colors) {
  final style = Theme.of(context).textTheme.labelSmall
      ?.copyWith(color: colors.secondaryLabel, fontWeight: FontWeight.w600);
  return TableRow(
    decoration: BoxDecoration(color: colors.fill),
    children: <Widget>[
      for (final title in detailColumnTitles) _cell(title, style),
    ],
  );
}

/// 数据行。
TableRow _dataRow(
  BuildContext context,
  LexiColors colors,
  DailyReviewStat stat,
) {
  final style = tabularFigures(
    Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.label),
  );
  final dateStyle = style?.copyWith(fontWeight: FontWeight.w500);
  return TableRow(
    children: <Widget>[
      _cell(stat.dateKey, dateStyle),
      _cell('${stat.reviewed}', style),
      _cell('${stat.correct}', style, color: colors.success),
      _cell(accuracyText(stat), style),
      _cell('${stat.again}', style, color: colors.danger),
      _cell('${stat.skipped}', style, color: colors.warning),
      _cell('${minutesOf(stat)} 分钟', style),
      _cell('${stat.sessions}', style),
    ],
  );
}

/// 一个表格单元格。
Widget _cell(String text, TextStyle? style, {Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: tableCellPaddingH,
    vertical: tableCellPaddingV,
  ),
  child: Text(
    text,
    style: color == null ? style : style?.copyWith(color: color),
  ),
);

/// 表格列标题，顺序与旧版 `statistics/page.tsx:51` 的 `<thead>` 逐列一致。
const List<String> detailColumnTitles = <String>[
  '日期',
  '复习',
  '正确',
  '正确率',
  '忘记',
  '稍后再学',
  '有效做题时长',
  '会话',
];

/// 明细切到表格形态的断点。
///
/// 640 是旧版 Tailwind 的 `sm:` 断点（`sm:hidden` / `hidden sm:block`）。
/// **按视口宽度判断而不是卡片可用宽度**：`sm:` 本来就是视口级媒体查询，
/// 按容器宽度判会让同一个窗口在有无侧边栏时呈现不同形态。
const double detailTableBreakpoint = 640;

/// 表格的最小宽度（旧版同一处的 `min-w-[640px]`）。
const double detailTableMinWidth = 640;

/// 表格单元格的水平内边距（旧版 `p-3`）。
const double tableCellPaddingH = 12;

/// 表格单元格的垂直内边距。
const double tableCellPaddingV = 10;

/// 窄屏小卡片的内边距（旧版 `p-3`）。
const double dayCardPadding = 12;

/// 窄屏小卡片里标题行与指标行的间距。
const double dayCardInnerGap = 8;

/// 窄屏小卡片之间的间距。
const double dayCardGap = 8;
