import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mone_desktop_app/services/file_readers.dart';

void main() {
  test('техкарта .xlsx читается в строки', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('xl/workbook.xml', '''
<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Техкарта" sheetId="1" r:id="rId1"/></sheets>
</workbook>'''),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          '''
<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>''',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/sharedStrings.xml',
          '''
<sst><si><t>№</t></si><si><t>Тема</t></si><si><r><t>Кофе </t></r><r><t>таёрлаш</t></r></si></sst>''',
        ),
      )
      ..addFile(
        ArchiveFile.string('xl/worksheets/sheet1.xml', '''
<worksheet><sheetData>
  <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
  <row r="2"><c r="A2"><v>1</v></c><c r="C2" t="s"><v>2</v></c></row>
</sheetData></worksheet>'''),
      );

    final sheets = parseXlsx(ZipEncoder().encodeBytes(archive));
    expect(sheets.single.name, 'Техкарта');
    expect(sheets.single.rows, [
      ['№', 'Тема'],
      ['1', '', 'Кофе таёрлаш'],
    ]);
  });
}
