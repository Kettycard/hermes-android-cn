/// The project detail screen: Overview and Chats for one server-owned project.
///
/// `ProjectsRepository.projectSessions` and the `projects.project_sessions`
/// RPC beneath it were both delivered before anything rendered them, so a
/// project card in [ProjectsPane] had nowhere to go. This screen is that
/// destination.
///
/// Two decisions are worth stating because they are easy to get wrong later:
///
/// * **Counts come from the server, never from the rows on screen.** The
///   overview tier of `projects.tree` deliberately ships lanes with their
///   session rows emptied, so deriving a count from what is rendered would
///   make every project report zero chats.
/// * **A failed re-read is not a failed screen.** The first read owns the
///   error state; every later failure keeps the chats already visible behind
///   an offline notice, because losing the network must never blank a screen
///   the user is reading.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` (Phase 1).
library;

import 'package:flutter/material.dart';

import '../models/hermes_project.dart';
import '../models/project_sessions_tree.dart';
import '../models/session.dart';
import '../services/projects_repository.dart';
import '../theme/hermes_theme.dart';
import '../utils/project_session_filter.dart';
import '../utils/relative_time.dart';
import 'hermes_components.dart';

/// Reads one project's chats. Mirrors `ProjectsRepository.projectSessions` so
/// the screen can be driven by a fake in tests without a gateway.
typedef ProjectSessionsLoader =
    Future<ProjectSessionsView> Function({required bool refresh});
typedef ProjectSessionMover =
    Future<void> Function(Session session, String? projectId);
typedef ProjectRenamer = Future<void> Function(String name);
typedef ProjectArchiver = Future<void> Function();
typedef ProjectDeleter = Future<void> Function();

const kProjectNewChatButtonKey = Key('project-detail-new-chat');
const kProjectSearchFieldKey = Key('project-detail-search');

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  /// Shown in the app bar before the first read lands, so the screen never
  /// opens on the word "Untitled".
  final String projectName;

  final ProjectSessionsLoader loadSessions;

  /// Opens one chat. When null the rows are drawn inert rather than
  /// fake-tappable.
  final ValueChanged<Session>? onOpenSession;

  /// Starts a chat already scoped to this Project.
  final VoidCallback? onNewChat;

  /// Server Projects offered as move destinations for existing chats.
  final List<HermesProject> projects;
  final ProjectSessionMover? onMoveSession;

  /// Reversible Project administration backed by the Gateway.
  final ProjectRenamer? onRenameProject;
  final ProjectArchiver? onArchiveProject;

  /// Permanently removes this server Project. Its chat sessions survive and
  /// become Unassigned because the Gateway deletes only their assignments.
  final ProjectDeleter? onDeleteProject;

  const ProjectDetailScreen({
    required this.projectId,
    required this.projectName,
    required this.loadSessions,
    this.onOpenSession,
    this.onNewChat,
    this.projects = const [],
    this.onMoveSession,
    this.onRenameProject,
    this.onArchiveProject,
    this.onDeleteProject,
    super.key,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  ProjectSessionsView? _view;

  /// True until the first read resolves, which is what separates a retryable
  /// first failure from a refresh failure over content.
  bool _loading = true;

  /// Per-Project search: filters the sessions the server already returned.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _deleting = false;
  bool _managing = false;
  late String _projectName;

  @override
  void initState() {
    super.initState();
    _projectName = widget.projectName;
    _load(refresh: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
  }

  Future<void> _load({required bool refresh}) async {
    try {
      final view = await widget.loadSessions(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // The repository already reports failures inside the view; this guards
      // the loader contract itself so a throw cannot leave a stuck skeleton.
      setState(() {
        _view = ProjectSessionsView(projectId: widget.projectId, error: error);
        _loading = false;
      });
    }
  }

  Future<void> _chooseMoveDestination(Session session) async {
    final target = await showModalBottomSheet<_MoveTarget>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                HermesSpacing.lg,
                HermesSpacing.lg,
                HermesSpacing.lg,
                HermesSpacing.sm,
              ),
              child: Text('移动对话'),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('未分配'),
              onTap: () => Navigator.pop(
                context,
                const _MoveTarget(projectId: null, label: '未分配'),
              ),
            ),
            for (final project in widget.projects)
              if (!project.archived && project.id != widget.projectId)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(project.name),
                  onTap: () => Navigator.pop(
                    context,
                    _MoveTarget(projectId: project.id, label: project.name),
                  ),
                ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await _moveSession(session, target);
  }

  Future<void> _moveSession(Session session, _MoveTarget target) async {
    try {
      await widget.onMoveSession!(session, target.projectId);
      if (!mounted) return;
      await _load(refresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已移动到 ${target.label}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('无法移动对话'),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => _moveSession(session, target),
          ),
        ),
      );
    }
  }

  Future<void> _renameProject() async {
    final rename = widget.onRenameProject;
    if (rename == null || _managing) return;
    var draft = _projectName;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('重命名 $_projectName'),
        content: TextFormField(
          key: const Key('rename-project-name'),
          initialValue: _projectName,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '名称'),
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('重命名'),
          ),
        ],
      ),
    );
    if (name == null || !mounted || name == _projectName) return;
    setState(() => _managing = true);
    try {
      await rename(name);
      if (mounted) {
        setState(() {
          _projectName = name;
          _managing = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _managing = false);
      _showManagementError('重命名', _renameProject);
    }
  }

  Future<void> _confirmArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('归档 $_projectName？'),
        content: const Text(
          '项目将移入“已归档”。其对话和文件保持不变，你可以稍后恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _archiveProject();
  }

  Future<void> _archiveProject() async {
    final archive = widget.onArchiveProject;
    if (archive == null || _managing) return;
    setState(() => _managing = true);
    try {
      await archive();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      } else {
        setState(() => _managing = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _managing = false);
      _showManagementError('归档', _archiveProject);
    }
  }

  void _showManagementError(String action, Future<void> Function() retry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('无法$action项目'),
        action: SnackBarAction(label: '重试', onPressed: retry),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除 $_projectName？'),
        content: const Text(
          '这将永久删除该项目。对话不会被删除，它们将回到“未分配”。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _deleteProject();
  }

  Future<void> _deleteProject() async {
    final delete = widget.onDeleteProject;
    if (delete == null || _deleting) return;
    setState(() => _deleting = true);
    try {
      await delete();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      } else {
        // Embedders may mount the detail as their root rather than a route.
        // There is nowhere to return in that case, but the action must still
        // settle instead of leaving an infinite progress indicator.
        setState(() => _deleting = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('无法删除项目'),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => _deleteProject(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final title = _projectName;
    final hasActions =
        widget.onRenameProject != null ||
        widget.onArchiveProject != null ||
        widget.onDeleteProject != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (hasActions)
            if (_deleting || _managing)
              const Padding(
                padding: EdgeInsets.all(HermesSpacing.md),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<String>(
                tooltip: '项目操作',
                onSelected: (action) {
                  switch (action) {
                    case 'rename':
                      _renameProject();
                    case 'archive':
                      _confirmArchive();
                    case 'delete':
                      _confirmDelete();
                  }
                },
                itemBuilder: (context) => [
                  if (widget.onRenameProject != null)
                    const PopupMenuItem<String>(
                      value: 'rename',
                      child: Text('重命名项目'),
                    ),
                  if (widget.onArchiveProject != null)
                    const PopupMenuItem<String>(
                      value: 'archive',
                      child: Text('归档项目'),
                    ),
                  if (widget.onDeleteProject != null)
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: HermesSpacing.sm),
                          Text(
                            '删除项目',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '对话'),
            Tab(text: '概览'),
            Tab(text: '文件'),
            Tab(text: '资产'),
            Tab(text: '活动'),
          ],
          isScrollable: true,
        ),
      ),
      body: _buildBody(view),
      floatingActionButton: widget.onNewChat == null
          ? null
          : FloatingActionButton.extended(
              key: kProjectNewChatButtonKey,
              onPressed: widget.onNewChat,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新对话'),
            ),
    );
  }

  Widget _buildBody(ProjectSessionsView? view) {
    if (_loading || view == null) {
      return const Padding(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    // An older gateway is not a crash and not an empty project: saying "no
    // chats" here would state something this gateway cannot actually know.
    if (view.support == ProjectsSupport.unsupported) {
      return const ErrorState.unsupported(
        title: '项目对话暂不可用',
        message:
            '此 Hermes 网关尚不支持打开项目。请在服务器上更新 Hermes，即可从手机浏览项目。',
      );
    }

    // Only a *first* read with nothing to show is an error screen.
    if (view.error != null && view.sessions.isEmpty && !view.isStale) {
      return ErrorState(
        title: '无法打开此项目',
        message: '请确认网关正在运行且可访问，然后重试。',
        onRetry: () => _load(refresh: true),
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [
        _buildChats(view),
        _buildOverview(view),
        _buildFiles(view),
        _buildAssets(view),
        _buildActivity(view),
      ],
    );
  }

  Widget _buildChats(ProjectSessionsView view) {
    final sessions = view.sessions;
    final filtered = filterProjectSessions(sessions, _searchQuery);
    final querying = _searchQuery.trim().isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: CustomScrollView(
        // Always scrollable, so pull-to-refresh works on an empty project too.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (view.isStale) const SliverToBoxAdapter(child: _OfflineNotice()),
          // The search field exists only when there is something to search.
          // An empty project keeps its honest "No chats yet" state.
          if (sessions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  HermesSpacing.md,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: SearchBar(
                  key: kProjectSearchFieldKey,
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  hintText: '搜索对话',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (querying)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '清空搜索',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),
          if (sessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.forum_outlined,
                title: '还没有对话',
                message:
                    '你在此项目中开始的对话会显示在这里，并同步到登录此 Hermes 的所有设备。',
              ),
            )
          else if (filtered.isEmpty)
            // A query that matches nothing is not the same as an empty
            // project: saying "No chats yet" would tell the user the chat
            // they are looking for does not exist.
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off,
                title: '没有匹配结果',
                message:
                    '此项目中没有对话匹配 “${_searchQuery.trim()}”。',
              ),
            )
          else
            SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final session = filtered[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HermesSpacing.lg,
                    HermesSpacing.sm,
                    HermesSpacing.lg,
                    0,
                  ),
                  child: _SessionCard(
                    session: session,
                    onTap: widget.onOpenSession == null
                        ? null
                        : () => widget.onOpenSession!(session),
                    onMove: widget.onMoveSession == null
                        ? null
                        : () => _chooseMoveDestination(session),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: HermesSpacing.lg)),
        ],
      ),
    );
  }

  Widget _buildOverview(ProjectSessionsView view) {
    final tree = view.tree;
    final tokens = HermesTokens.of(context);

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          const SectionHeader(title: '对话'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: HermesCard(
              child: Row(
                children: [
                  Icon(Icons.forum_outlined, color: tokens.muted, size: 20),
                  const SizedBox(width: HermesSpacing.md),
                  Expanded(
                    child: Text(
                      '此项目中的对话',
                      style: tokens.typography.body.copyWith(
                        color: tokens.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    // The server's count, not the rows we happen to hold.
                    '${tree?.sessionCount ?? view.sessions.length}',
                    style: tokens.typography.title.copyWith(
                      color: tokens.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (tree != null && tree.repos.isNotEmpty) ...[
            const SectionHeader(title: '仓库'),
            for (final repo in tree.repos)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.md,
                ),
                child: _RepoCard(repo: repo),
              ),
          ],
          if (tree?.path != null) ...[
            const SectionHeader(title: '位置'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
              child: HermesCard(
                child: Text(
                  tree!.path!,
                  style: tokens.typography.mono.copyWith(color: tokens.muted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The project's folders, exactly as the server described them.
  ///
  /// Paths come from `projects.project_sessions` (project, repos, lanes); the
  /// screen never scans local storage and never invents a tree of its own.
  Widget _buildFiles(ProjectSessionsView view) {
    final tokens = HermesTokens.of(context);
    final paths = <String>[];
    void add(String? path) {
      if (path != null && path.trim().isNotEmpty && !paths.contains(path)) {
        paths.add(path);
      }
    }

    final tree = view.tree;
    add(tree?.path);
    for (final repo in tree?.repos ?? const <ProjectRepo>[]) {
      add(repo.path);
      for (final lane in repo.lanes) {
        add(lane.path);
      }
    }

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          if (paths.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: HermesSpacing.xl),
              child: EmptyState(
                icon: Icons.folder_open_outlined,
                title: '还没有文件夹',
                message:
                    '服务器尚未报告此项目的文件夹。全局文件仍可从“更多”中访问。',
              ),
            )
          else ...[
            const SectionHeader(title: '文件夹'),
            for (final path in paths)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: HermesCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: tokens.muted,
                      ),
                      const SizedBox(width: HermesSpacing.md),
                      Expanded(
                        child: Text(
                          path,
                          style: tokens.typography.mono.copyWith(
                            color: tokens.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Honest capability gate: no server Assets index, no fake gallery.
  Widget _buildAssets(ProjectSessionsView view) {
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          const Padding(
            padding: EdgeInsets.only(top: HermesSpacing.xl),
            child: ErrorState.unsupported(
              title: '资产暂不可用',
              message:
                  '资产需要 Hermes 网关提供服务器端权威的资产索引，才能按项目显示。',
            ),
          ),
        ],
      ),
    );
  }

  /// The project's own activity: every chat with its current state and when
  /// it was last active, newest first.
  Widget _buildActivity(ProjectSessionsView view) {
    final tokens = HermesTokens.of(context);
    final now = DateTime.now();
    final sessions = [...view.sessions]
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          if (view.isStale) const _OfflineNotice(),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: HermesSpacing.xl),
              child: EmptyState(
                icon: Icons.bolt_outlined,
                title: '还没有活动',
                message:
                    '此项目中的对话将在这里显示其状态和最近的活动时间。',
              ),
            )
          else
            for (final session in sessions)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: HermesCard(
                  onTap: () => widget.onOpenSession?.call(session),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.title.trim().isEmpty
                                  ? '未命名对话'
                                  : session.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: HermesSpacing.xs),
                            Text(
                              formatRelativeTime(now, session.lastActive),
                              style: tokens.typography.label.copyWith(
                                color: tokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(
                        status: session.isActive
                            ? HermesStatus.running
                            : HermesStatus.completed,
                        label: session.isActive ? '运行中' : '已完成',
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// States that the content is the last known good copy, not live data.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        HermesSpacing.md,
        HermesSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: tokens.warning),
          const SizedBox(width: HermesSpacing.sm),
          Expanded(
            child: Text(
              '已离线 — 显示最近一次已知的对话',
              style: tokens.typography.label.copyWith(color: tokens.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveTarget {
  final String? projectId;
  final String label;

  const _MoveTarget({required this.projectId, required this.label});
}

class _SessionCard extends StatelessWidget {
  final Session session;
  final VoidCallback? onTap;
  final VoidCallback? onMove;

  const _SessionCard({required this.session, this.onTap, this.onMove});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return HermesCard(
      onTap: onTap,
      status: session.isActive ? HermesStatus.running : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.body.copyWith(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (session.isActive) ...[
                const SizedBox(width: HermesSpacing.sm),
                const StatusChip(status: HermesStatus.running),
              ],
              if (onMove != null) ...[
                const SizedBox(width: HermesSpacing.xs),
                IconButton(
                  key: Key('move-session-${session.id}'),
                  tooltip: '移动对话',
                  onPressed: onMove,
                  icon: const Icon(Icons.drive_file_move_outline, size: 20),
                ),
              ],
            ],
          ),
          if (session.preview.isNotEmpty) ...[
            const SizedBox(height: HermesSpacing.xs),
            Text(
              session.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.label.copyWith(color: tokens.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _RepoCard extends StatelessWidget {
  final ProjectRepo repo;

  const _RepoCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final lanes = repo.lanes;

    return HermesCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 18, color: tokens.muted),
              const SizedBox(width: HermesSpacing.sm),
              Expanded(
                child: Text(
                  repo.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.body.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              Text(
                '${repo.sessionCount}',
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ],
          ),
          if (lanes.isNotEmpty) ...[
            const SizedBox(height: HermesSpacing.sm),
            Wrap(
              spacing: HermesSpacing.sm,
              runSpacing: HermesSpacing.xs,
              children: [
                for (final lane in lanes)
                  Text(
                    lane.isMain ? '${lane.label} · 主' : lane.label,
                    style: tokens.typography.label.copyWith(
                      color: lane.isMain ? tokens.accent : tokens.muted,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
