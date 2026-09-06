import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/remote_files_client.dart';
import '../theme/hermes_theme.dart';
import '../widgets/hermes_components.dart';

class FilesScreen extends StatefulWidget {
  final RemoteFilesDataSource files;
  final ValueChanged<String>? onAddToChat;
  final Future<void> Function(RemoteFileDownload download)? onSaveDownload;

  const FilesScreen({
    required this.files,
    this.onAddToChat,
    this.onSaveDownload,
    super.key,
  });

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  RemoteDirectory? _root;
  String? _path;
  List<RemoteFileEntry> _entries = const [];
  RemoteFileEntry? _selected;
  RemoteTextPreview? _preview;
  Object? _error;
  bool _loading = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoot());
  }

  Future<void> _loadRoot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = await widget.files.defaultDirectory();
      if (!mounted) return;
      _root = root;
      await _openDirectory(root.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _openDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
      _preview = null;
    });
    try {
      final entries = await widget.files.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _path = path;
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _openFile(RemoteFileEntry entry) async {
    setState(() {
      _selected = entry;
      _preview = null;
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.files.readText(entry.path);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  String? get _parentPath {
    final path = _path;
    final root = _root?.path;
    if (path == null || root == null || path == root) return null;
    final separator = path.lastIndexOf('/');
    if (separator <= 0) return '/';
    return path.substring(0, separator);
  }

  void _back() {
    if (_selected != null) {
      setState(() {
        _selected = null;
        _preview = null;
        _error = null;
      });
      return;
    }
    final parent = _parentPath;
    if (parent != null) {
      unawaited(_openDirectory(parent));
      return;
    }
    Navigator.maybePop(context);
  }

  Future<void> _download() async {
    final selected = _selected;
    if (selected == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final download = await widget.files.download(selected.path);
      final saver = widget.onSaveDownload;
      if (saver != null) {
        await saver(download);
      } else {
        await FilePicker.platform.saveFile(
          dialogTitle: '保存 ${download.filename}',
          fileName: download.filename,
          bytes: download.bytes,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${download.filename} downloaded')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载失败：$error')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _directoryBody() {
    if (_entries.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.folder_open_outlined,
          title: '文件夹为空',
          message: '此服务器文件夹中没有可见文件。',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _openDirectory(_path!),
      child: ListView.separated(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: HermesSpacing.sm),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return HermesCard(
            padding: const EdgeInsets.symmetric(
              horizontal: HermesSpacing.lg,
              vertical: HermesSpacing.md,
            ),
            onTap: () => entry.isDirectory
                ? unawaited(_openDirectory(entry.path))
                : unawaited(_openFile(entry)),
            child: Row(
              children: [
                Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  color: HermesTokens.of(context).accent,
                ),
                const SizedBox(width: HermesSpacing.md),
                Expanded(child: Text(entry.name)),
                const Icon(Icons.chevron_right),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _previewBody() {
    final selected = _selected!;
    final preview = _preview;
    final tokens = HermesTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(HermesSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(selected.name, style: tokens.typography.section),
          const SizedBox(height: HermesSpacing.sm),
          Wrap(
            spacing: HermesSpacing.sm,
            runSpacing: HermesSpacing.sm,
            children: [
              if (preview != null)
                StatusChip(status: HermesStatus.idle, label: preview.language),
              if (preview?.truncated == true)
                const StatusChip(
                  status: HermesStatus.blocked,
                  label: '预览已截断',
                ),
            ],
          ),
          const SizedBox(height: HermesSpacing.lg),
          Expanded(
            child: HermesCard(
              child: SingleChildScrollView(
                child: SelectableText(
                  preview?.binary == true
                      ? '二进制文件无法预览，请下载后打开。'
                      : preview?.text ?? '预览不可用',
                  style: tokens.typography.body.copyWith(
                    fontFamily: 'monospace',
                    color: tokens.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: HermesSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
                ),
              ),
              if (widget.onAddToChat != null) ...[
                const SizedBox(width: HermesSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onAddToChat!(selected.path);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('文件引用已添加到对话'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('添加到对话'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingSkeleton(rows: 6);
    if (_error != null) {
      return Center(
        child: ErrorState(
          title: _selected == null ? '无法加载文件' : '无法预览文件',
          message: '请检查仪表盘连接后重试。',
          onRetry: _selected == null
              ? () => unawaited(
                  _path == null ? _loadRoot() : _openDirectory(_path!),
                )
              : () => unawaited(_openFile(_selected!)),
        ),
      );
    }
    return _selected == null ? _directoryBody() : _previewBody();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back)),
      title: const Text('文件'),
      bottom: _selected == null && _path != null
          ? PreferredSize(
              preferredSize: const Size.fromHeight(42),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _path!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_root?.branch != null)
                      StatusChip(
                        status: HermesStatus.idle,
                        label: _root!.branch,
                      ),
                  ],
                ),
              ),
            )
          : null,
    ),
    body: _body(),
  );
}
