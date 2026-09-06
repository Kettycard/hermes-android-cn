/// Compact relative time shared by conversation rows and activity lists.
///
/// The Gateway timestamps are seconds since the epoch; `now` is injectable
/// so window boundaries stay deterministic in widget tests.
String formatRelativeTime(DateTime now, double lastActiveSeconds) {
  final activity = DateTime.fromMillisecondsSinceEpoch(
    (lastActiveSeconds * 1000).round(),
  );
  final elapsed = now.difference(activity);
  if (elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟';
  if (elapsed.inDays < 1) return '${elapsed.inHours} 小时';
  if (elapsed.inDays < 7) return '${elapsed.inDays} 天';
  return '${activity.day}/${activity.month}';
}
