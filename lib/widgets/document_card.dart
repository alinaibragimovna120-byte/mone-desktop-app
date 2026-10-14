import 'package:flutter/material.dart';

import '../models/document_item.dart';
import 'document_thumbnail.dart';

enum DocumentCardAction {
  open,
  rename,
  setCover,
  removeCover,
  openExternal,
  delete,
}

/// Карточка документа на главной странице: превью + название.
class DocumentCard extends StatelessWidget {
  const DocumentCard({super.key, required this.doc, required this.onAction});

  final DocumentItem doc;
  final ValueChanged<DocumentCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.black12),
      ),
      child: InkWell(
        onTap: () => onAction(DocumentCardAction.open),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    // Превью только для показа, клик идёт на всю карточку.
                    child: DocumentThumbnail(
                      key: ValueKey('${doc.id}_${doc.coverPath}'),
                      doc: doc,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: doc.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        doc.extension.isEmpty
                            ? 'ФАЙЛ'
                            : doc.extension.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Positioned(right: 4, top: 4, child: _menu()),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF2D3142),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    doc.sizeLabel,
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: PopupMenuButton<DocumentCardAction>(
        tooltip: 'Действия',
        icon: const Icon(Icons.more_vert, size: 18),
        padding: EdgeInsets.zero,
        onSelected: onAction,
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: DocumentCardAction.open,
            child: ListTile(
              leading: Icon(Icons.open_in_full),
              title: Text('Открыть'),
            ),
          ),
          const PopupMenuItem(
            value: DocumentCardAction.rename,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Переименовать'),
            ),
          ),
          const PopupMenuItem(
            value: DocumentCardAction.setCover,
            child: ListTile(
              leading: Icon(Icons.add_photo_alternate_outlined),
              title: Text('Своя картинка карточки'),
            ),
          ),
          if (doc.coverPath != null)
            const PopupMenuItem(
              value: DocumentCardAction.removeCover,
              child: ListTile(
                leading: Icon(Icons.hide_image_outlined),
                title: Text('Убрать картинку'),
              ),
            ),
          const PopupMenuItem(
            value: DocumentCardAction.openExternal,
            child: ListTile(
              leading: Icon(Icons.launch),
              title: Text('Открыть в другой программе'),
            ),
          ),
          const PopupMenuItem(
            value: DocumentCardAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text('Удалить', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
  }
}
