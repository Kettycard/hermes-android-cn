import 'package:flutter/material.dart';

import '../services/android_share_intent_service.dart';
import '../theme/hermes_theme.dart';
import '../utils/new_chat_options.dart';

enum ShareFavoriteAction {
  useAsIs('原样使用', Icons.edit_note_rounded),
  summarize('总结', Icons.summarize_rounded),
  explain('解释', Icons.lightbulb_outline_rounded),
  research('深入研究', Icons.travel_explore_rounded),
  extractTasks('提取任务', Icons.task_alt_rounded),
  remember('记住', Icons.memory_rounded),
  fillFromDocument('从文档填写', Icons.description_outlined);

  final String label;
  final IconData icon;
  const ShareFavoriteAction(this.label, this.icon);
}

String buildSharedPrompt(
  ShareFavoriteAction action,
  String source, {
  bool hasAttachments = false,
}) {
  final text = source.trim();
  if (text.isEmpty && hasAttachments) {
    return switch (action) {
      ShareFavoriteAction.useAsIs => '查看附带的内容。',
      ShareFavoriteAction.summarize => '总结附带的内容。',
      ShareFavoriteAction.explain => '清楚地解释附带的内容。',
      ShareFavoriteAction.research =>
        '研究附带的内容，核实重要论断，并注明来源。',
      ShareFavoriteAction.extractTasks =>
        '从附带的内容中提取决策、截止时间、负责人和可执行的行动项。',
      ShareFavoriteAction.remember =>
        '把附带内容中持久有用的事实保存到记忆，然后确认保留了哪些内容。',
      ShareFavoriteAction.fillFromDocument =>
        '使用附带的内容识别并填写相关文档或表单字段。提交任何内容前请先询问。',
    };
  }
  return switch (action) {
    ShareFavoriteAction.useAsIs => text,
    ShareFavoriteAction.summarize => '总结以下内容：\n\n$text',
    ShareFavoriteAction.explain => '清楚地解释以下内容：\n\n$text',
    ShareFavoriteAction.research =>
      '研究以下内容，核实重要论断，并注明来源：\n\n$text',
    ShareFavoriteAction.extractTasks =>
      '从以下内容中提取决策、截止时间、负责人和可执行的行动项：\n\n$text',
    ShareFavoriteAction.remember =>
      '把以下内容中持久有用的事实保存到记忆，然后确认保留了哪些内容：\n\n$text',
    ShareFavoriteAction.fillFromDocument =>
      '使用以下内容识别并填写相关文档或表单字段。提交任何内容前请先询问：\n\n$text',
  };
}

class ShareTextDecision {
  final ShareFavoriteAction action;
  final NewChatMode mode;

  const ShareTextDecision({required this.action, required this.mode});
}

class ShareTextReviewSheet extends StatefulWidget {
  final String sharedText;
  final List<AndroidSharedFile> sharedFiles;
  final bool projectChatEnabled;

  const ShareTextReviewSheet({
    required this.sharedText,
    this.sharedFiles = const [],
    required this.projectChatEnabled,
    super.key,
  });

  @override
  State<ShareTextReviewSheet> createState() => _ShareTextReviewSheetState();
}

class _ShareTextReviewSheetState extends State<ShareTextReviewSheet> {
  ShareFavoriteAction _action = ShareFavoriteAction.useAsIs;
  NewChatMode _mode = NewChatMode.quickChat;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          HermesSpacing.lg,
          HermesSpacing.lg,
          HermesSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分享到 Hermes',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: HermesSpacing.sm),
                    Text(
                      widget.sharedText.trim().isEmpty
                          ? '没有分享文本'
                          : widget.sharedText,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (widget.sharedFiles.isNotEmpty) ...[
                      const SizedBox(height: HermesSpacing.md),
                      Text(
                        '${widget.sharedFiles.length} 个附件',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: HermesSpacing.xs),
                      for (final file in widget.sharedFiles)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            file.isImage
                                ? Icons.image_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(file.mediaType),
                        ),
                    ],
                    const SizedBox(height: HermesSpacing.lg),
                    Text(
                      '操作',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: HermesSpacing.sm),
                    Wrap(
                      spacing: HermesSpacing.sm,
                      runSpacing: HermesSpacing.sm,
                      children: [
                        for (final action in ShareFavoriteAction.values)
                          ChoiceChip(
                            avatar: Icon(action.icon, size: 18),
                            label: Text(action.label),
                            selected: _action == action,
                            onSelected: (_) => setState(() => _action = action),
                          ),
                      ],
                    ),
                    const SizedBox(height: HermesSpacing.lg),
                    Text(
                      '目标',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    RadioGroup<NewChatMode>(
                      groupValue: _mode,
                      onChanged: (mode) {
                        if (mode != null) setState(() => _mode = mode);
                      },
                      child: Column(
                        children: [
                          const RadioListTile<NewChatMode>(
                            contentPadding: EdgeInsets.zero,
                            title: Text('快捷对话'),
                            subtitle: Text('72 小时后自动归档'),
                            value: NewChatMode.quickChat,
                          ),
                          RadioListTile<NewChatMode>(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('项目对话'),
                            subtitle: Text(
                              widget.projectChatEnabled
                                  ? '下一步选择一个活跃的项目'
                                  : '此网关上没有活跃的项目',
                            ),
                            value: NewChatMode.projectChat,
                            enabled: widget.projectChatEnabled,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: HermesSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: HermesSpacing.sm),
                FilledButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(ShareTextDecision(action: _action, mode: _mode)),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('继续'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
