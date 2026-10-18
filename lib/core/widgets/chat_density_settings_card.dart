import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/chat_density_preference.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

String _densityLabel(AppLocalizations l10n, ChatDensity density) {
  return switch (density) {
    ChatDensity.comfortable => l10n.chat_density_comfortable,
    ChatDensity.compact => l10n.chat_density_compact,
  };
}

String _densityDescription(AppLocalizations l10n, ChatDensity density) {
  return switch (density) {
    ChatDensity.comfortable => l10n.chat_density_comfortable_description,
    ChatDensity.compact => l10n.chat_density_compact_description,
  };
}

/// App-wide chat-density control. It stores only the selected layout
/// preference; connection, profile, and credential data never enter this
/// namespace.
class ChatDensitySettingsCard extends StatefulWidget {
  const ChatDensitySettingsCard({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<ChatDensitySettingsCard> createState() =>
      _ChatDensitySettingsCardState();
}

class _ChatDensitySettingsCardState extends State<ChatDensitySettingsCard> {
  late final ChatDensityStore _store;
  late ChatDensity _density;

  @override
  void initState() {
    super.initState();
    _store = ChatDensityStore(widget.preferences);
    _density = ChatDensity.fromStorage(
      widget.preferences.getString(ChatDensity.preferenceKey),
    );
  }

  Future<void> _select(ChatDensity density) async {
    if (density != _density) {
      await _store.save(density);
      if (!mounted) return;
      setState(() => _density = density);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showPicker() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.chat_density,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context
                      .l10n
                      .compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins,
                ),
                const SizedBox(height: 8),
                RadioGroup<ChatDensity>(
                  groupValue: _density,
                  onChanged: (value) {
                    if (value != null) _select(value);
                  },
                  child: Column(
                    children: [
                      for (final density in ChatDensity.values)
                        RadioListTile<ChatDensity>(
                          value: density,
                          title: Text(_densityLabel(context.l10n, density)),
                          subtitle: Text(
                            _densityDescription(context.l10n, density),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Semantics(
        label: context.l10n.chat_density_2(
          _densityLabel(context.l10n, _density),
        ),
        button: true,
        child: ExcludeSemantics(
          child: ListTile(
            leading: const Icon(Icons.view_agenda_outlined),
            title: Text(context.l10n.chat_density),
            subtitle: Text(
              context.l10n.chat_density_label_description(
                _densityDescription(context.l10n, _density),
                _densityLabel(context.l10n, _density),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPicker,
          ),
        ),
      ),
    );
  }
}
