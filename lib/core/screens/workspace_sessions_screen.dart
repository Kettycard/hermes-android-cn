import 'dart:async';

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/hermes_theme.dart';
import '../utils/relative_time.dart';
import '../widgets/hermes_components.dart';

const kWorkspaceSessionSearchKey = Key('workspace-session-search');

enum WorkspaceSessionView { all, unassigned, archivedQuick, search }

/// The chip filters the Chats browser offers (decision #4 of the final UI
/// spec): every conversation, recent activity, unassigned, and archived.
enum WorkspaceChatsFilter {
  all('全部'),
  recent('最近'),
  unassigned('未分配'),
  archived('已归档');

  final String label;
  const WorkspaceChatsFilter(this.label);
}

/// How recently a conversation was last active, for date group headers.
enum ChatDateBucket {
  today('今天'),
  yesterday('昨天'),
  thisWeek('本周'),
  earlier('更早');

  final String label;
  const ChatDateBucket(this.label);
}

/// How long "Recent" means in the Chats browser.
const Duration kRecentChatsWindow = Duration(days: 7);

/// Assigns a conversation to its date bucket, by calendar day.
ChatDateBucket chatDateBucket(DateTime now, double lastActiveSeconds) {
  final activity = DateTime.fromMillisecondsSinceEpoch(
    (lastActiveSeconds * 1000).round(),
  );
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(activity.year, activity.month, activity.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return ChatDateBucket.today;
  if (diff == 1) return ChatDateBucket.yesterday;
  if (diff < 7) return ChatDateBucket.thisWeek;
  return ChatDateBucket.earlier;
}

/// Filters and sorts the Chats browser list for one chip filter.
///
/// Sorting is always by most recent activity, so a conversation moving up in
/// the list is the honest signal that it changed. [now] is injectable so the
/// "Recent" window and date buckets are deterministic in tests.
List<Session> filterChats({
  required List<Session> sessions,
  required WorkspaceChatsFilter filter,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final normalized = query.trim().toLowerCase();
  final recentCutoff =
      current.subtract(kRecentChatsWindow).millisecondsSinceEpoch / 1000.0;

  final filtered = [
    for (final session in sessions)
      if (switch (filter) {
            WorkspaceChatsFilter.all => true,
            WorkspaceChatsFilter.recent => session.lastActive >= recentCutoff,
            WorkspaceChatsFilter.unassigned => !claimedSessionIds.contains(
              session.id,
            ),
            WorkspaceChatsFilter.archived =>
              session.archived || archivedQuickChatIds.contains(session.id),
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
  return filtered;
}

/// Groups conversations into date buckets, newest bucket first.
List<MapEntry<ChatDateBucket, List<Session>>> groupChatsByDate(
  DateTime now,
  List<Session> sessions,
) {
  final buckets = <ChatDateBucket, List<Session>>{
    for (final bucket in ChatDateBucket.values) bucket: <Session>[],
  };
  for (final session in sessions) {
    buckets[chatDateBucket(now, session.lastActive)]!.add(session);
  }
  return [
    for (final bucket in ChatDateBucket.values)
      if (buckets[bucket]!.isNotEmpty)
        MapEntry(bucket, List.unmodifiable(buckets[bucket]!)),
  ];
}

class WorkspaceSessionsData {
  final List<Session> sessions;
  final Set<String> claimedSessionIds;
  final Set<String> archivedQuickChatIds;

  /// Best-effort session id → project label mapping.
  ///
  /// Built from the server `projects.tree` preview rows; a conversation whose
  /// project is unknown stays honest as "Unassigned" in the UI.
  final Map<String, String> projectLabels;

  const WorkspaceSessionsData({
    this.sessions = const [],
    this.claimedSessionIds = const {},
    this.archivedQuickChatIds = const {},
    this.projectLabels = const {},
  });
}

typedef WorkspaceSessionsLoader = Future<WorkspaceSessionsData> Function();
typedef WorkspaceSessionPromoter = Future<void> Function(Session session);

class QuickChatPromotionCancelled implements Exception {
  const QuickChatPromotionCancelled();
}

List<Session> filterWorkspaceSessions({
  required List<Session> sessions,
  required WorkspaceSessionView view,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
}) {
  final normalized = query.trim().toLowerCase();
  return [
    for (final session in sessions)
      if (switch (view) {
            WorkspaceSessionView.unassigned => !claimedSessionIds.contains(
              session.id,
            ),
            WorkspaceSessionView.archivedQuick => archivedQuickChatIds.contains(
              session.id,
            ),
            WorkspaceSessionView.all || WorkspaceSessionView.search => true,
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ];
}

class WorkspaceSessionsScreen extends StatefulWidget {
  final String title;
  final WorkspaceSessionView view;
  final WorkspaceSessionsLoader load;
  final ValueChanged<Session> onOpenSession;
  final WorkspaceSessionPromoter? onPromote;
  final bool embedded;

  /// Clock injection for deterministic filter/date tests. When null the
  /// screen uses `DateTime.now()`.
  final DateTime? now;

  const WorkspaceSessionsScreen({
    required this.title,
    required this.view,
    required this.load,
    required this.onOpenSession,
    this.onPromote,
    this.embedded = false,
    this.now,
    super.key,
  });

  @override
  State<WorkspaceSessionsScreen> createState() =>
      _WorkspaceSessionsScreenState();
}

class _WorkspaceSessionsScreenState extends State<WorkspaceSessionsScreen> {
  WorkspaceSessionsData? _data;
  Object? _error;
  String _query = '';
  final Set<String> _promoting = {};

  /// The active chip filter in the embedded Chats browser.
  WorkspaceChatsFilter _filter = WorkspaceChatsFilter.all;

  /// Injectable clock for deterministic tests.
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await widget.load();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('[workspace-sessions] load failed: $error');
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _promote(Session session) async {
    final promote = widget.onPromote;
    if (promote == null || _promoting.contains(session.id)) return;
    setState(() => _promoting.add(session.id));
    try {
      await promote(session);
      if (!mounted) return;
      final data = _data;
      if (data != null) {
        setState(() {
          _data = WorkspaceSessionsData(
            sessions: data.sessions,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: {
              for (final id in data.archivedQuickChatIds)
                if (id != session.id) id,
            },
            projectLabels: data.projectLabels,
          );
          _promoting.remove(session.id);
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已提升为项目')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _promoting.remove(session.id));
      if (error is QuickChatPromotionCancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('无法提升对话'),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => unawaited(_promote(session)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final body = data == null
        ? _error == null
              ? const Padding(
                  padding: EdgeInsets.only(top: HermesSpacing.lg),
                  child: LoadingSkeleton(rows: 5),
                )
              : ErrorState(
                  title: '无法加载对话',
                  message: '请检查连接后重试。',
                  onRetry: _load,
                )
        : _buildLoaded(data);
    if (widget.embedded) {
      return Material(color: Colors.transparent, child: body);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }

  Widget _buildLoaded(WorkspaceSessionsData data) {
    final sessions = widget.embedded
        ? filterChats(
            sessions: data.sessions,
            filter: _filter,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
            now: _now,
          )
        : filterWorkspaceSessions(
            sessions: data.sessions,
            view: widget.view,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
          );

    final groups = widget.embedded
        ? groupChatsByDate(_now, sessions)
        : [
            MapEntry(
              ChatDateBucket.today,
              List<Session>.unmodifiable(sessions),
            ),
          ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          HermesSpacing.md,
          HermesSpacing.lg,
          HermesSpacing.xl,
        ),
        children: [
          TextField(
            key: kWorkspaceSessionSearchKey,
            autofocus: widget.view == WorkspaceSessionView.search,
            decoration: InputDecoration(
              hintText: '搜索对话',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          if (widget.embedded) ...[
            const SizedBox(height: HermesSpacing.md),
            _buildChips(),
          ],
          const SizedBox(height: HermesSpacing.lg),
          if (sessions.isEmpty)
            EmptyState(
              icon: _emptyIcon,
              title: _query.isEmpty ? '这里还没有内容' : '无匹配',
              message: _emptyMessage,
            )
          else
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: HermesSpacing.xs,
                  bottom: HermesSpacing.sm,
                ),
                child: Text(
                  widget.embedded ? group.key.label : widget.title,
                  style: HermesTokens.of(context).typography.section,
                ),
              ),
              for (final session in group.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: HermesSpacing.sm),
                  child: _buildSessionRow(session, data),
                ),
            ],
        ],
      ),
    );
  }

  Widget _buildChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in WorkspaceChatsFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: HermesSpacing.sm),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Session session, WorkspaceSessionsData data) {
    final tokens = HermesTokens.of(context);
    final projectLabel = data.projectLabels[session.id];
    final showPromote =
        widget.view == WorkspaceSessionView.archivedQuick &&
        widget.onPromote != null;
    return HermesCard(
      onTap: () => widget.onOpenSession(session),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            session.pinned
                ? Icons.push_pin_outlined
                : Icons.chat_bubble_outline,
            size: 20,
            color: session.pinned ? tokens.accent : tokens.muted,
          ),
          const SizedBox(width: HermesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title.isEmpty ? '未命名对话' : session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (session.preview.isNotEmpty)
                  Text(
                    session.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.muted),
                  ),
                const SizedBox(height: HermesSpacing.xs),
                Wrap(
                  spacing: HermesSpacing.sm,
                  runSpacing: HermesSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(
                      status: session.isActive
                          ? HermesStatus.running
                          : HermesStatus.completed,
                      label: session.isActive ? '进行中' : '已完成',
                    ),
                    if (projectLabel != null)
                      _MetaChip(
                        label: projectLabel,
                        icon: Icons.folder_outlined,
                      )
                    else
                      _MetaChip(
                        label: '未分配',
                        icon: Icons.inbox_outlined,
                      ),
                    Text(
                      _relativeTime(_now, session.lastActive),
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showPromote)
            _promoting.contains(session.id)
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: '提升为项目',
                    onPressed: () => unawaited(_promote(session)),
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
        ],
      ),
    );
  }

  IconData get _emptyIcon {
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned => Icons.inbox_outlined,
        WorkspaceChatsFilter.archived => Icons.archive_outlined,
        WorkspaceChatsFilter.recent => Icons.history_outlined,
        WorkspaceChatsFilter.all => Icons.search_off,
      };
    }
    return widget.view == WorkspaceSessionView.unassigned
        ? Icons.inbox_outlined
        : Icons.search_off;
  }

  String get _emptyMessage {
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned =>
          '所有对话都已分配到项目。',
        WorkspaceChatsFilter.archived => '已归档的对话会显示在这里。',
        WorkspaceChatsFilter.recent =>
          '最近七天没有变化。',
        WorkspaceChatsFilter.all => '此视图没有匹配的对话。',
      };
    }
    return switch (widget.view) {
      WorkspaceSessionView.unassigned =>
        '所有对话都已分配到项目。',
      WorkspaceSessionView.archivedQuick =>
        '快捷对话超过保留期后会显示在这里。',
      WorkspaceSessionView.all ||
      WorkspaceSessionView.search => '此视图没有匹配的对话。',
    };
  }

  /// Compact relative time: "now", "5m", "2h", "3d", else a date.
  String _relativeTime(DateTime now, double lastActiveSeconds) =>
      formatRelativeTime(now, lastActiveSeconds);
}

/// A small neutral label under a conversation row (project, unassigned).
class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MetaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: HermesSpacing.sm,
            vertical: HermesSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.raised,
            borderRadius: BorderRadius.circular(HermesRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: tokens.muted),
              const SizedBox(width: 4),
              Text(label, style: tokens.typography.label),
            ],
          ),
        ),
      ),
    );
  }
}
