import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/document_item.dart';
import '../services/document_parsers.dart';
import '../services/file_readers.dart';
import '../services/file_store.dart';
import 'document_content_view.dart';

/// Картинка-превью документа для карточки на главной странице:
/// своя обложка, первая страница PDF, само изображение,
/// начало таблицы (техкарты) или текста.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({super.key, required this.doc});

  final DocumentItem doc;

  @override
  Widget build(BuildContext context) {
    final cover = doc.coverPath;
    if (cover != null) {
      return _imageFile(cover);
    }
    switch (doc.kind) {
      case DocumentKind.image:
        return _imageFile(doc.path);
      case DocumentKind.pdf:
        return _PdfFirstPage(path: doc.path, fallback: _iconPreview());
      case DocumentKind.spreadsheet:
        return _SpreadsheetPreview(path: doc.path, fallback: _iconPreview());
      case DocumentKind.text:
        return _TextPreview(path: doc.path, fallback: _iconPreview());
      case DocumentKind.word:
      case DocumentKind.presentation:
        return _DocPreview(path: doc.path, fallback: _iconPreview());
      case DocumentKind.other:
        return _iconPreview();
    }
  }

  Widget _imageFile(String path) => Image(
    image: ResizeImage.resizeIfNeeded(600, null, storedImage(path)),
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (_, _, _) => _iconPreview(),
  );

  Widget _iconPreview() => Container(
    color: doc.color.withValues(alpha: 0.07),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(doc.icon, size: 56, color: doc.color),
        const SizedBox(height: 8),
        Text(
          doc.extension.toUpperCase(),
          style: TextStyle(
            color: doc.color,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}

class _PdfFirstPage extends StatelessWidget {
  const _PdfFirstPage({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: PdfDocumentViewBuilder(
        documentRef: storedPdf(path),
        builder: (context, document) {
          if (document == null) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return PdfPageView(
            document: document,
            pageNumber: 1,
            maximumDpi: 96,
            alignment: Alignment.topCenter,
          );
        },
      ),
    );
  }
}

class _SpreadsheetPreview extends StatelessWidget {
  const _SpreadsheetPreview({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SheetData>>(
      future: readSpreadsheet(path),
      builder: (context, snapshot) {
        if (snapshot.hasError) return fallback;
        final sheets = snapshot.data;
        if (sheets == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final rows = sheets.isEmpty ? <List<String>>[] : sheets.first.rows;
        if (rows.isEmpty) return fallback;
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length && i < 12; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: i == 0 ? Colors.green.shade50 : null,
                        border: const Border(
                          bottom: BorderSide(color: Colors.black12),
                        ),
                      ),
                      child: Row(
                        children: [
                          for (var j = 0; j < rows[i].length && j < 4; j++)
                            Expanded(
                              flex: j == 0 ? 1 : 4,
                              child: Text(
                                rows[i][j],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: i == 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: readText(path, maxChars: 800),
      builder: (context, snapshot) {
        if (snapshot.hasError) return fallback;
        final text = snapshot.data;
        if (text == null) return const SizedBox.shrink();
        if (text.trim().isEmpty) return fallback;
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          alignment: Alignment.topLeft,
          child: Text(
            text,
            overflow: TextOverflow.fade,
            style: const TextStyle(fontSize: 9, color: Colors.black87),
          ),
        );
      },
    );
  }
}

class _DocPreview extends StatelessWidget {
  const _DocPreview({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocContent>(
      future: readDocument(path),
      builder: (context, snapshot) {
        if (snapshot.hasError) return fallback;
        final content = snapshot.data;
        if (content == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final blocks = content.pages.first.blocks;
        if (blocks.isEmpty) return fallback;
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in blocks.take(12))
                    docBlockWidget(b, scale: 0.55),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
