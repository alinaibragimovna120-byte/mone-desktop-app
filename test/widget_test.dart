import 'package:flutter_test/flutter_test.dart';

import 'package:mone_desktop_app/models/document_item.dart';

void main() {
  DocumentItem doc(String name) => DocumentItem(
    id: '1',
    name: name,
    path: 'C:/tmp/$name',
    sizeBytes: 2048,
    addedAt: DateTime(2026),
  );

  test('тип документа определяется по расширению', () {
    expect(doc('техкарта.PDF').kind, DocumentKind.pdf);
    expect(doc('меню.xlsx').kind, DocumentKind.spreadsheet);
    expect(doc('фото.jpg').kind, DocumentKind.image);
    expect(doc('договор.docx').kind, DocumentKind.word);
    expect(doc('архив.zip').kind, DocumentKind.other);
    expect(doc('без_расширения').extension, '');
  });

  test('сохранение и загрузка из JSON', () {
    final original = doc('техкарта.pdf')..coverPath = 'C:/cover.png';
    final restored = DocumentItem.fromJson(original.toJson());
    expect(restored.name, original.name);
    expect(restored.coverPath, original.coverPath);
    expect(restored.sizeLabel, '2.0 КБ');
  });
}
