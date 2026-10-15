import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

bool get isDesktopOs =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

bool get isMobileOs => Platform.isAndroid || Platform.isIOS;

/// Папка, где программа хранит свои документы.
Future<String> storageRoot() async =>
    p.join((await getApplicationSupportDirectory()).path, 'mone_documents');

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

/// Записывает файл целиком: сначала во временный, потом подменяет,
/// чтобы при сбое не остался наполовину записанный документ.
Future<void> writeFileBytes(String path, List<int> bytes) async {
  await Directory(p.dirname(path)).create(recursive: true);
  final tmp = File('$path.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(path);
}

bool fileExists(String path) => File(path).existsSync();

Future<int> fileLength(String path) => File(path).length();

Future<void> deleteFile(String path) => File(path).delete();

ImageProvider storedImage(String path) => FileImage(File(path));

PdfDocumentRef storedPdf(String path) => PdfDocumentRefFile(path);

/// Открывает файл в установленной программе (Word, Excel, просмотрщик PDF…).
Future<bool> openFileExternally(String path, String name) async {
  if (isMobileOs) {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }
  return launchUrl(Uri.file(path));
}
