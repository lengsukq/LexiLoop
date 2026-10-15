/// 平台能力卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 平台能力卡片：把 `PlatformCaps` 的判定结果直接摆出来。
///
/// 保留自 P0 的自检页：双端差异（TTS 落盘、语音包引导、模糊降级）是
/// 最容易「在 A 端正常、在 B 端静默失效」的部分，摆在首页比藏在日志里可靠。
class PlatformCapabilityCard extends StatelessWidget {
  /// 创建平台能力卡片。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final platformName = switch ((
      PlatformCaps.isWeb,
      PlatformCaps.isDesktop,
      PlatformCaps.isMobile,
    )) {
      // 三态而不是「是桌面就 macOS、否则 Android」：Web 上两个都是 false，
      // 二元判断会把浏览器里的自检卡片写成「运行平台：Android」。
      (true, _, _) => 'Web（浏览器）',
      (_, true, _) => 'macOS',
      (_, _, true) => 'Android',
      _ => '未知平台',
    };

    return SectionCard(
      title: '平台能力',
      icon: Icons.devices_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '运行平台：$platformName',
            style: LexiType.callout.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s10),
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
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
          ),
          const SizedBox(width: LexiSpace.s8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                ok ? Icons.check_circle_rounded : Icons.info_rounded,
                size: 13,
                color: ok ? colors.success : colors.warning,
              ),
              const SizedBox(width: LexiSpace.s6),
              Text(
                value,
                style: LexiType.body.copyWith(
                  color: colors.label,
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
