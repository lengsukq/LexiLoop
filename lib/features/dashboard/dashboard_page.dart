/// 首页「今日」。
///
/// P0 阶段此页展示地基自检：主题色板、玻璃层级、平台能力是否按预期生效。
/// 后续阶段（P3）会替换为真实的每日学习概览。
///
/// 这里刻意不放任何假数据——旧版 `import/page.tsx` 写死 `value={75}` 的
/// 假进度条是明确的负面示范（见 CLEAN_CODE_BASELINE.md）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 首页。
class DashboardPage extends StatelessWidget {
  /// 创建首页。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: <Widget>[
            Text(
              '今日',
              style: TextStyle(
                color: colors.label,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'LexiLoop 词环 · 纯本地',
              style: TextStyle(color: colors.secondaryLabel, fontSize: 14),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('P0 地基自检'),
            const SizedBox(height: 10),
            const _PlatformCard(),
            const SizedBox(height: 10),
            const _GlassShowcaseCard(),
            const SizedBox(height: 10),
            const _PaletteCard(),
            const SizedBox(height: 24),
            const _SectionTitle('后续阶段'),
            const SizedBox(height: 10),
            const _RoadmapCard(),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Text(
      text,
      style: TextStyle(
        color: colors.secondaryLabel,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final platformName = PlatformCaps.isDesktop ? 'macOS' : 'Android';

    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.devices_rounded, size: 17, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                '运行平台：$platformName',
                style: TextStyle(
                  color: colors.label,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _StatusRow(
            label: 'TTS 落盘缓存',
            value: PlatformCaps.supportsTtsFileSynthesis ? '支持' : '不支持',
            ok: PlatformCaps.supportsTtsFileSynthesis,
          ),
          _StatusRow(
            label: '需引导安装语音包',
            value: PlatformCaps.requiresVoicePackSetup ? '需要' : '不需要',
            ok: !PlatformCaps.requiresVoicePackSetup,
          ),
          _StatusRow(
            label: '模糊降级',
            value: PlatformCaps.needsBlurDowngrade ? '已启用' : '未启用',
            ok: true,
          ),
          _StatusRow(
            label: '布局形态',
            value: MediaQuery.sizeOf(context).width >= sidebarBreakpoint
                ? '侧边栏'
                : '底部 Tab',
            ok: true,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const new({required this.label, required this.value, required this.ok});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                ok ? Icons.check_circle_rounded : Icons.info_rounded,
                size: 13,
                color: ok ? colors.success : colors.warning,
              ),
              const SizedBox(width: 5),
              Text(
                value,
                style: TextStyle(
                  color: colors.label,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassShowcaseCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.blur_on_rounded, size: 17, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                '液态玻璃层级',
                style: TextStyle(
                  color: colors.label,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final level in GlassLevel.values) ...<Widget>[
            LiquidGlass(
              level: level,
              borderRadius: BorderRadius.circular(LexiRadius.md),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      level.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.label,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'blur ${level.blurSigma.toInt()}'
                      ' · sat ${level.saturation}',
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: colors.tertiaryLabel,
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (level != GlassLevel.values.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final swatches = <String, Color>{
      'accent': colors.accent,
      'danger': colors.danger,
      'success': colors.success,
      'warning': colors.warning,
      'purple': colors.purple,
      'label': colors.label,
      'secondary': colors.secondaryLabel,
      'border': colors.borderStrong,
    };

    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.palette_rounded, size: 17, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                '语义色板',
                style: TextStyle(
                  color: colors.label,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final entry in swatches.entries)
                Column(
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: entry.value,
                        borderRadius: BorderRadius.circular(LexiRadius.sm),
                        border: Border.all(color: colors.borderDefault),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.key,
                      style: TextStyle(
                        color: colors.tertiaryLabel,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoadmapCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    const stages = <(String, String)>[
      ('P1', 'JSON 备份导入 / CSV 导入'),
      ('P2', 'FSRS、判题、错词、熟练度、学习队列'),
      ('P3', '词条列表与详情、统计图表'),
      ('P4', '词典 provider、BYOK AI 初始化'),
      ('P5', '游戏、配对、音标训练'),
      ('P6', '液态玻璃精修、TTS 双端校准、打包'),
    ];

    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final (stage, description) in stages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stage,
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      description,
                      style: TextStyle(
                        color: colors.secondaryLabel,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
