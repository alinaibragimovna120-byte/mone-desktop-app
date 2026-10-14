import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document_item.dart';
import 'document_editor.dart';

/// Хранит копии добавленных файлов и список документов на диске,
/// чтобы после перезапуска программы всё оставалось на месте.
class DocumentStorage {
  late Directory _filesDir;
  late Directory _coversDir;
  late File _indexFile;

  Future<void> init() async {
    final root = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'mone_documents'),
    );
    _filesDir = Directory(p.join(root.path, 'files'));
    _coversDir = Directory(p.join(root.path, 'covers'));
    _indexFile = File(p.join(root.path, 'index.json'));
    await _filesDir.create(recursive: true);
    await _coversDir.create(recursive: true);
  }

  Future<List<DocumentItem>> load() async {
    if (!await _indexFile.exists()) return [];
    try {
      final raw = jsonDecode(await _indexFile.readAsString()) as List;
      return raw
          .map((e) => DocumentItem.fromJson(e as Map<String, dynamic>))
          .where((d) => File(d.path).existsSync())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<DocumentItem> docs) async {
    await _indexFile.writeAsString(
      jsonEncode(docs.map((d) => d.toJson()).toList()),
    );
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Копирует файл с диска во внутреннее хранилище.
  Future<DocumentItem> importFile(String sourcePath) async {
    final id = _newId();
    final name = p.basename(sourcePath);
    final target = p.join(_filesDir.path, '${id}_$name');
    final copied = await File(sourcePath).copy(target);
    return DocumentItem(
      id: id,
      name: name,
      path: copied.path,
      sizeBytes: await copied.length(),
      addedAt: DateTime.now(),
    );
  }

  /// Сохраняет картинку из буфера обмена как отдельный документ.
  Future<DocumentItem> importImageBytes(Uint8List bytes) async {
    final id = _newId();
    final name = 'Изображение ${_stamp()}.png';
    final file = File(p.join(_filesDir.path, '${id}_$name'));
    await file.writeAsBytes(bytes);
    return DocumentItem(
      id: id,
      name: name,
      path: file.path,
      sizeBytes: bytes.length,
      addedAt: DateTime.now(),
    );
  }

  Future<String> importCover(String sourcePath) async {
    final target = p.join(
      _coversDir.path,
      '${_newId()}${p.extension(sourcePath)}',
    );
    return (await File(sourcePath).copy(target)).path;
  }

  Future<void> delete(DocumentItem doc) async {
    for (final path in [doc.path, originalCopyPath(doc.path), doc.coverPath]) {
      if (path == null) continue;
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> removeCover(DocumentItem doc) async {
    final path = doc.coverPath;
    doc.coverPath = null;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}-${two(n.minute)}-${two(n.second)}';
  }
}
