/// The read-only Spaces → Projects migration preview.
///
/// The roadmap requires the local Spaces prototype to be migrated onto
/// server-owned Projects *only* after the user has seen exactly what would
/// happen. This widget renders [SpaceMigrationPlan] — which never writes
/// anything — so the preview is honest by construction: it shows matches,
/// the projects that would have to be created, and how many chats are
/// involved, while stating plainly that nothing has moved.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` ("Migration of the current
/// Spaces prototype").
library;

import 'package:flutter/material.dart';

import '../services/projects_repository.dart';
import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

class SpaceMigrationPreview extends StatefulWidget {
  final SpaceMigrationPlan plan;
  final VoidCallback? onDismiss;
  final Future<SpaceMigrationResult> Function()? onMigrate;

  const SpaceMigrationPreview({
    required this.plan,
    this.onDismiss,
    this.onMigrate,
    super.key,
  });

  @override
  State<SpaceMigrationPreview> createState() => _SpaceMigrationPreviewState();
}

class _SpaceMigrationPreviewState extends State<SpaceMigrationPreview> {
  bool _migrating = false;
  SpaceMigrationResult? _result;
  Object? _error;

  static String _chats(int count) => count == 1 ? '1 个对话' : '$count 个对话';

  String get _summary {
    final plan = widget.plan;
    final spaces = plan.entries.length == 1
        ? '1 个空间'
        : '${plan.entries.length} 个空间';
    final toCreate = plan.projectsToCreate;
    final projects = switch (toCreate) {
      0 => '无需创建新项目',
      1 => '需创建 1 个项目',
      _ => '需创建 $toCreate 个项目',
    };
    return '$spaces · ${_chats(plan.sessionsToLink)} · $projects';
  }

  Future<void> _runMigration() async {
    final migrate = widget.onMigrate;
    if (migrate == null || _migrating) return;
    setState(() {
      _migrating = true;
      _error = null;
    });
    try {
      final result = await migrate();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final plan = widget.plan;

    if (plan.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EmptyState(
            icon: Icons.swap_horiz_rounded,
            title: '没有可迁移的内容',
            message:
                '未找到此连接的本地空间，项目已经是这里唯一使用的组织方式。',
          ),
          if (widget.onDismiss != null)
            TextButton(onPressed: widget.onDismiss, child: const Text('关闭')),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
      children: [
        const SectionHeader(title: '迁移预览'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
          child: Text(
            _summary,
            style: tokens.typography.body.copyWith(color: tokens.onSurface),
          ),
        ),
        const SizedBox(height: HermesSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
          child: Text(
            '尚未移动任何内容 — 这只是迁移将会执行的操作。',
            style: tokens.typography.label.copyWith(color: tokens.muted),
          ),
        ),
        if (_result case final result?) ...[
          const SizedBox(height: HermesSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: HermesCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.isComplete
                        ? '迁移完成'
                        : '迁移未完成',
                    style: tokens.typography.section.copyWith(
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    '已迁移 ${result.linkedSessions} 个对话 · '
                    '已创建 ${result.createdProjects} 个项目',
                    style: tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                  if (result.unlinkedSessions > 0)
                    Text(
                      '${result.unlinkedSessions} 个对话仍保留在本地空间中，'
                      '可以安全地重试。',
                      style: tokens.typography.body.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: HermesSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: Text(
              '迁移失败。本地空间保持不变。',
              style: tokens.typography.body.copyWith(color: tokens.danger),
            ),
          ),
        ],
        const SizedBox(height: HermesSpacing.md),
        for (final entry in plan.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              0,
              HermesSpacing.lg,
              HermesSpacing.md,
            ),
            child: _EntryCard(entry: entry),
          ),
        if (widget.onMigrate != null && _result?.isComplete != true)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: FilledButton.icon(
              onPressed: _migrating ? null : _runMigration,
              icon: _migrating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz_rounded),
              label: Text(_migrating ? '迁移中…' : '迁移'),
            ),
          ),
        if (widget.onDismiss != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: TextButton(
              onPressed: _migrating ? null : widget.onDismiss,
              child: const Text('关闭'),
            ),
          ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final SpaceMigrationEntry entry;

  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final matched = entry.matchedProject;
    final assigned = entry.sessionCount == 1
        ? '1 个已分配对话'
        : '${entry.sessionCount} 个已分配对话';

    return HermesCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.space.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: HermesSpacing.sm),
              StatusChip(
                status: matched == null
                    ? HermesStatus.blocked
                    : HermesStatus.completed,
                label: matched == null ? '新建项目' : '已匹配',
              ),
            ],
          ),
          const SizedBox(height: HermesSpacing.xs),
          Text(
            matched == null
                ? '没有名称匹配的服务器项目 · $assigned'
                : '匹配 ${matched.name} · $assigned',
            style: tokens.typography.body.copyWith(color: tokens.muted),
          ),
        ],
      ),
    );
  }
}
