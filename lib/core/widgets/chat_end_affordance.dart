import 'package:flutter/material.dart';

/// Accessible floating action that returns a chat to its current end.
class ChatEndAffordance extends StatelessWidget {
  static const buttonKey = Key('chat-go-to-end');
  static const countKey = Key('chat-new-message-count');

  final int newMessageCount;
  final VoidCallback onPressed;

  const ChatEndAffordance({
    required this.newMessageCount,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasNewMessages = newMessageCount > 0;
    final indicatorText = hasNewMessages ? '$newMessageCount 条新消息' : '最新';
    final semanticsValue = switch (newMessageCount) {
      0 => '没有新消息',
      1 => '1 条新消息',
      _ => '$newMessageCount 条新消息',
    };

    return Semantics(
      label: '回到底部',
      value: semanticsValue,
      button: true,
      excludeSemantics: true,
      child: FloatingActionButton.extended(
        key: buttonKey,
        heroTag: null,
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_downward_rounded),
        label: Text(indicatorText, key: countKey),
      ),
    );
  }
}
