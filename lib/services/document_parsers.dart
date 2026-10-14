import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'file_readers.dart';

// ---------- Модель содержимого текстового документа ----------

class DocRun {
  const DocRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
}

sealed class DocBlock {}

class DocParagraph extends DocBlock {
  DocParagraph(
    this.runs, {
    this.headingLevel = 0,
    this.bullet = false,
    this.id,
  });

  final List<DocRun> runs;

  /// 0 — обычный текст, 1..3 — заголовки.
  final int headingLevel;
  final bool bullet;

  /// Номер абзаца (w:p) в файле Word — нужен, чтобы сохранить правку.
  /// null — абзац нельзя редактировать.
  final int? id;

  String get text => runs.map((r) => r.text).join();
}

class DocTable extends DocBlock {
  DocTable(this.rows);

  final List<List<DocCell>> rows;
}

class DocCell {
  DocCell(this.paragraphs);

  DocCell.text(String text)
    : paragraphs = [
        DocParagraph([DocRun(text)]),
      ];

  final List<DocParagraph> paragraphs;

  String get text => paragraphs.map((p) => p.text).join('\n').trim();
}

class DocImage extends DocBlock {
  DocImage(this.bytes);

  final Uint8List bytes;
}

/// Документ, разбитый на страницы (для Word — одна длинная страница,
/// для PowerPoint — по странице на слайд).
class DocContent {
  DocContent(this.pages, {this.editable = false});

  final List<DocPage> pages;

  /// Можно ли исправлять текст и сохранять обратно в файл.
  final bool editable;
}

class DocPage {
  DocPage(this.blocks, {this.title});

  final String? title;
  final List<DocBlock> blocks;
}

final Map<String, Future<DocContent>> _docCache = {};

/// Читает .docx / .pptx / .rtf в общий формат для показа внутри программы.
/// Сбрасывает кэш после сохранения файла.
void forgetDocument(String path) => _docCache.remove(path);

Future<DocContent> readDocument(String path) {
  return _docCache.putIfAbsent(path, () async {
    final bytes = await File(path).readAsBytes();
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'docx':
        return parseDocx(bytes);
      case 'pptx':
        return parsePptx(bytes);
      case 'rtf':
        return DocContent([DocPage(_textToBlocks(parseRtf(bytes)))]);
      default:
        throw UnsupportedError('Формат .$ext не поддерживается');
    }
  });
}

List<DocBlock> _textToBlocks(String text) => [
  for (final line in text.split('\n')) DocParagraph([DocRun(line)]),
];

// ---------- Word (.docx) ----------

/// Все абзацы документа по порядку — по этому номеру правка
/// потом находит нужный абзац при сохранении.
List<XmlElement> docxParagraphs(XmlDocument document) =>
    document.findAllElements('w:p').toList();

/// Фрагменты текста, которые принадлежат именно этому абзацу
/// (без вложенных надписей/текстовых полей).
List<XmlElement> docxOwnRuns(XmlElement p) => p
    .findAllElements('w:r')
    .where(
      (r) =>
          r.ancestors.whereType<XmlElement>().firstWhere(
            (a) => a.qualifiedName == 'w:p',
          ) ==
          p,
    )
    .toList();

DocContent parseDocx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final document = _readXml(archive, 'word/document.xml');
  if (document == null) throw const FormatException('Это не файл Word');
  final media = _relationshipMedia(
    archive,
    'word/_rels/document.xml.rels',
    'word/',
  );
  final ids = Map<XmlElement, int>.identity();
  final all = docxParagraphs(document);
  for (var i = 0; i < all.length; i++) {
    ids[all[i]] = i;
  }

  final body = document.findAllElements('w:body').firstOrNull;
  final blocks = <DocBlock>[];
  for (final child in body?.childElements ?? <XmlElement>[]) {
    switch (child.qualifiedName) {
      case 'w:p':
        blocks.addAll(_docxParagraph(child, media, ids));
      case 'w:tbl':
        blocks.add(_docxTable(child, media, ids));
      case 'w:sdt':
        // Блок оглавления/элементов управления содержимым.
        for (final p in child.findAllElements('w:p')) {
          blocks.addAll(_docxParagraph(p, media, ids));
        }
    }
  }
  return DocContent([DocPage(blocks)], editable: true);
}

List<DocBlock> _docxParagraph(
  XmlElement p,
  Map<String, Uint8List> media,
  Map<XmlElement, int> ids,
) {
  final style =
      p
          .findAllElements('w:pStyle')
          .firstOrNull
          ?.getAttribute('w:val')
          ?.toLowerCase() ??
      '';
  var heading = 0;
  if (style == 'title') {
    heading = 1;
  } else if (style.startsWith('heading') || style.startsWith('заголовок')) {
    heading = (int.tryParse(style.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1)
        .clamp(1, 3);
  }
  final bullet = p.findAllElements('w:numPr').isNotEmpty;

  final runs = <DocRun>[];
  final images = <DocBlock>[];
  for (final r in docxOwnRuns(p)) {
    final rPr = r.getElement('w:rPr');
    bool flag(String name) {
      final e = rPr?.getElement(name);
      if (e == null) return false;
      final v = e.getAttribute('w:val');
      return v == null || (v != '0' && v != 'false' && v != 'none');
    }

    final text = StringBuffer();
    for (final e in r.childElements) {
      switch (e.qualifiedName) {
        case 'w:t':
          text.write(e.innerText);
        case 'w:tab':
          text.write('\t');
        case 'w:br':
        case 'w:cr':
          text.write('\n');
      }
    }
    if (text.isNotEmpty) {
      runs.add(
        DocRun(
          text.toString(),
          bold: flag('w:b'),
          italic: flag('w:i'),
          underline: flag('w:u'),
        ),
      );
    }
    for (final blip in r.findAllElements('a:blip')) {
      final data = media[blip.getAttribute('r:embed')];
      if (data != null) images.add(DocImage(data));
    }
  }
  return [
    DocParagraph(runs, headingLevel: heading, bullet: bullet, id: ids[p]),
    ...images,
  ];
}

DocTable _docxTable(
  XmlElement tbl,
  Map<String, Uint8List> media,
  Map<XmlElement, int> ids,
) {
  final rows = <List<DocCell>>[];
  for (final tr in tbl.findElements('w:tr')) {
    rows.add([
      for (final tc in tr.findElements('w:tc'))
        DocCell([
          for (final p in tc.findAllElements('w:p'))
            ..._docxParagraph(p, media, ids).whereType<DocParagraph>(),
        ]),
    ]);
  }
  return DocTable(rows);
}

// ---------- PowerPoint (.pptx) ----------

DocContent parsePptx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final slideRe = RegExp(r'^ppt/slides/slide(\d+)\.xml$');
  final slides =
      archive.files
          .map((f) => (f.name, slideRe.firstMatch(f.name)))
          .where((e) => e.$2 != null)
          .map((e) => (e.$1, int.parse(e.$2!.group(1)!)))
          .toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));
  if (slides.isEmpty) throw const FormatException('В презентации нет слайдов');

  final pages = <DocPage>[];
  for (final (name, number) in slides) {
    final xml = _readXml(archive, name)!;
    final media = _relationshipMedia(
      archive,
      'ppt/slides/_rels/slide$number.xml.rels',
      'ppt/slides/',
    );
    final blocks = <DocBlock>[];
    for (final tbl in xml.findAllElements('a:tbl')) {
      blocks.add(
        DocTable([
          for (final tr in tbl.findElements('a:tr'))
            [
              for (final tc in tr.findElements('a:tc'))
                DocCell.text(
                  tc.findAllElements('a:t').map((t) => t.innerText).join(),
                ),
            ],
        ]),
      );
    }
    for (final sp in xml.findAllElements('p:sp')) {
      final isTitle = sp
          .findAllElements('p:ph')
          .any((ph) => (ph.getAttribute('type') ?? '').contains('itle'));
      for (final p in sp.findAllElements('a:p')) {
        final runs = [
          for (final r in p.findAllElements('a:r'))
            DocRun(
              r.getElement('a:t')?.innerText ?? '',
              bold: r.getElement('a:rPr')?.getAttribute('b') == '1',
              italic: r.getElement('a:rPr')?.getAttribute('i') == '1',
            ),
        ];
        if (runs.every((r) => r.text.trim().isEmpty)) continue;
        blocks.add(DocParagraph(runs, headingLevel: isTitle ? 2 : 0));
      }
    }
    for (final blip in xml.findAllElements('a:blip')) {
      final data = media[blip.getAttribute('r:embed')];
      if (data != null) blocks.add(DocImage(data));
    }
    pages.add(DocPage(blocks, title: 'Слайд $number'));
  }
  return DocContent(pages);
}

// ---------- RTF ----------

/// Упрощённое извлечение текста из RTF (с поддержкой кириллицы cp1251).
String parseRtf(List<int> bytes) {
  final src = latin1.decode(bytes);
  final out = StringBuffer();
  // Стек групп: true — группа служебная, её текст не выводим.
  final skip = <bool>[false];
  var i = 0;
  int? pendingSkipUnicode;

  while (i < src.length) {
    final ch = src[i];
    if (ch == '{') {
      skip.add(skip.last);
      i++;
    } else if (ch == '}') {
      if (skip.length > 1) skip.removeLast();
      i++;
    } else if (ch == '\\') {
      i++;
      if (i >= src.length) break;
      final next = src[i];
      if (next == '\'') {
        final hex = src.substring(i + 1, (i + 3).clamp(0, src.length));
        if (pendingSkipUnicode != null && pendingSkipUnicode > 0) {
          // Запасной символ после \uN — уже вывели настоящий.
          pendingSkipUnicode--;
        } else if (!skip.last) {
          out.write(_cp1251(int.tryParse(hex, radix: 16) ?? 63));
        }
        i += 3;
      } else if (next == '*') {
        skip[skip.length - 1] = true;
        i++;
      } else if (RegExp(r'[a-zA-Z]').hasMatch(next)) {
        final m = RegExp(r'([a-zA-Z]+)(-?\d+)? ?').matchAsPrefix(src, i)!;
        final word = m.group(1)!;
        final arg = int.tryParse(m.group(2) ?? '');
        i = m.end;
        const destinations = {
          'fonttbl',
          'colortbl',
          'stylesheet',
          'info',
          'pict',
          'header',
          'footer',
          'listtable',
          'listoverridetable',
          'rsidtbl',
          'xmlnstbl',
          'generator',
          'themedata',
          'colorschememapping',
          'latentstyles',
          'datastore',
          'object',
        };
        if (destinations.contains(word)) {
          skip[skip.length - 1] = true;
        } else if (!skip.last) {
          switch (word) {
            case 'par':
            case 'line':
            case 'row':
              out.write('\n');
            case 'tab':
            case 'cell':
              out.write('\t');
            case 'u':
              if (arg != null) {
                out.writeCharCode(arg < 0 ? arg + 65536 : arg);
                pendingSkipUnicode = 1;
              }
          }
        }
      } else {
        if (!skip.last && (next == '\\' || next == '{' || next == '}')) {
          out.write(next);
        }
        i++;
      }
    } else {
      if (ch != '\r' && ch != '\n' && !skip.last) {
        if (pendingSkipUnicode != null && pendingSkipUnicode > 0) {
          pendingSkipUnicode--;
        } else {
          out.write(ch);
        }
      }
      i++;
    }
    if (pendingSkipUnicode == 0) pendingSkipUnicode = null;
  }
  return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _cp1251(int code) {
  if (code >= 0xC0) return String.fromCharCode(0x0410 + code - 0xC0);
  if (code == 0xA8) return 'Ё';
  if (code == 0xB8) return 'ё';
  if (code == 0xAB) return '«';
  if (code == 0xBB) return '»';
  if (code == 0x96) return '–';
  if (code == 0x97) return '—';
  if (code == 0xB9) return '№';
  return String.fromCharCode(code);
}

// ---------- CSV ----------

/// Читает CSV-таблицу (разделитель ; или , определяется автоматически).
Future<List<SheetData>> readCsv(String path) async {
  final text = await readText(path);
  final firstLine = text.split('\n').first;
  final sep =
      ';'.allMatches(firstLine).length >= ','.allMatches(firstLine).length
      ? ';'
      : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n') {
      row.add(cell.toString().replaceAll('\r', ''));
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return [SheetData('CSV', rows)];
}

// ---------- Общее ----------

XmlDocument? _readXml(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) return null;
  return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
}

/// id связи → байты картинки (word/media/..., ppt/media/...).
Map<String, Uint8List> _relationshipMedia(
  Archive archive,
  String relsPath,
  String baseDir,
) {
  final rels = _readXml(archive, relsPath);
  final result = <String, Uint8List>{};
  for (final rel in rels?.findAllElements('Relationship') ?? <XmlElement>[]) {
    final id = rel.getAttribute('Id');
    final target = rel.getAttribute('Target');
    if (id == null ||
        target == null ||
        rel.getAttribute('TargetMode') == 'External') {
      continue;
    }
    final file = archive.findFile(_resolve(baseDir, target));
    if (file != null) result[id] = file.content;
  }
  return result;
}

String _resolve(String baseDir, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = baseDir.split('/')..removeWhere((p) => p.isEmpty);
  for (final seg in target.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.') {
      parts.add(seg);
    }
  }
  return parts.join('/');
}
