import 'file_store.dart';

/// Компьютер: Windows, macOS, Linux — есть мышь, перетаскивание и Ctrl+V.
bool get isDesktop => isDesktopOs;

/// Телефон или планшет: Android, iPhone, iPad (не браузер).
bool get isMobile => isMobileOs;

/// Открывает файл в установленной программе (Word, Excel, просмотрщик PDF…).
/// В веб-версии браузер показывает или скачивает файл.
Future<bool> openInSystemApp(String path, String name) =>
    openFileExternally(path, name);
