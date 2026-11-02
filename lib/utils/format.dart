String formatBytes(num? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  final s = (n >= 100 || i == 0) ? n.round().toString() : n.toStringAsFixed(1);
  return '$s ${units[i]}';
}

String formatSpeed(double bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String _two(int n) => n.toString().padLeft(2, '0');

String formatTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${_two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today, 10:24 AM" / "Yesterday, 9:02 PM" / "12 Mar, 4:10 PM"
String formatTimestamp(int ms, {DateTime? now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, ${formatTime(t)}';
  if (diff == 1) return 'Yesterday, ${formatTime(t)}';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]}, ${formatTime(t)}';
}

String formatDuration(int ms) {
  final d = Duration(milliseconds: ms);
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
  return parts.map((p) => p.characters.first.toUpperCase()).join();
}

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}

/// Accepts "192.168.1.5", "192.168.1.5:8080", "http://…/?sid=…" and returns
/// the base URL plus the optional session id from a QR link.
({Uri base, String? sessionId})? parseServerAddress(String input, {int defaultPort = 8080}) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
  final host = uri.host;
  final isIpv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host)?.groups([1, 2, 3, 4]).every((g) => int.parse(g!) <= 255) ?? false;
  final isHostname = RegExp(r'^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$').hasMatch(host);
  final isIpv6 = host.contains(':') && RegExp(r'^[0-9A-Fa-f:.]+$').hasMatch(host);
  if (!isIpv4 && !isHostname && !isIpv6) return null;
  if (RegExp(r'^[\d.]+$').hasMatch(host) && !isIpv4) return null;
  final base = Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : defaultPort);
  final sid = uri.queryParameters['sid'];
  return (base: base, sessionId: (sid != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(sid)) ? sid : null);
}
