import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/platform.dart';
import 'file_drop_area.dart';

/// Окно добавления файлов: перетаскивание, выбор через проводник
/// или вставка из буфера обмена (Ctrl+V).
class AddFilesDialog extends StatefulWidget {
  const AddFilesDialog({
    super.key,
    required this.onPick,
    required this.onPaste,
    required this.onDrop,
  });

  final VoidCallback onPick;
  final VoidCallback onPaste;
  final ValueChanged<List<String>> onDrop;

  @override
  State<AddFilesDialog> createState() => _AddFilesDialogState();
}

class _AddFilesDialogState extends State<AddFilesDialog> {
  bool _dragging = false;

  void _close() => Navigator.of(context).pop();

  /// В ряд кнопки делят ширину поровну, в столбик — на всю ширину.
  Widget _flexible(bool narrow, Widget child) =>
      narrow ? child : Expanded(child: child);

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4A1525);
    final screen = MediaQuery.sizeOf(context);
    final narrow = screen.width < 520;
    final dropHeight = (screen.height * 0.28).clamp(110.0, 200.0);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          _close();
          widget.onPaste();
        },
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
          _close();
          widget.onPick();
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: EdgeInsets.all(narrow ? 12 : 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(narrow ? 16 : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Добавление документа или техкарты',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D3142),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _close,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FileDropArea(
                    onHover: (v) => setState(() => _dragging = v),
                    onDrop: (paths) {
                      _close();
                      widget.onDrop(paths);
                    },
                    child: InkWell(
                      onTap: () {
                        _close();
                        widget.onPick();
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        // Минимальная высота; если текст не влезает — растёт.
                        constraints: BoxConstraints(minHeight: dropHeight),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _dragging
                              ? primary.withValues(alpha: 0.10)
                              : const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _dragging ? primary : Colors.black26,
                            width: _dragging ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _dragging
                                  ? Icons.file_download_outlined
                                  : Icons.cloud_upload_outlined,
                              size: narrow ? 40 : 52,
                              color: primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _dragging
                                  ? 'Отпустите, чтобы добавить'
                                  : isDesktop
                                  ? 'Перетащите файлы сюда'
                                  : 'Нажмите, чтобы выбрать файлы',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'PDF, Excel, Word, картинки, текст — любые файлы',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flex(
                    direction: narrow ? Axis.vertical : Axis.horizontal,
                    // Растягиваем только столбик: ряд внутри прокрутки
                    // по высоте растягивать нельзя.
                    crossAxisAlignment: narrow
                        ? CrossAxisAlignment.stretch
                        : CrossAxisAlignment.center,
                    children: [
                      _flexible(
                        narrow,
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            _close();
                            widget.onPick();
                          },
                          icon: const Icon(Icons.folder_open),
                          label: Text(
                            isDesktop
                                ? 'Выбрать файлы  (Ctrl+O)'
                                : 'Выбрать файлы',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12, height: 10),
                      _flexible(
                        narrow,
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            _close();
                            widget.onPaste();
                          },
                          icon: const Icon(Icons.content_paste),
                          label: Text(
                            isDesktop ? 'Вставить  (Ctrl+V)' : 'Вставить',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
