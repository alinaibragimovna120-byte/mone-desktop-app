import 'package:flutter/material.dart';

enum DocumentKind { pdf, image, spreadsheet, text, word, presentation, other }

class DocumentItem {
  DocumentItem({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.addedAt,
    this.coverPath,
  });

  final String id;
  String name;

  /// Путь к копии файла во внутреннем хранилище приложения.
  final String path;
  int sizeBytes;
  final DateTime addedAt;

  /// Своя картинка-обложка для карточки (если пользователь её задал).
  String? coverPath;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  DocumentKind get kind {
    switch (extension) {
      case 'pdf':
        return DocumentKind.pdf;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'bmp':
      case 'webp':
        return DocumentKind.image;
      case 'xlsx':
      case 'csv':
        return DocumentKind.spreadsheet;
      case 'txt':
      case 'md':
      case 'json':
      case 'log':
        return DocumentKind.text;
      case 'docx':
      case 'rtf':
        return DocumentKind.word;
      case 'pptx':
        return DocumentKind.presentation;
      default:
        return DocumentKind.other;
    }
  }

  Color get color {
    switch (kind) {
      case DocumentKind.pdf:
        return const Color(0xFFB3261E);
      case DocumentKind.image:
        return Colors.purple.shade600;
      case DocumentKind.spreadsheet:
        return Colors.green.shade700;
      case DocumentKind.text:
        return Colors.blueGrey.shade600;
      case DocumentKind.word:
        return Colors.blue.shade700;
      case DocumentKind.presentation:
        return Colors.deepOrange.shade700;
      case DocumentKind.other:
        return Colors.grey.shade700;
    }
  }

  IconData get icon {
    switch (kind) {
      case DocumentKind.pdf:
        return Icons.picture_as_pdf;
      case DocumentKind.image:
        return Icons.image_outlined;
      case DocumentKind.spreadsheet:
        return Icons.table_chart_outlined;
      case DocumentKind.text:
        return Icons.notes;
      case DocumentKind.word:
        return Icons.description_outlined;
      case DocumentKind.presentation:
        return Icons.slideshow_outlined;
      case DocumentKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  /// Старые двоичные форматы Office, которые нельзя прочитать без Office.
  bool get isLegacyOffice => const {'doc', 'xls', 'ppt'}.contains(extension);

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes Б';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'sizeBytes': sizeBytes,
    'addedAt': addedAt.toIso8601String(),
    'coverPath': coverPath,
  };

  factory DocumentItem.fromJson(Map<String, dynamic> json) => DocumentItem(
    id: json['id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    sizeBytes: json['sizeBytes'] as int,
    addedAt: DateTime.parse(json['addedAt'] as String),
    coverPath: json['coverPath'] as String?,
  );
}
