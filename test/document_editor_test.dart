import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mone_desktop_app/services/document_editor.dart';
import 'package:mone_desktop_app/services/document_parsers.dart';
import 'package:mone_desktop_app/services/file_readers.dart';

const _w =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

Archive _docx(String body) => Archive()
  ..addFile(
    ArchiveFile.string(
      'word/document.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document $_w><w:body>$body</w:body></w:document>',
    ),
  );

List<DocBlock> _blocks(Archive a) =>
    parseDocx(ZipEncoder().encodeBytes(a)).pages.single.blocks;

String _documentXml(Archive a) =>
    String.fromCharCodes(a.findFile('word/document.xml')!.content);

void main() {
  group('Word', () {
    test('правка середины сохраняет жирный шрифт у остального текста', () {
      final a = _docx(
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Эспрессо</w:t></w:r>'
        '<w:r><w:t xml:space="preserve"> 30 мл</w:t></w:r></w:p>',
      );
      applyDocxEdits(a, {0: 'Эспрессо 40 мл'});
      final p = _blocks(a).single as DocParagraph;
      expect(p.text, 'Эспрессо 40 мл');
      expect(p.runs.first.text, 'Эспрессо');
      expect(p.runs.first.bold, isTrue);
      expect(p.runs.last.bold, isFalse);
    });

    test('замена всего текста, начало и пустой абзац', () {
      final a = _docx(
        '<w:p><w:r><w:t>Старый</w:t></w:r><w:r><w:t> текст</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>мир</w:t></w:r></w:p>'
        '<w:p/>',
      );
      applyDocxEdits(a, {0: 'Новое', 1: 'Привет, мир', 2: 'Добавлено'});
      final texts = _blocks(
        a,
      ).whereType<DocParagraph>().map((p) => p.text).toList();
      expect(texts, ['Новое', 'Привет, мир', 'Добавлено']);
    });

    test('ячейка таблицы и перенос строки', () {
      final a = _docx(
        '<w:tbl><w:tr>'
        '<w:tc><w:p><w:r><w:t>Молоко</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>150</w:t></w:r></w:p></w:tc>'
        '</w:tr></w:tbl>',
      );
      final table = _blocks(a).single as DocTable;
      final id = table.rows[0][1].paragraphs.single.id!;
      applyDocxEdits(a, {id: '200\nгр'});
      expect(_documentXml(a), contains('<w:br/>'));
      final cell = (_blocks(a).single as DocTable).rows[0][1];
      expect(cell.text, '200\nгр');
    });

    test('сохранение в файл, копия оригинала и возврат', () async {
      final dir = await Directory.systemTemp.createTemp('mone_test');
      final path = '${dir.path}/техкарта.docx';
      await File(path).writeAsBytes(
        ZipEncoder().encodeBytes(
          _docx('<w:p><w:r><w:t>Капучино</w:t></w:r></w:p>'),
        ),
      );

      await saveDocxEdits(path, {0: 'Латте'});
      expect(
        ((await readDocument(path)).pages.single.blocks.single as DocParagraph)
            .text,
        'Латте',
      );
      expect(hasOriginalCopy(path), isTrue);

      await restoreOriginal(path);
      expect(
        ((await readDocument(path)).pages.single.blocks.single as DocParagraph)
            .text,
        'Капучино',
      );
      expect(hasOriginalCopy(path), isFalse);
      await dir.delete(recursive: true);
    });
  });

  group('Excel', () {
    Archive xlsx() => Archive()
      ..addFile(
        ArchiveFile.string(
          '[Content_Types].xml',
          '<Types><Override PartName="/xl/calcChain.xml" ContentType="x"/></Types>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/workbook.xml',
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
              'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets><sheet name="Техкарта" sheetId="1" r:id="rId1"/></sheets>'
              '</workbook>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          '<Relationships>'
              '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/>'
              '<Relationship Id="rId9" Target="calcChain.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/sharedStrings.xml',
          '<sst><si><t>Тема</t></si><si><t>Кофе</t></si></sst>',
        ),
      )
      ..addFile(ArchiveFile.string('xl/calcChain.xml', '<calcChain/>'))
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<sheetData>'
              '<row r="1"><c r="A1" t="s" s="3"><v>0</v></c></row>'
              '<row r="3"><c r="A3" t="s"><v>1</v></c><c r="B3"><v>30</v></c>'
              '<c r="C3"><f>B3*2</f><v>60</v></c></row>'
              '</sheetData></worksheet>',
        ),
      );

    List<List<String>> rows(Archive a) =>
        parseXlsx(ZipEncoder().encodeBytes(a)).single.rows;

    test('текст, число, новая ячейка и новая строка', () {
      final a = xlsx();
      final sheet = parseXlsx(ZipEncoder().encodeBytes(a)).single;
      expect(sheet.cellRef(1, 1), 'B3');

      applyXlsxEdits(a, {
        'xl/worksheets/sheet1.xml': {
          'A1': 'Тема обучения',
          'B3': '40',
          'D3': 'гр',
          'B2': 'новая строка',
        },
      });
      expect(rows(a), [
        ['Тема обучения'],
        ['', 'новая строка'],
        ['Кофе', '40', '60', 'гр'],
      ]);
      final xml = String.fromCharCodes(
        a.findFile('xl/worksheets/sheet1.xml')!.content,
      );
      // Стиль ячейки сохранён, число записано числом.
      expect(xml, contains('s="3"'));
      expect(xml, contains('<c r="B3"><v>40</v></c>'));
    });

    test('замена формулы убирает calcChain', () {
      final a = xlsx();
      applyXlsxEdits(a, {
        'xl/worksheets/sheet1.xml': {'C3': '70'},
      });
      expect(rows(a).last, ['Кофе', '30', '70']);
      expect(a.findFile('xl/calcChain.xml'), isNull);
      final types = String.fromCharCodes(
        a.findFile('[Content_Types].xml')!.content,
      );
      expect(types, isNot(contains('calcChain')));
      final workbook = String.fromCharCodes(
        a.findFile('xl/workbook.xml')!.content,
      );
      expect(workbook, contains('fullCalcOnLoad="1"'));
    });
  });
}
