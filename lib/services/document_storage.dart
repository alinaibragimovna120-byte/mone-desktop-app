import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/document_item.dart';
import 'document_editor.dart';
import 'file_store.dart';

/// Хранит копии добавленных файлов и список документов,
/// чтобы после перезапуска программы всё оставалось на месте.
class DocumentStorage {
  late String _filesDir;
  late String _coversDir;
  late String _indexPath;

  Future<void> init() async {
    final root = await storageRoot();
    _filesDir = p.join(root, 'files');
    _coversDir = p.join(root, 'covers');
    _indexPath = p.join(root, 'index.json');
  }

  Future<List<DocumentItem>> load() async {
    if (!fileExists(_indexPath)) return [];
    try {
      final raw =
          jsonDecode(utf8.decode(await readFileBytes(_indexPath))) as List;
      return raw
          .map((e) => DocumentItem.fromJson(e as Map<String, dynamic>))
          .where((d) => fileExists(d.path))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<DocumentItem> docs) async {
    await writeFileBytes(
      _indexPath,
      utf8.encode(jsonEncode(docs.map((d) => d.toJson()).toList())),
    );
  }

  int _lastId = 0;

  /// Время в микросекундах; в браузере часы точны лишь до миллисекунды,
  /// поэтому следим, чтобы два файла подряд не получили один номер.
  String _newId() {
    var id = DateTime.now().microsecondsSinceEpoch;
    if (id <= _lastId) id = _lastId + 1;
    _lastId = id;
    return '$id';
  }

  /// Копирует файл с диска во внутреннее хранилище.
  Future<DocumentItem> importFile(String sourcePath) async =>
      importBytes(p.basename(sourcePath), await readFileBytes(sourcePath));

  /// Сохраняет содержимое файла (например, выбранного в браузере).
  Future<DocumentItem> importBytes(String name, Uint8List bytes) async {
    final id = _newId();
    final path = p.join(_filesDir, '${id}_$name');
    await writeFileBytes(path, bytes);
    return DocumentItem(
      id: id,
      name: name,
      path: path,
      sizeBytes: bytes.length,
      addedAt: DateTime.now(),
    );
  }

  /// Сохраняет картинку из буфера обмена как отдельный документ.
  Future<DocumentItem> importImageBytes(Uint8List bytes) =>
      importBytes('Изображение ${_stamp()}.png', bytes);

  /// [name] нужен только ради расширения (.png, .jpg…).
  Future<String> importCover(String name, Uint8List bytes) async {
    final path = p.join(_coversDir, '${_newId()}${p.extension(name)}');
    await writeFileBytes(path, bytes);
    return path;
  }

  Future<void> delete(DocumentItem doc) async {
    for (final path in [doc.path, originalCopyPath(doc.path), doc.coverPath]) {
      if (path == null) continue;
      try {
        await deleteFile(path);
      } catch (_) {}
    }
  }

  Future<void> removeCover(DocumentItem doc) async {
    final path = doc.coverPath;
    doc.coverPath = null;
    if (path != null) {
      try {
        await deleteFile(path);
      } catch (_) {}
    }
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}-${two(n.minute)}-${two(n.second)}';
  }
}
