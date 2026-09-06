/// The More destination pane.
///
/// The fourth top-level destination of the validated navigation
/// (Home / Projects / Activity / More). Phase 0 of
/// `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` requires the shell to expose every
/// capability instead of hiding it in a drawer, and requires an embedded
/// Dashboard fallback entry so no capability is blocked while the native UX
/// catches up.
///
/// Two rules drive this file:
///
/// 1. **Never hide a capability.** A surface that is not built yet is listed
///    as `Coming next`, and a surface the server cannot serve is listed as
///    disabled *with a precise reason* — never removed from the list.
/// 2. **Explain, do not crash.** Availability is data, so tests can assert it
///    without pumping a widget, and the pane simply renders it.
library;

import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

/// Whether a More entry can be opened right now, and why not when it cannot.
enum MoreEntryAvailability {
  /// Usable now.
  available,

  /// Native surface not implemented yet; listed so it stays discoverable.
  comingSoon,

  /// The connected Hermes instance cannot serve it (for example: no
  /// reachable dashboard). Disabled with an explanation, never hidden.
  unavailable,
}

/// One row of the More pane.
@immutable
class MoreEntry {
  /// Stable identifier used for routing and tests. Never localized.
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final MoreEntryAvailability availability;

  /// Why the entry is disabled. Required for [MoreEntryAvailability.unavailable]
  /// so the UI can always tell the user what to fix.
  final String? unavailableReason;

  const MoreEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.availability = MoreEntryAvailability.available,
    this.unavailableReason,
  }) : assert(
         availability != MoreEntryAvailability.unavailable ||
             unavailableReason != null,
         'A disabled entry must explain itself',
       );

  bool get isSelectable => availability == MoreEntryAvailability.available;
}

/// A titled group of [MoreEntry] rows.
@immutable
class MoreSection {
  final String title;
  final List<MoreEntry> entries;

  const MoreSection({required this.title, required this.entries});
}

const _dashboardRequired =
    '需要可访问的 Hermes 仪表盘。请检查此连接的主机、端口和凭据。';
const _gatewayAssetsRequired = '需要 Hermes 网关提供服务器端权威的资产索引。';
const _gatewayOrganizationRequired =
    '需要 Hermes 网关提供持久的置顶排序、批量修改和撤销契约。';
const _gatewayAiFilingRequired = '需要 Hermes 网关提供具备纠正能力的归档契约。';

/// Builds the More menu for the current connection.
///
/// [dashboardReachable] gates the surfaces served by the Hermes Dashboard.
/// Local device settings stay reachable regardless, so the user can always
/// repair a broken connection from inside the app.
List<MoreSection> buildMoreSections({required bool dashboardReachable}) {
  MoreEntryAvailability dashboardBacked() => dashboardReachable
      ? MoreEntryAvailability.available
      : MoreEntryAvailability.unavailable;
  String? dashboardReason() => dashboardReachable ? null : _dashboardRequired;

  return [
    MoreSection(
      title: '工作区',
      entries: [
        const MoreEntry(
          id: 'unassigned',
          title: '未分配对话',
          subtitle: '尚未分配到项目的对话',
          icon: Icons.inbox_outlined,
        ),
        const MoreEntry(
          id: 'archived-quick',
          title: '已归档的快捷对话',
          subtitle: '查看或恢复超过保留期的快捷对话',
          icon: Icons.archive_outlined,
        ),
        MoreEntry(
          id: 'files',
          title: '文件',
          subtitle: '浏览项目背后的 miniserver 文件夹',
          icon: Icons.folder_open_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        const MoreEntry(
          id: 'assets',
          title: '资产',
          subtitle: '产物、附件和生成的媒体',
          icon: Icons.image_outlined,
          availability: MoreEntryAvailability.unavailable,
          unavailableReason: _gatewayAssetsRequired,
        ),
      ],
    ),
    const MoreSection(
      title: '整理',
      entries: [
        MoreEntry(
          id: 'pin-batch-undo',
          title: '置顶、批量与撤销',
          subtitle: '跨设备排序和可逆的批量整理',
          icon: Icons.push_pin_outlined,
          availability: MoreEntryAvailability.unavailable,
          unavailableReason: _gatewayOrganizationRequired,
        ),
        MoreEntry(
          id: 'ai-filing',
          title: 'AI 辅助归档',
          subtitle: '建议项目并从你的纠正中学习',
          icon: Icons.auto_fix_high_outlined,
          availability: MoreEntryAvailability.unavailable,
          unavailableReason: _gatewayAiFilingRequired,
        ),
      ],
    ),
    MoreSection(
      title: '自动化',
      entries: [
        MoreEntry(
          id: 'cron',
          title: '定时任务',
          subtitle: '计划任务及其最近一次运行',
          icon: Icons.schedule_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'skills',
          title: '技能与工具',
          subtitle: 'Hermes 能做到什么',
          icon: Icons.auto_awesome_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'memory',
          title: '记忆',
          subtitle: 'Hermes 记住的关于你的持久事实',
          icon: Icons.psychology_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
      ],
    ),
    MoreSection(
      title: '系统',
      entries: [
        const MoreEntry(
          id: 'settings',
          title: '设置',
          subtitle: '连接、外观和设备偏好',
          icon: Icons.settings_outlined,
        ),
        MoreEntry(
          id: 'dashboard',
          title: '打开 Hermes 仪表盘',
          subtitle: '尚未原生化的功能都在经过身份验证的网页仪表盘中',
          icon: Icons.open_in_new,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
      ],
    ),
  ];
}

/// Renders the More menu.
class MorePane extends StatelessWidget {
  final List<MoreSection> sections;
  final ValueChanged<MoreEntry> onSelect;

  const MorePane({required this.sections, required this.onSelect, super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
      children: [
        for (final section in sections) ...[
          SectionHeader(title: section.title),
          for (final entry in section.entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HermesSpacing.lg,
                0,
                HermesSpacing.lg,
                HermesSpacing.md,
              ),
              child: _MoreEntryCard(entry: entry, onSelect: onSelect),
            ),
        ],
      ],
    );
  }
}

class _MoreEntryCard extends StatelessWidget {
  final MoreEntry entry;
  final ValueChanged<MoreEntry> onSelect;

  const _MoreEntryCard({required this.entry, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final dimmed = !entry.isSelectable;
    final titleColor = dimmed ? tokens.muted : tokens.onSurface;

    return Semantics(
      button: entry.isSelectable,
      enabled: entry.isSelectable,
      label: entry.title,
      child: HermesCard(
        onTap: entry.isSelectable ? () => onSelect(entry) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (dimmed ? tokens.muted : tokens.accent).withValues(
                  alpha: 0.14,
                ),
                borderRadius: BorderRadius.circular(HermesRadius.sm),
              ),
              child: Icon(
                entry.icon,
                size: 20,
                color: dimmed ? tokens.muted : tokens.accent,
              ),
            ),
            const SizedBox(width: HermesSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A Wrap rather than a Row: at a large text scale the badge
                  // moves to its own line instead of overflowing the card.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: HermesSpacing.sm,
                    runSpacing: HermesSpacing.xs,
                    children: [
                      Text(
                        entry.title,
                        style: tokens.typography.section.copyWith(
                          color: titleColor,
                        ),
                      ),
                      if (entry.availability ==
                          MoreEntryAvailability.comingSoon)
                        const StatusChip(
                          status: HermesStatus.idle,
                          label: '即将推出',
                        ),
                    ],
                  ),
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    entry.subtitle,
                    style: tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                  if (entry.availability ==
                      MoreEntryAvailability.unavailable) ...[
                    const SizedBox(height: HermesSpacing.xs),
                    Text(
                      entry.unavailableReason!,
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
