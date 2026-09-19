import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// A file that now lives in storage the student can reach outside the app.
class SavedDownload {
  const SavedDownload({
    required this.uri,
    required this.fileName,
    required this.mimeType,
  });

  /// Android: a `content://` URI (MediaStore or FileProvider).
  /// iOS: an absolute path inside the app's Files-visible Documents folder.
  final String uri;
  final String fileName;
  final String mimeType;
}

class DeviceDownloadPermissionDenied implements Exception {
  const DeviceDownloadPermissionDenied();
}

/// Saves finished downloads where the device's own file manager shows them.
///
/// Android 10+ writes through MediaStore into `Download/Learnoo` (no storage
/// permission needed); Android 9 and below writes the same folder directly
/// after asking for the storage permission. iOS keeps a private copy that the
/// caller hands to the system share sheet ("Save to Files").
class DeviceDownloads {
  const DeviceDownloads();

  static const MethodChannel _channel = MethodChannel('com.learnoo.downloads');

  /// Sub-folder name, shown to the student in the success message.
  static const String folderName = 'Learnoo';

  static String mimeTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'zip':
        return 'application/zip';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  Future<SavedDownload> save({
    required File source,
    required String fileName,
    required String mimeType,
  }) async {
    if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk < 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) throw const DeviceDownloadPermissionDenied();
      }
      final saved = await _channel.invokeMapMethod<String, String>(
        'saveToDownloads',
        {
          'sourcePath': source.path,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );
      if (saved == null || (saved['uri'] ?? '').isEmpty) {
        throw const FileSystemException('Download could not be saved');
      }
      return SavedDownload(
        uri: saved['uri']!,
        fileName: saved['name'] ?? fileName,
        mimeType: mimeType,
      );
    }

    // iOS has no shared Downloads folder. The file is kept in app support (not
    // Documents, which would expose the app's database and offline videos if
    // file sharing were switched on) and the screen then offers the system
    // "Save to Files" sheet.
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/$folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = await _uniqueFile(dir, fileName);
    await source.copy(target.path);
    return SavedDownload(
      uri: target.path,
      fileName: target.uri.pathSegments.last,
      mimeType: mimeType,
    );
  }

  /// Opens a saved download in the system viewer. Returns false when no app
  /// on the device can open it.
  Future<bool> open({required String uri, required String mimeType}) async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>(
              'openDownload',
              {'uri': uri, 'mimeType': mimeType},
            ) ??
            false;
      }
      final result = await OpenFile.open(uri, type: mimeType);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  static Future<File> _uniqueFile(Directory dir, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var candidate = File('${dir.path}/$fileName');
    var n = 1;
    while (await candidate.exists()) {
      candidate = File('${dir.path}/$base ($n)$ext');
      n++;
    }
    return candidate;
  }
}
