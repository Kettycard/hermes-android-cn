enum GatewaySensitivePromptKind { sudo, secret }

/// A request-ID keyed password or secret prompt emitted by Hermes.
///
/// Values entered by the user are intentionally not part of this model so they
/// cannot be retained alongside chat or connection state.
class GatewaySensitivePromptRequest {
  final GatewaySensitivePromptKind kind;
  final String requestId;
  final String title;
  final String description;
  final String fieldLabel;

  const GatewaySensitivePromptRequest({
    required this.kind,
    required this.requestId,
    required this.title,
    required this.description,
    required this.fieldLabel,
  });

  static GatewaySensitivePromptRequest? fromEventData({
    required GatewaySensitivePromptKind kind,
    required Map<String, dynamic> data,
  }) {
    final requestId = data['request_id']?.toString().trim() ?? '';
    if (requestId.isEmpty) return null;

    if (kind == GatewaySensitivePromptKind.sudo) {
      return GatewaySensitivePromptRequest(
        kind: kind,
        requestId: requestId,
        title: '需要管理员密码',
        description:
            'Hermes 需要待执行终端命令的 sudo 密码。',
        fieldLabel: 'Sudo 密码',
      );
    }

    final envVar = data['env_var']?.toString().trim() ?? '';
    final prompt = data['prompt']?.toString().trim() ?? '';
    return GatewaySensitivePromptRequest(
      kind: kind,
      requestId: requestId,
      title: envVar.isEmpty ? '需要机密值' : envVar,
      description: prompt.isEmpty
          ? 'Hermes 需要待执行技能的机密值。'
          : prompt,
      fieldLabel: envVar.isEmpty ? '机密值' : envVar,
    );
  }
}
