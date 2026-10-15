import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'document_parsers.dart';
import 'file_store.dart';

/// Лист таблицы: название и строки ячеек в виде текста.
class SheetData {
  SheetData(this.name, this.rows, {this.xmlPath, List<int>? rowNumbers})
    : rowNumbers = rowNumbers ?? [for (var i = 0; i < rows.length; i++) i + 1];

  final String name;
  final List<List<String>> rows;

  /// Путь к XML листа внутри .xlsx (null — лист нельзя редактировать).
  final String? xmlPath;

  /// Настоящие номера строк в Excel (пустые строки пропущены при показе).
  final List<int> rowNumbers;

  /// Адрес ячейки в стиле Excel: (0, 1) → "B<номер строки>".
  String cellRef(int row, int col) => '${columnName(col)}${rowNumbers[row]}';
}

/// 0 → A, 25 → Z, 26 → AA.
String columnName(int index) {
  var n = index + 1;
  final out = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    out.write(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  return out.toString().split('').reversed.join();
}

/// "B12" → 1
int? columnIndex(String? ref) {
  if (ref == null) return null;
  var result = 0;
  var found = false;
  for (final unit in ref.toUpperCase().codeUnits) {
    if (unit < 65 || unit > 90) break;
    result = result * 26 + (unit - 64);
    found = true;
  }
  return found ? result - 1 : null;
}

final Map<String, Future<List<SheetData>>> _sheetCache = {};

/// Сбрасывает кэш после сохранения файла.
void forgetSpreadsheet(String path) => _sheetCache.remove(path);

/// Читает .xlsx или .csv файл (результат кэшируется по пути).
Future<List<SheetData>> readSpreadsheet(String path) {
  return _sheetCache.putIfAbsent(path, () async {
    if (path.toLowerCase().endsWith('.csv')) return readCsv(path);
    return parseXlsx(await readFileBytes(path));
  });
}

/// Ищет элементы по имени без учёта префикса пространства имён.
Iterable<XmlElement> xlsxAll(XmlNode node, String name) =>
    node.findAllElements(name, namespace: '*');

XmlDocument? readZipXml(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) return null;
  return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
}

/// Пути к XML листов: название листа → "xl/worksheets/sheet1.xml".
List<(String, String)> xlsxSheetPaths(Archive archive) {
  final relTargets = <String, String>{
    for (final rel in xlsxAll(
      readZipXml(archive, 'xl/_rels/workbook.xml.rels') ?? XmlDocument(),
      'Relationship',
    ))
      rel.getAttribute('Id') ?? '': rel.getAttribute('Target') ?? '',
  };
  final result = <(String, String)>[];
  final workbook = readZipXml(archive, 'xl/workbook.xml');
  for (final sheet in xlsxAll(workbook ?? XmlDocument(), 'sheet')) {
    final relId = sheet.attributes
        .firstWhere(
          (a) => a.name.local == 'id',
          orElse: () => XmlAttribute(XmlName('id'), ''),
        )
        .value;
    var target = relTargets[relId];
    if (target == null) continue;
    target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    result.add((sheet.getAttribute('name') ?? 'Лист', target));
  }
  return result;
}

/// Разбирает .xlsx: это zip-архив с XML-файлами листов внутри.
List<SheetData> parseXlsx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final shared = <String>[
    for (final si in xlsxAll(
      readZipXml(archive, 'xl/sharedStrings.xml') ?? XmlDocument(),
      'si',
    ))
      xlsxAll(si, 't').map((t) => t.innerText).join(),
  ];

  final sheets = <SheetData>[];
  for (final (name, path) in xlsxSheetPaths(archive)) {
    final doc = readZipXml(archive, path);
    if (doc == null) continue;
    sheets.add(_readSheet(name, path, doc, shared));
  }
  return sheets;
}

SheetData _readSheet(
  String name,
  String path,
  XmlDocument doc,
  List<String> shared,
) {
  final rows = <List<String>>[];
  final numbers = <int>[];
  var lastNumber = 0;
  for (final row in xlsxAll(doc, 'row')) {
    final number = int.tryParse(row.getAttribute('r') ?? '') ?? lastNumber + 1;
    lastNumber = number;
    final cells = <String>[];
    for (final c in row.findElements('c', namespace: '*')) {
      final index = columnIndex(c.getAttribute('r')) ?? cells.length;
      while (cells.length < index) {
        cells.add('');
      }
      final value = _cellValue(c, shared);
      if (index < cells.length) {
        cells[index] = value;
      } else {
        cells.add(value);
      }
    }
    while (cells.isNotEmpty && cells.last.isEmpty) {
      cells.removeLast();
    }
    if (cells.isNotEmpty) {
      rows.add(cells);
      numbers.add(number);
    }
  }
  return SheetData(name, rows, xmlPath: path, rowNumbers: numbers);
}

String _cellValue(XmlElement c, List<String> shared) {
  final type = c.getAttribute('t');
  if (type == 'inlineStr') {
    return xlsxAll(c, 't').map((t) => t.innerText).join();
  }
  final v = c.getElement('v', namespace: '*')?.innerText ?? '';
  switch (type) {
    case 's':
      final i = int.tryParse(v);
      return i != null && i < shared.length ? shared[i] : '';
    case 'b':
      return v == '1' ? 'ДА' : 'НЕТ';
    default:
      final n = num.tryParse(v);
      if (n != null && n == n.roundToDouble() && !v.contains('E')) {
        return n.toInt().toString();
      }
      return v;
  }
}

/// Читает текстовый файл, не падая на неправильной кодировке.
Future<String> readText(String path, {int? maxChars}) async {
  final bytes = await readFileBytes(path);
  final text = _decodeUtf8(bytes);
  if (maxChars != null && text.length > maxChars) {
    return text.substring(0, maxChars);
  }
  return text;
}

String _decodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}
