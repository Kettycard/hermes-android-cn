/// Remembers, per logical tool-activity group, whether the user opened or
/// closed its card.
///
/// The card cannot keep this in its own `State`. The chat list is a
/// `ListView.builder`: while a turn streams, assistant text is inserted ahead
/// of the trailing tool card, so the card is rebuilt at a different index, and
/// rows that scroll out of the viewport are evicted altogether. Either way the
/// `State` — and with it the tap — is discarded, and the card falls back to its
/// default expansion in the middle of the run the user wanted closed.
///
/// Keyed by the group id from `ChatToolActivityGroup`, the choice follows the
/// group instead of the slot it occupies.
class ToolActivityGroupPins {
  final Map<String, bool> _pins = <String, bool>{};

  /// The choice this user made for [groupId], or `null` if they never touched
  /// that card.
  bool? operator [](String groupId) => _pins[groupId];

  void pin(String groupId, bool expanded) => _pins[groupId] = expanded;

  /// Forgets every choice, for when the conversation itself is replaced.
  void clear() => _pins.clear();

  int get length => _pins.length;
}
