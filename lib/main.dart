import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/android_launch_intent_service.dart';
import 'core/services/android_share_intent_service.dart';
import 'core/services/config_backup.dart';
import 'core/services/config_backup_io.dart';
import 'core/services/config_backup_service.dart';
import 'core/services/connection_manager.dart';
import 'core/services/gateway_turn_application_controller.dart';
import 'core/services/text_size_preference.dart';
import 'core/screens/workspace_screen.dart';
import 'core/theme/hermes_theme.dart';
import 'core/utils/responsive.dart';
import 'core/widgets/config_backup_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final connManager = await ConnectionManager.create(prefs);
  final shareIntents = AndroidShareIntentService();
  final launchIntents = AndroidLaunchIntentService();
  await Future.wait([shareIntents.initialize(), launchIntents.initialize()]);
  runApp(
    HermesApp(
      connManager: connManager,
      shareIntents: shareIntents,
      launchIntents: launchIntents,
    ),
  );
}

class HermesApp extends StatefulWidget {
  final ConnectionManager connManager;
  final AndroidShareIntentService? shareIntents;
  final AndroidLaunchIntentService? launchIntents;
  const HermesApp({
    required this.connManager,
    this.shareIntents,
    this.launchIntents,
    super.key,
  });

  @override
  State<HermesApp> createState() => HermesAppState();

  static ThemeMode getThemeMode(SharedPreferences prefs) {
    final stored = prefs.getString('theme_mode') ?? 'system';
    switch (stored) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(
    SharedPreferences prefs,
    ThemeMode mode,
  ) async {
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await prefs.setString('theme_mode', value);
  }

  static TextSizePreference getTextSizePreference(SharedPreferences prefs) {
    return TextSizePreferenceStore(prefs).read();
  }
}

class HermesAppState extends State<HermesApp> {
  late final GatewayTurnApplicationController _turnApplicationController;

  @override
  void initState() {
    super.initState();
    _turnApplicationController = GatewayTurnApplicationController();
  }

  Future<void> setTextSizePreference(TextSizePreference preference) async {
    await TextSizePreferenceStore(widget.connManager.prefs).save(preference);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes 智能体',
      themeMode: HermesApp.getThemeMode(widget.connManager.prefs),
      theme: hermesTheme(Brightness.light),
      darkTheme: hermesTheme(Brightness.dark),
      builder: (context, child) {
        final systemMediaQuery = MediaQuery.of(context);
        final preference = HermesApp.getTextSizePreference(
          widget.connManager.prefs,
        );
        return MediaQuery(
          data: systemMediaQuery.copyWith(
            textScaler: preference.applyTo(systemMediaQuery.textScaler),
          ),
          child: child!,
        );
      },
      home: HomeScreen(
        connManager: widget.connManager,
        turnApplicationController: _turnApplicationController,
        shareIntents: widget.shareIntents,
        launchIntents: widget.launchIntents,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_turnApplicationController.close());
    super.dispose();
  }
}

/// Brand header used across screens.
class HermesHeader extends StatelessWidget {
  final String? subtitle;
  const HermesHeader({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(color: Color(0xFFD4AF37), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'HERMES',
            style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFD4AF37),
              letterSpacing: 6,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ConnectionManager connManager;
  final GatewayTurnApplicationController turnApplicationController;
  final AndroidShareIntentService? shareIntents;
  final AndroidLaunchIntentService? launchIntents;
  final Future<String?> Function()? pickBackupFile;
  final Future<ConfigImportResult> Function(
    String contents,
    String passphrase,
    ConfigImportMode mode,
  )?
  importBackup;

  const HomeScreen({
    required this.connManager,
    required this.turnApplicationController,
    this.shareIntents,
    this.launchIntents,
    this.pickBackupFile,
    this.importBackup,
    super.key,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<SavedConnection> _connections = [];
  bool _autoNavigated = false;
  static const String _lastConnectionKey = 'last_connection_id';

  void _refresh() {
    setState(() => _connections = widget.connManager.getConnections());
  }

  /// Public only so the import flow and its widget test can refresh Home after
  /// restoring connections without restarting the process.
  void refreshConnections() => _refresh();

  ConfigBackupIo get _backupIo =>
      ConfigBackupIo(connectionManager: widget.connManager);

  Future<void> _showRestoreConfig() async {
    String? contents;
    try {
      contents =
          await (widget.pickBackupFile?.call() ?? _backupIo.pickBackupFile());
    } catch (error) {
      if (!mounted) return;
      _showRestoreError(error);
      return;
    }
    if (contents == null || !mounted) return;

    final choice = await showModalBottomSheet<ImportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ImportOptionsSheet(),
    );
    if (choice == null || !mounted) return;

    try {
      final importer = widget.importBackup ?? _backupIo.importEncrypted;
      final result = await importer(contents, choice.passphrase, choice.mode);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.summary)));
    } catch (error) {
      if (!mounted) return;
      _showRestoreError(error);
    }
  }

  void _showRestoreError(Object error) {
    final message = error is ConfigBackupException
        ? error.message
        : '无法恢复备份。';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _closeDialogAndRefresh(BuildContext dialogContext) async {
    // Let editable controls detach from the IME before removing their route.
    // Rebuilding HomeScreen while the dialog still owns focus can deactivate
    // inherited dependencies out of order on Android.
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.shareIntents?.pendingShare.addListener(_onSharedText);
    widget.launchIntents?.pendingQuickChat.addListener(_onQuickChat);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSharedText();
      _onQuickChat();
    });
  }

  SavedConnection? _connectionForExternalAction() {
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    final preferred = _connections
        .where((connection) => connection.id == lastId)
        .firstOrNull;
    return preferred ?? (_connections.length == 1 ? _connections.single : null);
  }

  void _onSharedText() {
    if (!mounted || widget.shareIntents?.pendingShare.value == null) return;
    final connection = _connectionForExternalAction();
    if (connection == null) return;
    _autoNavigated = true;
    _navigateToWorkspace(connection);
  }

  void _onQuickChat() {
    if (!mounted || widget.launchIntents?.pendingQuickChat.value != true) {
      return;
    }
    final connection = _connectionForExternalAction();
    if (connection == null) return;
    _autoNavigated = true;
    _navigateToWorkspace(connection);
  }

  @override
  void dispose() {
    widget.shareIntents?.pendingShare.removeListener(_onSharedText);
    widget.launchIntents?.pendingQuickChat.removeListener(_onQuickChat);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoNavigated && _connections.isNotEmpty) {
      _autoNavigated = true;
      _maybeAutoNavigate();
    }
  }

  void _maybeAutoNavigate() {
    // The share listener owns this route so the regular last-connection
    // auto-navigation cannot stack a second Workspace above the shared draft.
    if (widget.shareIntents?.pendingShare.value != null ||
        widget.launchIntents?.pendingQuickChat.value == true) {
      return;
    }
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    if (lastId == null) return;
    final conn = _connections.where((c) => c.id == lastId).firstOrNull;
    if (conn == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToWorkspace(conn);
    });
  }

  void _navigateToWorkspace(SavedConnection conn) {
    widget.connManager.prefs.setString(_lastConnectionKey, conn.id);
    final sharedPayload = widget.shareIntents?.takePendingShare();
    final initialQuickChat =
        widget.launchIntents?.takePendingQuickChat() == true &&
        sharedPayload == null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkspaceScreen(
          connection: conn,
          turnApplicationController: widget.turnApplicationController,
          initialSharedPayload: sharedPayload,
          initialQuickChat: initialQuickChat,
        ),
      ),
    );
  }

  void _showAddDialog() => _showConnectionDialog();

  void _showEditConnectionDialog(SavedConnection conn) {
    _showConnectionDialog(existing: conn);
  }

  void _showConnectionDialog({SavedConnection? existing}) {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(
        initialConnection: existing,
        onSave:
            (
              label,
              host,
              port,
              apiKey, {
              gatewayPrefix,
              dashboardPrefix,
              dashboardProxied = false,
              desktopGatewayUrl,
              dashboardPort,
              dashboardUsername,
              dashboardPassword,
            }) async {
              if (existing == null) {
                await widget.connManager.saveConnection(
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  desktopGatewayUrl: desktopGatewayUrl,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                );
              } else {
                await widget.connManager.updateConnection(
                  existing.id,
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  desktopGatewayUrl: desktopGatewayUrl,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                );
              }
              _refresh();
            },
      ),
    );
  }

  void _showApiKeyDialog(SavedConnection conn) {
    final ctrl = TextEditingController(text: conn.apiKey);
    bool validating = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('更新 API 密钥'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'API 密钥',
                  hintText: '来自 ~/.hermes/.env 的 API_SERVER_KEY',
                ),
                obscureText: true,
                enabled: !validating,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: validating ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: validating
                  ? null
                  : () async {
                      final key = ctrl.text.trim();
                      if (key.isEmpty) return;

                      setDialogState(() {
                        validating = true;
                        error = null;
                      });

                      try {
                        final baseUrl = conn.baseUrl;
                        final client = ApiClient(
                          baseUrl: baseUrl,
                          apiKey: key,
                          pathPrefix: conn.gatewayPrefix ?? '',
                        );
                        final result = await client.checkHealth();
                        client.close();

                        if (!ctx.mounted) return;

                        if (result.isHealthy) {
                          await widget.connManager.updateApiKey(conn.id, key);
                          if (!ctx.mounted) return;
                          await _closeDialogAndRefresh(ctx);
                        } else {
                          setDialogState(() {
                            error = result.userMessage(apiKeyProvided: true);
                            validating = false;
                          });
                        }
                      } on CredentialStorageException {
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error = '无法安全地保存 API 密钥。';
                          validating = false;
                        });
                      } catch (_) {
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error = '无法连接到 ${conn.host}:${conn.port}。';
                          validating = false;
                        });
                      }
                    },
              child: validating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDashboardAuthDialog(SavedConnection conn) {
    final gatewayPrefixCtrl = TextEditingController(
      text: conn.gatewayPrefix ?? '',
    );
    final dashboardPrefixCtrl = TextEditingController(
      text: conn.dashboardPrefix ?? '',
    );
    final portCtrl = TextEditingController(
      text: conn.dashboardPortOverride?.toString() ?? '',
    );
    final userCtrl = TextEditingController(text: conn.dashboardUsername ?? '');
    final passCtrl = TextEditingController(text: conn.dashboardPassword ?? '');
    var proxied = conn.dashboardProxied;
    bool validating = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('仪表盘 / 代理设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '用于托管路径前缀，以及设置、记忆、技能和定时任务标签页。'
                    '开放仪表盘可将用户名/密码留空；若反向代理已注入仪表盘认证，'
                    '请启用代理模式。',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
                if (error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: gatewayPrefixCtrl,
                  decoration: const InputDecoration(
                    labelText: '网关路径前缀',
                    hintText: '例如 /profile/peter',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dashboardPrefixCtrl,
                  decoration: const InputDecoration(
                    labelText: '仪表盘路径前缀',
                    hintText: '例如 /dashboard',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: proxied,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('仪表盘位于代理之后'),
                  subtitle: const Text(
                    '由代理注入认证，应用发送干净请求',
                  ),
                  onChanged: validating
                      ? null
                      : (v) => setDialogState(() => proxied = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(
                    labelText: '仪表盘端口',
                    hintText: '留空使用默认端口 (9119)',
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    labelText: '用户名（可选）',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                    labelText: '密码（可选）',
                  ),
                  obscureText: true,
                  enabled: !validating,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: validating ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: validating
                  ? null
                  : () async {
                      final portText = portCtrl.text.trim();
                      final port = portText.isEmpty
                          ? null
                          : int.tryParse(portText);
                      if (portText.isNotEmpty && (port == null || port <= 0)) {
                        setDialogState(() => error = '端口号无效。');
                        return;
                      }
                      final user = userCtrl.text.trim();
                      final pass = passCtrl.text.trim();
                      final gatewayPrefix = gatewayPrefixCtrl.text.trim();
                      final dashboardPrefix = dashboardPrefixCtrl.text.trim();

                      setDialogState(() {
                        validating = true;
                        error = null;
                      });

                      if (gatewayPrefix != (conn.gatewayPrefix ?? '')) {
                        final apiClient = ApiClient(
                          baseUrl: conn.baseUrl,
                          apiKey: conn.apiKey,
                          pathPrefix: gatewayPrefix,
                        );
                        final result = await apiClient.checkHealth();
                        apiClient.close();
                        if (!ctx.mounted) return;
                        if (!result.isHealthy) {
                          setDialogState(() {
                            error = result.userMessage(
                              apiKeyProvided: conn.apiKey.isNotEmpty,
                            );
                            validating = false;
                          });
                          return;
                        }
                      }

                      final client = DashboardClient(
                        host: conn.host,
                        port: port ?? conn.dashboardPort,
                        useHttps: conn.useHttps,
                        pathPrefix: dashboardPrefix,
                        proxied: proxied,
                        username: user.isEmpty ? null : user,
                        password: pass.isEmpty ? null : pass,
                      );
                      try {
                        await client.getModelInfo();
                        client.close();
                        if (!ctx.mounted) return;
                        await widget.connManager.updateDashboardAuth(
                          conn.id,
                          dashboardPort: port,
                          username: user,
                          password: pass,
                          gatewayPrefix: gatewayPrefix,
                          dashboardPrefix: dashboardPrefix,
                          dashboardProxied: proxied,
                        );
                        if (!ctx.mounted) return;
                        await _closeDialogAndRefresh(ctx);
                      } on CredentialStorageException {
                        client.close();
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error =
                              '无法安全地保存仪表盘凭据。';
                          validating = false;
                        });
                      } catch (_) {
                        client.close();
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error =
                              '无法连接或认证 ${conn.host}:${port ?? conn.dashboardPort} '
                              '的仪表盘。请检查端口和凭据。';
                          validating = false;
                        });
                      }
                    },
              child: validating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      gatewayPrefixCtrl.dispose();
      dashboardPrefixCtrl.dispose();
      portCtrl.dispose();
      userCtrl.dispose();
      passCtrl.dispose();
    });
  }

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.router, color: Color(0xFFD4AF37)),
        title: Text(conn.label),
        subtitle: Text(
          '${conn.host}:${conn.port}${conn.gatewayPrefix != null && conn.gatewayPrefix!.isNotEmpty ? conn.gatewayPrefix! : ''}'
          '  \u2022  密钥: ${conn.apiKey.isNotEmpty ? "\u2713" : "\u2717"}',
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') {
              try {
                await widget.connManager.deleteConnection(conn.id);
                if (mounted) _refresh();
              } on CredentialStorageException {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '无法安全地删除该连接。',
                    ),
                  ),
                );
              }
            } else if (v == 'edit') {
              _showEditConnectionDialog(conn);
            } else if (v == 'apikey') {
              _showApiKeyDialog(conn);
            } else if (v == 'dashboard') {
              _showDashboardAuthDialog(conn);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑连接')),
            const PopupMenuItem(value: 'apikey', child: Text('更新 API 密钥')),
            const PopupMenuItem(
              value: 'dashboard',
              child: Text('仪表盘 / 代理设置'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: () => _navigateToWorkspace(conn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HERMES',
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_connections.isNotEmpty)
            IconButton(
              key: const Key('home_restore_config_menu'),
              tooltip: '恢复配置',
              onPressed: _showRestoreConfig,
              icon: const Icon(Icons.settings_backup_restore),
            ),
        ],
      ),
      body: _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, size: 64, color: Colors.grey[800]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无连接',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击 + 添加远程 Hermes 网关\n（API Server，端口 8642）',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const Key('home_restore_config_button'),
                    onPressed: _showRestoreConfig,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('恢复配置'),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                if (Responsive.isTablet(context)) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Responsive.gridColumns(context),
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _connections.length,
                    itemBuilder: (_, i) =>
                        _buildConnectionCard(_connections[i]),
                  );
                }
                return ListView.builder(
                  itemCount: _connections.length,
                  itemBuilder: (_, i) => _buildConnectionCard(_connections[i]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加连接',
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  final SavedConnection? initialConnection;
  final Future<void> Function(
    String label,
    String host,
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
  })
  onSave;
  const _AddDialog({required this.onSave, this.initialConnection});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _apiKey;
  late final TextEditingController _gatewayPrefix;
  late final TextEditingController _dashboardPrefix;
  late final TextEditingController _dashPort;
  late final TextEditingController _dashUser;
  late final TextEditingController _dashPass;
  late final TextEditingController _desktopGatewayUrl;
  late bool _showDashboard;
  late bool _dashboardProxied;
  bool _validating = false;
  String? _error;

  bool get _isEditing => widget.initialConnection != null;

  @override
  void initState() {
    super.initState();
    final conn = widget.initialConnection;
    _label = TextEditingController(text: conn?.label ?? '主页');
    _host = TextEditingController(
      text: conn == null
          ? ''
          : conn.useHttps
          ? 'https://${conn.host}'
          : conn.host,
    );
    _port = TextEditingController(text: (conn?.port ?? 8642).toString());
    _apiKey = TextEditingController(text: conn?.apiKey ?? '');
    _gatewayPrefix = TextEditingController(text: conn?.gatewayPrefix ?? '');
    _dashboardPrefix = TextEditingController(text: conn?.dashboardPrefix ?? '');
    _dashPort = TextEditingController(
      text: conn?.dashboardPortOverride?.toString() ?? '',
    );
    _dashUser = TextEditingController(text: conn?.dashboardUsername ?? '');
    _dashPass = TextEditingController(text: conn?.dashboardPassword ?? '');
    // The Desktop Gateway URL is an advanced override, not a default: the
    // app derives the JSON-RPC/WebSocket origin from the dashboard details
    // when this field is blank. Pre-filling a hardcoded example here made
    // every new connection silently point at a dead host and wedge Project
    // loading. See docs/ANDROID_FINAL_UI_SPEC_DRAFT.md.
    _desktopGatewayUrl = TextEditingController(
      text: conn?.desktopGatewayUrl ?? '',
    );
    _dashboardProxied = conn?.dashboardProxied ?? false;
    _showDashboard =
        conn?.gatewayPrefix?.isNotEmpty == true ||
        conn?.dashboardPrefix?.isNotEmpty == true ||
        conn?.dashboardPortOverride != null ||
        conn?.dashboardUsername?.isNotEmpty == true ||
        conn?.dashboardPassword?.isNotEmpty == true ||
        _dashboardProxied ||
        conn?.desktopGatewayUrl?.isNotEmpty == true;
  }

  Future<void> _validateAndSave() async {
    final label = _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 8642;
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final dashboardPrefix = _dashboardPrefix.text.trim();

    if (label.isEmpty || host.isEmpty || port <= 0) return;

    setState(() {
      _validating = true;
      _error = null;
    });

    try {
      final normalized = SavedConnection.normalizeHostAndPort(host, port);
      final baseUrl = SavedConnection(
        id: '',
        label: '',
        host: normalized.host,
        port: normalized.port,
        apiKey: '',
        useHttps: normalized.useHttps,
      ).baseUrl;
      final client = ApiClient(
        baseUrl: baseUrl,
        apiKey: apiKey,
        pathPrefix: gatewayPrefix,
      );
      final result = await client.checkHealth();
      client.close();

      if (!mounted) return;

      if (!result.isHealthy) {
        setState(() {
          _error = result.userMessage(apiKeyProvided: apiKey.isNotEmpty);
          _validating = false;
        });
        return;
      }

      final dashPortText = _dashPort.text.trim();
      final dashUser = _dashUser.text.trim();
      final dashPass = _dashPass.text.trim();
      final desktopGatewayUrl = _desktopGatewayUrl.text.trim();
      final dashPort = dashPortText.isEmpty ? null : int.tryParse(dashPortText);

      // If the user supplied any dashboard details, validate them before saving
      // (parity with the Dashboard Login dialog). The gateway is already known
      // good at this point.
      if (dashPortText.isNotEmpty ||
          dashUser.isNotEmpty ||
          dashPass.isNotEmpty ||
          dashboardPrefix.isNotEmpty ||
          _dashboardProxied) {
        final dashClient = DashboardClient(
          host: normalized.host,
          port: SavedConnection(
            id: '',
            label: '',
            host: normalized.host,
            port: normalized.port,
            apiKey: '',
            useHttps: normalized.useHttps,
            dashboardPortOverride: dashPort,
          ).dashboardPort,
          useHttps: normalized.useHttps,
          pathPrefix: dashboardPrefix,
          proxied: _dashboardProxied,
          username: dashUser.isEmpty ? null : dashUser,
          password: dashPass.isEmpty ? null : dashPass,
        );
        try {
          await dashClient.getModelInfo();
        } catch (_) {
          dashClient.close();
          if (!mounted) return;
          setState(() {
            _error =
                '网关已连接，但无法访问或认证仪表盘。'
                '请检查仪表盘信息，或清空这些信息以跳过。';
            _validating = false;
            _showDashboard = true;
          });
          return;
        }
        dashClient.close();
        if (!mounted) return;
      }

      await widget.onSave(
        label,
        host,
        port,
        apiKey,
        gatewayPrefix: gatewayPrefix.isEmpty ? null : gatewayPrefix,
        dashboardPrefix: dashboardPrefix.isEmpty ? null : dashboardPrefix,
        dashboardProxied: _dashboardProxied,
        desktopGatewayUrl: desktopGatewayUrl.isEmpty ? null : desktopGatewayUrl,
        dashboardPort: dashPort,
        dashboardUsername: dashUser.isEmpty ? null : dashUser,
        dashboardPassword: dashPass.isEmpty ? null : dashPass,
      );
      if (mounted) Navigator.pop(context);
    } on CredentialStorageException {
      if (!mounted) return;
      setState(() {
        _error = '无法安全地保存该连接。';
        _validating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '无法连接到 $host:$port。请检查主机和端口。';
        _validating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing ? '编辑网关连接' : '添加网关连接',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: '标签'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: '主机',
                hintText:
                    '192.168.1.50、100.x.y.z 或 hermes-machine.tailnet.ts.net',
              ),
              keyboardType: TextInputType.text,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '8642（API Server）',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKey,
              decoration: const InputDecoration(
                labelText: 'API 密钥',
                hintText: '来自 ~/.hermes/.env 的 API_SERVER_KEY',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _validating
                  ? null
                  : () => setState(() => _showDashboard = !_showDashboard),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showDashboard ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '自定义代理和仪表盘信息',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_showDashboard) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _gatewayPrefix,
                decoration: const InputDecoration(
                  labelText: '网关路径前缀',
                  hintText:
                      '例如 /profile/peter（/api/ 和 /v1/ 之前的代理路径）',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashboardPrefix,
                decoration: const InputDecoration(
                  labelText: '仪表盘路径前缀',
                  hintText: '例如 /dashboard（/api/ 之前的代理路径）',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _dashboardProxied,
                contentPadding: EdgeInsets.zero,
                title: const Text('仪表盘位于代理之后'),
                subtitle: const Text(
                  'Nginx 注入认证 — 应用发送干净请求',
                ),
                onChanged: (v) => setState(() => _dashboardProxied = v),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '可选，用于记忆/定时任务/技能/设置标签页。留空则使用默认'
                  '仪表盘端口 (9119) 且无需登录。',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
              TextField(
                controller: _dashPort,
                decoration: const InputDecoration(
                  labelText: '仪表盘端口',
                  hintText: '留空使用默认端口 (9119)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashUser,
                decoration: const InputDecoration(
                  labelText: '仪表盘用户名（可选）',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashPass,
                decoration: const InputDecoration(
                  labelText: '仪表盘密码（可选）',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desktopGatewayUrl,
                decoration: const InputDecoration(
                  labelText: '桌面网关 URL（可选）',
                  hintText: 'https://hermes-desktop.example.lan',
                  helperText:
                      '通过桌面远程网关发送文件附件。',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _validating ? null : _validateAndSave,
          child: _validating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? '保存修改' : '连接'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _apiKey.dispose();
    _gatewayPrefix.dispose();
    _dashboardPrefix.dispose();
    _dashPort.dispose();
    _dashUser.dispose();
    _dashPass.dispose();
    _desktopGatewayUrl.dispose();
    super.dispose();
  }
}
