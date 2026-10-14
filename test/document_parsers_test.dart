import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mone_desktop_app/services/document_parsers.dart';

const _w =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

void main() {
  test('Word .docx: заголовок, текст и таблица', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('word/document.xml', '''
<w:document $_w><w:body>
  <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Техкарта: Капучино</w:t></w:r></w:p>
  <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Эспрессо</w:t></w:r><w:r><w:t xml:space="preserve"> 30 мл</w:t></w:r></w:p>
  <w:tbl>
    <w:tr><w:tc><w:p><w:r><w:t>Ингредиент</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Граммы</w:t></w:r></w:p></w:tc></w:tr>
    <w:tr><w:tc><w:p><w:r><w:t>Молоко</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>150</w:t></w:r></w:p></w:tc></w:tr>
  </w:tbl>
</w:body></w:document>'''),
      );
    final blocks = parseDocx(
      ZipEncoder().encodeBytes(archive),
    ).pages.single.blocks;

    final title = blocks[0] as DocParagraph;
    expect(title.text, 'Техкарта: Капучино');
    expect(title.headingLevel, 1);
    final body = blocks[1] as DocParagraph;
    expect(body.text, 'Эспрессо 30 мл');
    expect(body.runs.first.bold, isTrue);
    expect(
      (blocks[2] as DocTable).rows.map((r) => r.map((c) => c.text).toList()),
      [
        ['Ингредиент', 'Граммы'],
        ['Молоко', '150'],
      ],
    );
  });

  test('PowerPoint .pptx: по странице на слайд в правильном порядке', () {
    String slide(String text) =>
        '''
<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>
  <p:sp><p:txBody><a:p><a:r><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp>
</p:spTree></p:cSld></p:sld>''';
    final archive = Archive()
      ..addFile(ArchiveFile.string('ppt/slides/slide10.xml', slide('Десятый')))
      ..addFile(ArchiveFile.string('ppt/slides/slide2.xml', slide('Второй')));
    final pages = parsePptx(ZipEncoder().encodeBytes(archive)).pages;
    expect(pages.map((p) => p.title), ['Слайд 2', 'Слайд 10']);
    expect((pages.first.blocks.single as DocParagraph).text, 'Второй');
  });

  test('RTF с кириллицей', () {
    const rtf =
        r"{\rtf1\ansi\ansicpg1251{\fonttbl{\f0 Arial;}}"
        r"\f0 \'cc\'ee\'eb\'ee\'ea\'ee\par "
        r'\'
        'u1050?'
        r"\'ee\'f4\'e5}";
    expect(parseRtf(latin1.encode(rtf)), 'Молоко\nКофе');
  });

  test('CSV с разделителем ; и кавычками', () async {
    final file = File('${Directory.systemTemp.path}/mone_test.csv');
    await file.writeAsString('№;Тема\n1;"Кофе; молоко"\n');
    final rows = (await readCsv(file.path)).single.rows;
    expect(rows, [
      ['№', 'Тема'],
      ['1', 'Кофе; молоко'],
    ]);
    await file.delete();
  });
}
