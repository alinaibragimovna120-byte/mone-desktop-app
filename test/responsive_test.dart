import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mone_desktop_app/models/document_item.dart';
import 'package:mone_desktop_app/screens/document_viewer_screen.dart';
import 'package:mone_desktop_app/screens/home_screen.dart';
import 'package:mone_desktop_app/services/document_storage.dart';
import 'package:mone_desktop_app/widgets/add_files_dialog.dart';

/// Хранилище без диска приложения — отдаёт заранее заданный список.
class _FakeStorage extends DocumentStorage {
  _FakeStorage(this.docs);

  final List<DocumentItem> docs;

  @override
  Future<List<DocumentItem>> load() async => docs;

  @override
  Future<void> save(List<DocumentItem> docs) async {}
}

/// Размеры окна: от минимального до большого монитора.
const _sizes = [
  Size(360, 740), // телефон
  Size(412, 915), // большой телефон
  Size(800, 360), // телефон, повёрнутый боком
  Size(820, 1180), // планшет
  Size(400, 480),
  Size(600, 800),
  Size(1024, 640),
  Size(1366, 768),
  Size(1920, 1080),
  Size(2560, 1440),
];

const _w =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

late Directory _dir;
late DocumentItem _docx;
late DocumentItem _xlsx;
late DocumentItem _other;

DocumentItem _item(String name, List<int> bytes) {
  final file = File('${_dir.path}/$name')..writeAsBytesSync(bytes);
  return DocumentItem(
    id: name,
    name: name,
    path: file.path,
    sizeBytes: bytes.length,
    addedAt: DateTime(2026),
  );
}

void main() {
  setUpAll(() {
    _dir = Directory.systemTemp.createTempSync('mone_responsive');
    final longText = 'Очень длинный текст техкарты без переносов ' * 6;
    _docx = _item(
      'Очень длинное название технологической карты для проверки.docx',
      ZipEncoder().encodeBytes(
        Archive()..addFile(
          ArchiveFile.string(
            'word/document.xml',
            '<w:document $_w><w:body>'
                '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
                '<w:r><w:t>Техкарта: Капучино</w:t></w:r></w:p>'
                '<w:p><w:r><w:t>$longText</w:t></w:r></w:p>'
                '<w:tbl>'
                '${'<w:tr>${'<w:tc><w:p><w:r><w:t>Ячейка с текстом</w:t></w:r></w:p></w:tc>' * 5}</w:tr>' * 4}'
                '</w:tbl>'
                '</w:body></w:document>',
          ),
        ),
      ),
    );
    final cells = StringBuffer();
    for (var r = 1; r <= 30; r++) {
      cells.write('<row r="$r">');
      for (var c = 0; c < 8; c++) {
        final ref = '${String.fromCharCode(65 + c)}$r';
        cells.write('<c r="$ref" t="inlineStr"><is><t>$longText</t></is></c>');
      }
      cells.write('</row>');
    }
    _xlsx = _item(
      'Шахло Ургатиш кулланмаси.xlsx',
      ZipEncoder().encodeBytes(
        Archive()
          ..addFile(
            ArchiveFile.string(
              'xl/workbook.xml',
              '<workbook xmlns:r="r"><sheets>'
                  '<sheet name="Лист1" r:id="rId1"/><sheet name="Лист2" r:id="rId1"/>'
                  '</sheets></workbook>',
            ),
          )
          ..addFile(
            ArchiveFile.string(
              'xl/_rels/workbook.xml.rels',
              '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
            ),
          )
          ..addFile(
            ArchiveFile.string(
              'xl/worksheets/sheet1.xml',
              '<worksheet><sheetData>$cells</sheetData></worksheet>',
            ),
          ),
      ),
    );
    _other = _item('архив.zip', [1, 2, 3]);
  });

  tearDownAll(() {
    // Картинки/файлы могут быть ещё открыты движком — не страшно.
    try {
      _dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Даёт файлам прочитаться (настоящий ввод-вывод) и перерисовывает.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  for (final size in _sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('главная со списком файлов: $label', (tester) async {
      await setSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(storage: _FakeStorage([_docx, _xlsx, _other])),
        ),
      );
      await settle(tester);
      expect(find.text('Все файлы и техкарты кафе'), findsOneWidget);
    });

    testWidgets('главная без файлов: $label', (tester) async {
      await setSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(storage: _FakeStorage([]))),
      );
      await settle(tester);
      expect(find.text('Пока нет файлов'), findsOneWidget);
    });

    testWidgets('окно добавления файла: $label', (tester) async {
      await setSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddFilesDialog(onPick: () {}, onPaste: () {}, onDrop: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Перетащите файлы сюда'), findsOneWidget);
    });

    for (final kind in ['docx', 'xlsx', 'other']) {
      testWidgets('просмотр и редактирование $kind: $label', (tester) async {
        final item = switch (kind) {
          'docx' => _docx,
          'xlsx' => _xlsx,
          _ => _other,
        };
        await setSize(tester, size);
        await tester.pumpWidget(
          MaterialApp(home: DocumentViewerScreen(doc: item)),
        );
        await settle(tester);
        if (item != _other) {
          // На узком окне — значок с подсказкой, на широком — кнопка с текстом.
          final icon = find.byTooltip('Редактировать');
          await tester.tap(
            icon.evaluate().isNotEmpty ? icon : find.text('Редактировать'),
          );
          await settle(tester);
          expect(
            find.text('Сохранить').evaluate().length +
                find.byTooltip('Сохранить').evaluate().length,
            1,
          );
        }
      });
    }
  }
}
