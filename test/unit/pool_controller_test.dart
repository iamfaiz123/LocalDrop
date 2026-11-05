import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/providers/pool_controller.dart';
import 'package:localdrop/services/device_library.dart';
import 'package:localdrop/services/upload_manager.dart';

import '../support.dart';

void main() {
  late FakeDeviceLibrary lib;
  late RecordingUploads uploads;
  late PoolController pool;

  setUp(() {
    lib = FakeDeviceLibrary(300);
    uploads = RecordingUploads();
    pool = PoolController(library: lib, prefs: memoryPreferences(), uploads: uploads);
  });

  test('deck shows the newest items first; right shares, left skips', () async {
    await pool.open('session-1');
    expect(pool.hasAccess, isTrue);
    expect(pool.current!.id, 'asset-0');
    await pool.shareCurrent();
    pool.skipCurrent();
    await pool.shareCurrent();
    expect(uploads.queued, ['asset-0.jpg', 'asset-2.jpg']);
    expect(pool.shared, {'asset-0', 'asset-2'});
    expect(pool.skipped, {'asset-1'});
    expect(pool.current!.id, 'asset-3');
    expect(pool.current!.isVideo, isTrue);
    expect(pool.remaining, 297);
  });

  test('undo restores a skip, cancels a not-yet-started share, refuses a sent one', () async {
    await pool.open('s');
    pool.skipCurrent();
    expect(await pool.undo(), isTrue);
    expect(pool.current!.id, 'asset-0');
    expect(pool.skipped, isEmpty);

    await pool.shareCurrent();
    expect(await pool.undo(), isTrue);
    expect(uploads.cancelled, ['asset-0.jpg']);
    expect(pool.current!.id, 'asset-0');

    await pool.shareCurrent();
    uploads.tasks.last.state = TransferState.uploading;
    expect(await pool.undo(), isFalse);
    expect(pool.notice, contains('Already sent'));
  });

  test('deck refills across pages and reviewed items never come back', () async {
    final prefs = memoryPreferences();
    pool = PoolController(library: lib, prefs: prefs, uploads: uploads);
    await pool.open('s');
    for (var i = 0; i < 130; i++) {
      pool.skipCurrent();
      await Future<void>.delayed(Duration.zero);
    }
    await pool.shareCurrent();
    expect(pool.current, isNotNull, reason: 'next page loaded automatically');
    await Future<void>.delayed(const Duration(milliseconds: 700)); // debounced save

    final again = PoolController(library: lib, prefs: prefs, uploads: RecordingUploads());
    await again.open('s');
    expect(again.current!.id, 'asset-131');
    expect(again.shared, contains('asset-130'));

    // A different session starts fresh.
    final other = PoolController(library: lib, prefs: prefs, uploads: RecordingUploads());
    await other.open('another-session');
    expect(other.current!.id, 'asset-0');
  });

  test('select mode sends many and skips items already in the pool', () async {
    await pool.open('s');
    await pool.shareCurrent(); // asset-0
    final page = await pool.gridPage(0);
    final n = await pool.sendMany(page.take(4).toList());
    expect(n, 3);
    expect(uploads.queued, ['asset-0.jpg', 'asset-1.jpg', 'asset-2.jpg', 'asset-3.mp4']);
    expect(pool.current!.id, 'asset-4');
  });

  test('unreadable (iCloud-only) items are reported and not marked shared', () async {
    lib.unreadable.add('asset-0');
    await pool.open('s');
    await pool.shareCurrent();
    expect(pool.shared, isEmpty);
    expect(uploads.queued, isEmpty);
    expect(pool.notice, contains('iCloud'));
  });

  test('denied permission exposes no items', () async {
    lib.accessResult = LibraryAccess.denied;
    await pool.open('s');
    expect(pool.hasAccess, isFalse);
    expect(pool.current, isNull);
  });
}
