import 'package:flutter/services.dart';

import 'file_store.dart';
import 'platform.dart';

/// Файлы, которыми поделились с программой из других приложений
/// (Telegram → «Поделиться» → Mone App). Работает на Android и iPhone.
///
/// Телефон копирует присланный файл во временную папку и передаёт путь;
/// [onFiles] вызывается и для файла, с которым программу запустили,
/// и для файлов, присланных, пока она открыта.
void listenSharedFiles(Future<void> Function(List<String> paths) onFiles) {
  if (!isMobile) return;
  const channel = MethodChannel('mone/shared_files');

  Future<void> take() async {
    final paths = await channel.invokeListMethod<String>('takeFiles') ?? [];
    if (paths.isEmpty) return;
    await onFiles(paths);
    // Копия уже сохранена в хранилище программы.
    for (final path in paths) {
      try {
        await deleteFile(path);
      } catch (_) {}
    }
  }

  channel.setMethodCallHandler((call) async {
    if (call.method == 'filesAvailable') await take();
  });
  take();
}
