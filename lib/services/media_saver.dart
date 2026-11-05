import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'download_manager.dart';

/// Saves to the Photos app / Android gallery (album "LocalDrop") and keeps
/// ZIP exports in the app's documents folder (visible in the Files app on
/// iOS and shareable on Android).
class GalMediaSaver implements MediaSaver {
  static const album = 'LocalDrop';

  @override
  Future<String> saveToGallery(String path, {required bool isVideo}) async {
    if (!await Gal.hasAccess(toAlbum: true)) {
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw const FileSystemException('Allow LocalDrop to add photos to your gallery in Settings');
      }
    }
    try {
      if (isVideo) {
        await Gal.putVideo(path, album: album);
      } else {
        await Gal.putImage(path, album: album);
      }
    } on GalException catch (e) {
      throw FileSystemException(switch (e.type) {
        GalExceptionType.accessDenied => 'Permission to save to the gallery was denied',
        GalExceptionType.notEnoughSpace => 'Not enough storage space on this device',
        GalExceptionType.notSupportedFormat => 'This file format cannot be added to the gallery',
        _ => 'Could not save to the gallery',
      });
    }
    return Platform.isIOS ? 'Photos › $album' : 'Gallery › $album';
  }

  @override
  Future<Directory> exportDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/Exports');
  }
}
