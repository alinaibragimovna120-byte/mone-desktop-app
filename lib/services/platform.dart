import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// Компьютер: Windows, macOS, Linux — есть мышь, перетаскивание и Ctrl+V.
bool get isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Телефон или планшет: Android, iPhone, iPad.
bool get isMobile => Platform.isAndroid || Platform.isIOS;

/// Открывает файл в установленной программе (Word, Excel, просмотрщик PDF…).
Future<bool> openInSystemApp(String path) async {
  if (isMobile) {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }
  return launchUrl(Uri.file(path));
}
