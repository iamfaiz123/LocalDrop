import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

enum LibraryAccess { full, limited, denied }

/// A photo or video in the phone's own library (not yet in the pool).
class DeviceAsset {
  final String id;
  final bool isVideo;
  final DateTime createdAt;
  final Duration duration;
  final int width;
  final int height;
  final Object? native;
  const DeviceAsset({
    required this.id,
    required this.isVideo,
    required this.createdAt,
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
    this.native,
  });
}

class DeviceLibraryException implements Exception {
  final String message;
  const DeviceLibraryException(this.message);
  @override
  String toString() => message;
}

/// Read access to the phone's photo library. Abstract so tests can fake it.
abstract class DeviceLibrary {
  Future<LibraryAccess> requestAccess();

  /// Number of photos + videos (newest first ordering everywhere).
  Future<int> count();
  Future<List<DeviceAsset>> page(int page, int size);
  Future<Uint8List?> thumbnail(DeviceAsset asset, int size);

  /// The original file, untouched (no re-encoding, metadata kept).
  Future<({String path, String name})> original(DeviceAsset asset);
  Future<void> openSettings();

  /// iOS 14+/Android 14+: let the user change which photos LocalDrop sees.
  Future<void> manageLimitedSelection();
}

/// [DeviceLibrary] backed by the `photo_manager` plugin (Android + iOS).
class PhotoManagerLibrary implements DeviceLibrary {
  AssetPathEntity? _all;

  static final _filter = FilterOptionGroup(orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)]);

  @override
  Future<LibraryAccess> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        // ACCESS_MEDIA_LOCATION: without it Android 10+ strips GPS EXIF,
        // which would change the "original" bytes.
        androidPermission: AndroidPermission(type: RequestType.common, mediaLocation: true),
      ),
    );
    _all = null;
    if (state == PermissionState.authorized) return LibraryAccess.full;
    if (state == PermissionState.limited) return LibraryAccess.limited;
    return LibraryAccess.denied;
  }

  Future<AssetPathEntity?> _allPath() async {
    if (_all != null) return _all;
    final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: RequestType.common, filterOption: _filter);
    return _all = paths.isEmpty ? null : paths.first;
  }

  @override
  Future<int> count() async => (await (await _allPath())?.assetCountAsync) ?? 0;

  @override
  Future<List<DeviceAsset>> page(int page, int size) async {
    final path = await _allPath();
    if (path == null) return const [];
    final list = await path.getAssetListPaged(page: page, size: size);
    return [
      for (final e in list)
        if (e.type == AssetType.image || e.type == AssetType.video)
          DeviceAsset(
            id: e.id,
            isVideo: e.type == AssetType.video,
            createdAt: e.createDateTime,
            duration: Duration(seconds: e.duration),
            width: e.width,
            height: e.height,
            native: e,
          ),
    ];
  }

  @override
  Future<Uint8List?> thumbnail(DeviceAsset asset, int size) =>
      (asset.native as AssetEntity).thumbnailDataWithSize(ThumbnailSize.square(size), quality: 85);

  @override
  Future<({String path, String name})> original(DeviceAsset asset) async {
    final e = asset.native as AssetEntity;
    final File? file = await e.originFile;
    if (file == null) {
      final local = await e.isLocallyAvailable(isOrigin: true);
      throw DeviceLibraryException(local
          ? 'This item could not be read from your library.'
          : 'This item is stored in iCloud and is not on this phone. Download it in Photos first.');
    }
    var name = (await e.titleAsync).trim();
    final pathName = file.path.split(Platform.pathSeparator).last;
    if (name.isEmpty) name = pathName;
    if (!name.contains('.') && pathName.contains('.')) name = '$name.${pathName.split('.').last}';
    return (path: file.path, name: name);
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<void> manageLimitedSelection() async {
    await PhotoManager.presentLimited();
    _all = null;
  }
}
