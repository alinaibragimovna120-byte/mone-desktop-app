import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'document_parsers.dart';
import 'file_readers.dart';
import 'file_store.dart';

/// Сохраняет исправления текста обратно в файлы Word и Excel.
///
/// Файл не пересоздаётся с нуля: меняются только нужные кусочки XML
/// внутри, поэтому шрифты, цвета, рамки, картинки и формулы остаются.
/// Перед первым сохранением рядом кладётся копия исходного файла
/// (`<файл>.orig`), чтобы можно было вернуть всё как было.

String originalCopyPath(String path) => '$path.orig';

bool hasOriginalCopy(String path) => fileExists(originalCopyPath(path));

/// Возвращает файл к состоянию до первого исправления.
Future<void> restoreOriginal(String path) async {
  final orig = originalCopyPath(path);
  if (!fileExists(orig)) return;
  await writeFileBytes(path, await readFileBytes(orig));
  await deleteFile(orig);
  forgetDocument(path);
  forgetSpreadsheet(path);
}

// ---------- Word ----------

/// [edits]: номер абзаца (DocParagraph.id) → новый текст.
Future<void> saveDocxEdits(String path, Map<int, String> edits) async {
  if (edits.isEmpty) return;
  await _rewriteZip(path, (archive) {
    applyDocxEdits(archive, edits);
  });
  forgetDocument(path);
}

void applyDocxEdits(Archive archive, Map<int, String> edits) {
  final doc = readZipXml(archive, 'word/document.xml');
  if (doc == null) throw const FormatException('Это не файл Word');
  final paragraphs = docxParagraphs(doc);
  edits.forEach((id, text) {
    if (id < paragraphs.length) _setParagraphText(paragraphs[id], text);
  });
  _putXml(archive, 'word/document.xml', doc);
}

/// Кусочек текста абзаца: либо `w:t` (можно менять),
/// либо табуляция/перенос строки (один неизменяемый символ).
class _Segment {
  _Segment(this.element, this.text, this.editable);

  final XmlElement element;
  String text;
  final bool editable;
}

void _setParagraphText(XmlElement p, String newText) {
  final segments = <_Segment>[];
  for (final r in docxOwnRuns(p)) {
    for (final e in r.childElements) {
      switch (e.qualifiedName) {
        case 'w:t':
          segments.add(_Segment(e, e.innerText, true));
        case 'w:tab':
          segments.add(_Segment(e, '\t', false));
        case 'w:br':
        case 'w:cr':
          segments.add(_Segment(e, '\n', false));
      }
    }
  }
  final oldText = segments.map((s) => s.text).join();
  if (oldText == newText) return;

  // Меняем только изменившуюся середину, чтобы у остального текста
  // сохранилось оформление (жирный, цвет и т.д.).
  var prefix = 0;
  final maxPrefix = oldText.length < newText.length
      ? oldText.length
      : newText.length;
  while (prefix < maxPrefix && oldText[prefix] == newText[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < maxPrefix - prefix &&
      oldText[oldText.length - 1 - suffix] ==
          newText[newText.length - 1 - suffix]) {
    suffix++;
  }
  final removeEnd = oldText.length - suffix;
  final insert = newText.substring(prefix, newText.length - suffix);

  // Куда вставлять: в кусочек текста, внутри или в конце которого правка.
  _Segment? target;
  var offset = 0;
  var targetStart = 0;
  for (final s in segments) {
    final start = offset;
    final end = offset + s.text.length;
    offset = end;
    if (!s.editable) continue;
    if (start < prefix && prefix <= end) {
      target = s;
      targetStart = start;
      break;
    }
    if (start == prefix && target == null) {
      target = s;
      targetStart = start;
    }
  }

  // Удаляем старый текст из всех задетых кусочков.
  offset = 0;
  for (final s in segments) {
    final start = offset;
    final end = offset + s.text.length;
    offset = end;
    final lo = prefix > start ? prefix : start;
    final hi = removeEnd < end ? removeEnd : end;
    if (lo >= hi) continue;
    if (s.editable) {
      s.text = s.text.replaceRange(lo - start, hi - start, '');
    } else {
      s.text = '';
      s.element.remove();
    }
  }

  if (insert.isNotEmpty) {
    if (target == null) {
      // Подходящего кусочка нет — добавляем новый фрагмент текста.
      final run = XmlElement(XmlName('r', 'w'), [], [
        XmlElement(XmlName('t', 'w')),
      ]);
      final firstRun = docxOwnRuns(p).firstOrNull;
      final rPr = firstRun?.getElement('w:rPr');
      if (rPr != null) run.children.insert(0, rPr.copy());
      if (prefix == 0 && firstRun != null) {
        firstRun.parent!.children.insert(
          firstRun.parent!.children.indexOf(firstRun),
          run,
        );
      } else {
        p.children.add(run);
      }
      target = _Segment(run.getElement('w:t')!, '', true);
      segments.add(target);
      targetStart = prefix;
    }
    final at = (prefix - targetStart).clamp(0, target.text.length);
    target.text = target.text.replaceRange(at, at, insert);
  }

  for (final s in segments.where((s) => s.editable)) {
    _writeRunText(s.element, s.text);
  }
}

/// Записывает текст в `w:t`; переносы строк и табуляции превращает
/// в настоящие `w:br` и `w:tab` Word.
void _writeRunText(XmlElement t, String text) {
  if (!text.contains('\n') && !text.contains('\t')) {
    if (t.innerText != text) {
      t.innerText = text;
      t.setAttribute('xml:space', 'preserve');
    }
    return;
  }
  final parent = t.parent!;
  var index = parent.children.indexOf(t);
  t.remove();
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isEmpty) return;
    final e = XmlElement(
      XmlName('t', 'w'),
      [XmlAttribute(XmlName('space', 'xml'), 'preserve')],
      [XmlText(buffer.toString())],
    );
    parent.children.insert(index++, e);
    buffer.clear();
  }

  for (final ch in text.split('')) {
    if (ch == '\n' || ch == '\t') {
      flush();
      parent.children.insert(
        index++,
        XmlElement(XmlName(ch == '\n' ? 'br' : 'tab', 'w')),
      );
    } else {
      buffer.write(ch);
    }
  }
  flush();
}

// ---------- Excel ----------

/// [edits]: путь к листу (SheetData.xmlPath) → (адрес ячейки "B3" → текст).
Future<void> saveXlsxEdits(
  String path,
  Map<String, Map<String, String>> edits,
) async {
  if (edits.values.every((e) => e.isEmpty)) return;
  await _rewriteZip(path, (archive) => applyXlsxEdits(archive, edits));
  forgetSpreadsheet(path);
}

void applyXlsxEdits(Archive archive, Map<String, Map<String, String>> edits) {
  var formulasRemoved = false;
  edits.forEach((sheetPath, cells) {
    if (cells.isEmpty) return;
    final doc = readZipXml(archive, sheetPath);
    if (doc == null) return;
    final sheetData = xlsxAll(doc, 'sheetData').firstOrNull;
    if (sheetData == null) return;
    cells.forEach((ref, text) {
      formulasRemoved |= _setCell(sheetData, ref, text);
    });
    _putXml(archive, sheetPath, doc);
  });
  if (formulasRemoved) _dropCalcChain(archive);
  _requestRecalculation(archive);
}

/// Возвращает true, если в ячейке была формула и её заменили значением.
bool _setCell(XmlElement sheetData, String ref, String text) {
  final prefix = sheetData.name.prefix;
  XmlElement el(String local) => XmlElement(XmlName(local, prefix));

  final rowNumber = int.parse(ref.replaceAll(RegExp(r'[A-Z]'), ''));
  final col = columnIndex(ref)!;

  // Строка.
  XmlElement? row;
  XmlElement? rowAfter;
  for (final r in sheetData.findElements('row', namespace: '*')) {
    final n = int.tryParse(r.getAttribute('r') ?? '') ?? 0;
    if (n == rowNumber) {
      row = r;
      break;
    }
    if (n > rowNumber) {
      rowAfter = r;
      break;
    }
  }
  if (row == null) {
    row = el('row')..setAttribute('r', '$rowNumber');
    _insertBefore(sheetData, row, rowAfter);
  }

  // Ячейка.
  XmlElement? cell;
  XmlElement? cellAfter;
  for (final c in row.findElements('c', namespace: '*')) {
    final index = columnIndex(c.getAttribute('r')) ?? -1;
    if (index == col) {
      cell = c;
      break;
    }
    if (index > col) {
      cellAfter = c;
      break;
    }
  }
  if (cell == null) {
    cell = el('c')..setAttribute('r', ref);
    _insertBefore(row, cell, cellAfter);
  }

  final oldType = cell.getAttribute('t');
  final wasText = oldType == 's' || oldType == 'inlineStr' || oldType == 'str';
  final hadFormula = cell.getElement('f', namespace: '*') != null;
  for (final child in cell.childElements.toList()) {
    if (const {'f', 'v', 'is'}.contains(child.name.local)) child.remove();
  }
  cell.removeAttribute('t');

  if (text.isEmpty) return hadFormula;
  final number = _asNumber(text);
  if (number != null && !wasText) {
    cell.children.add(el('v')..innerText = number);
  } else {
    cell.setAttribute('t', 'inlineStr');
    cell.children.add(
      el('is')
        ..children.add(
          el('t')
            ..setAttribute('xml:space', 'preserve')
            ..innerText = text,
        ),
    );
  }
  return hadFormula;
}

/// "12", "-3,5", "0.25" → число для Excel; "007" и прочее — текст.
String? _asNumber(String text) {
  final t = text.trim();
  if (!RegExp(r'^-?(0|[1-9]\d*)([.,]\d+)?$').hasMatch(t)) return null;
  return t.replaceAll(',', '.');
}

void _insertBefore(XmlElement parent, XmlElement child, XmlElement? before) {
  if (before == null) {
    parent.children.add(child);
  } else {
    parent.children.insert(parent.children.indexOf(before), child);
  }
}

/// Список порядка вычисления формул ссылается на ячейки; если формулу
/// заменили значением, его надо убрать, иначе Excel ругается на файл.
void _dropCalcChain(Archive archive) {
  final chain = archive.findFile('xl/calcChain.xml');
  if (chain == null) return;
  archive.removeFile(chain);

  final types = readZipXml(archive, '[Content_Types].xml');
  if (types != null) {
    for (final o in xlsxAll(types, 'Override').toList()) {
      if (o.getAttribute('PartName') == '/xl/calcChain.xml') o.remove();
    }
    _putXml(archive, '[Content_Types].xml', types);
  }
  final rels = readZipXml(archive, 'xl/_rels/workbook.xml.rels');
  if (rels != null) {
    for (final r in xlsxAll(rels, 'Relationship').toList()) {
      if ((r.getAttribute('Target') ?? '').endsWith('calcChain.xml')) {
        r.remove();
      }
    }
    _putXml(archive, 'xl/_rels/workbook.xml.rels', rels);
  }
}

/// Просим Excel пересчитать формулы при открытии — итоги в техкарте
/// обновятся после изменения цифр.
void _requestRecalculation(Archive archive) {
  final workbook = readZipXml(archive, 'xl/workbook.xml');
  final root = workbook?.rootElement;
  if (workbook == null || root == null) return;
  var calcPr = root.getElement('calcPr', namespace: '*');
  if (calcPr == null) {
    calcPr = XmlElement(XmlName('calcPr', root.name.prefix));
    // calcPr по схеме идёт после sheets/definedNames и т.п.
    const before = {
      'sheets',
      'functionGroups',
      'externalReferences',
      'definedNames',
    };
    final anchor = root.childElements
        .where((e) => before.contains(e.name.local))
        .lastOrNull;
    if (anchor == null) {
      root.children.add(calcPr);
    } else {
      root.children.insert(root.children.indexOf(anchor) + 1, calcPr);
    }
  }
  calcPr.setAttribute('fullCalcOnLoad', '1');
  _putXml(archive, 'xl/workbook.xml', workbook);
}

// ---------- Общее ----------

void _putXml(Archive archive, String name, XmlDocument doc) {
  archive.addFile(ArchiveFile.string(name, doc.toXmlString()));
}

Future<void> _rewriteZip(String path, void Function(Archive) modify) async {
  final bytes = await readFileBytes(path);
  final archive = ZipDecoder().decodeBytes(bytes);
  modify(archive);
  final Uint8List encoded = ZipEncoder().encodeBytes(archive);

  final orig = originalCopyPath(path);
  if (!fileExists(orig)) await writeFileBytes(orig, bytes);
  await writeFileBytes(path, encoded);
}
