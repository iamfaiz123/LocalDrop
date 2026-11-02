import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/models/models.dart';
import 'package:localdrop/utils/format.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(24 * 1024 * 1024), '24.0 MB');
    expect(formatBytes(1.2 * 1024 * 1024 * 1024), '1.2 GB');
    expect(formatBytes(null), '');
  });

  test('formatTimestamp relative days', () {
    final now = DateTime(2026, 3, 12, 15);
    expect(formatTimestamp(DateTime(2026, 3, 12, 10, 24).millisecondsSinceEpoch, now: now), 'Today, 10:24 AM');
    expect(formatTimestamp(DateTime(2026, 3, 11, 21, 2).millisecondsSinceEpoch, now: now), 'Yesterday, 9:02 PM');
    expect(formatTimestamp(DateTime(2026, 3, 1, 0, 5).millisecondsSinceEpoch, now: now), '1 Mar, 12:05 AM');
  });

  test('parseServerAddress accepts addresses and QR links, rejects junk', () {
    final a = parseServerAddress('192.168.43.20')!;
    expect(a.base.toString(), 'http://192.168.43.20:8080');
    expect(parseServerAddress('10.0.0.5:8081')!.base.port, 8081);
    final q = parseServerAddress('http://172.20.10.1:8080/?sid=${'a' * 32}')!;
    expect(q.base.host, '172.20.10.1');
    expect(q.sessionId, 'a' * 32);
    expect(parseServerAddress('http://h.local:9000/?sid=bad')!.sessionId, isNull);
    expect(parseServerAddress(''), isNull);
    expect(parseServerAddress('not a url'), isNull);
    expect(parseServerAddress('ftp://1.2.3.4'), isNull);
    expect(parseServerAddress('999.1.1.1'), isNull);
  });

  test('initials', () {
    expect(initialsOf('riya kapoor'), 'RK');
    expect(initialsOf('  Aarav '), 'A');
  });

  test('models parse engine JSON', () {
    final m = MediaItem.fromJson({
      'id': 'a' * 32,
      'filename': 'IMG.JPG',
      'mime': 'image/jpeg',
      'kind': 'photo',
      'ext': 'jpg',
      'size': 10,
      'sha256': 'b' * 64,
      'created_at': 5,
      'has_thumbnail': true,
      'uploader': {'id': 'p', 'name': 'Riya', 'initials': 'R', 'avatar_color': 4293781759},
      'favorite': true,
    });
    expect(m.isVideo, isFalse);
    expect(m.uploader.name, 'Riya');
    expect(m.copyWith(favorite: false).favorite, isFalse);
    final s = SessionInfo.fromJson({'id': 'x', 'name': 'Trip', 'host_name': 'A', 'upload_permission': 'host_only'});
    expect(s.uploadsOpen, isFalse);
    expect(s.downloadsOpen, isTrue);
  });
}
