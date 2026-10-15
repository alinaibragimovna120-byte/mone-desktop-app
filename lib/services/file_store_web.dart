import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:web/web.dart' as web;

/// В браузере нет ни мыши с перетаскиванием файлов из проводника,
/// ни установленных программ — ведём себя как на телефоне.
bool get isDesktopOs => false;

bool get isMobileOs => false;

/// Все файлы лежат в IndexedDB браузера (путь → байты) и при запуске
/// целиком загружаются в память, поэтому читать их можно мгновенно.
const _dbName = 'mone_documents';
const _storeName = 'files';

late web.IDBDatabase _db;
final Map<String, Uint8List> _files = {};

Future<String> storageRoot() async {
  await _open();
  return 'mone_documents';
}

Future<void> _open() async {
  // Просим браузер не удалять данные при нехватке места.
  try {
    await web.window.navigator.storage.persist().toDart;
  } catch (_) {}

  final request = web.window.indexedDB.open(_dbName, 1);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore(_storeName);
  }).toJS;
  _db = (await _result(request)) as web.IDBDatabase;

  final store = _db.transaction(_storeName.toJS).objectStore(_storeName);
  final keys = (await _result(store.getAllKeys())) as JSArray<JSString>;
  final values = (await _result(store.getAll())) as JSArray<JSUint8Array>;
  final keyList = keys.toDart;
  final valueList = values.toDart;
  for (var i = 0; i < keyList.length; i++) {
    _files[keyList[i].toDart] = valueList[i].toDart;
  }
}

Future<JSAny?> _result(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError(request.error?.message ?? 'Ошибка хранилища браузера'),
  )).toJS;
  return done.future;
}

web.IDBObjectStore _writable() =>
    _db.transaction(_storeName.toJS, 'readwrite').objectStore(_storeName);

Future<Uint8List> readFileBytes(String path) async {
  final bytes = _files[path];
  if (bytes == null) throw StateError('Файл не найден: $path');
  return bytes;
}

Future<void> writeFileBytes(String path, List<int> bytes) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  await _result(_writable().put(data.toJS, path.toJS));
  _files[path] = data;
}

bool fileExists(String path) => _files.containsKey(path);

Future<int> fileLength(String path) async => (await readFileBytes(path)).length;

Future<void> deleteFile(String path) async {
  await _result(_writable().delete(path.toJS));
  _files.remove(path);
}

ImageProvider storedImage(String path) => MemoryImage(_files[path]!);

PdfDocumentRef storedPdf(String path) =>
    PdfDocumentRefData(_files[path]!, sourceName: path);

/// В браузере нет установленных программ — отдаём файл браузеру:
/// на iPhone откроется просмотр с кнопкой «Поделиться».
Future<bool> openFileExternally(String path, String name) async {
  final bytes = _files[path];
  if (bytes == null) return false;
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
  (web.HTMLAnchorElement()
        ..href = url
        ..download = name)
      .click();
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return true;
}
