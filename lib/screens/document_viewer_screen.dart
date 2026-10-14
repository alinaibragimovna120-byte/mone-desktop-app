import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/document_item.dart';
import '../services/document_editor.dart';
import '../services/document_parsers.dart';
import '../services/file_readers.dart';
import '../services/platform.dart';
import '../widgets/document_content_view.dart';

const _primary = Color(0xFF4A1525);

enum ViewerResult { delete }

/// Полноэкранный просмотр документа / техкарты.
/// Текст в Word (.docx) и ячейки в Excel (.xlsx) можно исправлять.
class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({super.key, required this.doc});

  final DocumentItem doc;

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  Future<DocContent>? _docFuture;
  Future<List<SheetData>>? _sheetFuture;

  bool _editing = false;
  bool _saving = false;
  final Map<int, String> _docEdits = {};
  final Map<String, Map<String, String>> _cellEdits = {};

  DocumentItem get doc => widget.doc;

  bool get _canEdit => doc.extension == 'docx' || doc.extension == 'xlsx';

  bool get _dirty =>
      _docEdits.isNotEmpty || _cellEdits.values.any((e) => e.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (doc.kind == DocumentKind.word ||
        doc.kind == DocumentKind.presentation) {
      _docFuture = readDocument(doc.path);
    } else if (doc.kind == DocumentKind.spreadsheet) {
      _sheetFuture = readSpreadsheet(doc.path);
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Colors.red.shade700 : _primary,
        ),
      );
  }

  Future<void> _openExternal() async {
    final ok = await openInSystemApp(doc.path);
    if (!ok) _toast('Не найдена программа для открытия файла', error: true);
  }

  // ---------- Редактирование ----------

  void _startEditing() => setState(() => _editing = true);

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить исправления?'),
        content: const Text('Несохранённые изменения пропадут.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Продолжить редактирование'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Не сохранять'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancelEditing() async {
    if (!await _confirmDiscard()) return;
    setState(() {
      _editing = false;
      _docEdits.clear();
      _cellEdits.clear();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_dirty) {
      setState(() => _editing = false);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      if (doc.extension == 'docx') {
        await saveDocxEdits(doc.path, Map.of(_docEdits));
      } else {
        await saveXlsxEdits(doc.path, {
          for (final e in _cellEdits.entries) e.key: Map.of(e.value),
        });
      }
      doc.sizeBytes = await File(doc.path).length();
      setState(() {
        _editing = false;
        _docEdits.clear();
        _cellEdits.clear();
        _load();
      });
      _toast('Изменения сохранены в файл');
    } catch (e) {
      _toast('Не удалось сохранить: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreOriginal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вернуть исходный файл?'),
        content: const Text(
          'Все исправления, сделанные в программе, будут отменены, '
          'и файл станет таким, каким его добавили.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Вернуть'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await restoreOriginal(doc.path);
    doc.sizeBytes = await File(doc.path).length();
    setState(_load);
    _toast('Исходный файл восстановлен');
  }

  // ---------- Интерфейс ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_editing || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() {
            _docEdits.clear();
            _cellEdits.clear();
          });
          Navigator.of(context).pop();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_editing) {
              _cancelEditing();
            } else {
              Navigator.of(context).maybePop();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (_editing) _save();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFFEDEEF1),
            appBar: AppBar(
              backgroundColor: _editing
                  ? const Color(0xFFFFF8E8)
                  : Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 1,
              title: Row(
                children: [
                  if (!_phone) ...[
                    Icon(doc.icon, color: doc.color),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      _editing ? 'Редактирование: ${doc.name}' : doc.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3142),
                      ),
                    ),
                  ),
                ],
              ),
              actions: _editing ? _editActions() : _viewActions(),
            ),
            body: Column(
              children: [
                if (_editing)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFFF3D6),
                    padding: EdgeInsets.symmetric(
                      horizontal: _narrow(context) ? 12 : 24,
                      vertical: 10,
                    ),
                    child: Text(
                      (doc.extension == 'docx'
                              ? 'Нажмите на любой текст и исправьте его.'
                              : 'Нажмите на любую ячейку и исправьте её.') +
                          (isDesktop
                              ? ' Сохранить — Ctrl+S, отменить — Esc.'
                              : ''),
                      style: const TextStyle(color: Color(0xFF6B4E16)),
                    ),
                  ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _viewActions() {
    // На узком окне всё, кроме «Редактировать», убираем в меню «⋮».
    if (MediaQuery.sizeOf(context).width < 820) {
      return [
        if (_canEdit)
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: _primary),
            tooltip: 'Редактировать',
            onPressed: _startEditing,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Ещё',
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            if (_canEdit && hasOriginalCopy(doc.path))
              PopupMenuItem(
                value: _restoreOriginal,
                child: const ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Вернуть исходный'),
                ),
              ),
            PopupMenuItem(
              value: _openExternal,
              child: const ListTile(
                leading: Icon(Icons.launch),
                title: Text('Открыть в программе'),
              ),
            ),
            PopupMenuItem(
              value: _confirmDelete,
              child: const ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text(
                  'Удалить',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ];
    }
    return _wideViewActions();
  }

  List<Widget> _wideViewActions() => [
    if (_canEdit)
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _primary),
          onPressed: _startEditing,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Редактировать'),
        ),
      ),
    if (_canEdit && hasOriginalCopy(doc.path))
      TextButton.icon(
        onPressed: _restoreOriginal,
        icon: const Icon(Icons.restore, size: 18),
        label: const Text('Вернуть исходный'),
      ),
    TextButton.icon(
      onPressed: _openExternal,
      icon: const Icon(Icons.launch, size: 18),
      label: const Text('Открыть в программе'),
    ),
    IconButton(
      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
      tooltip: 'Удалить документ',
      onPressed: _confirmDelete,
    ),
    const SizedBox(width: 8),
  ];

  /// Экран шириной с телефон — кнопки только значками.
  bool get _phone => MediaQuery.sizeOf(context).width < 520;

  List<Widget> _editActions() {
    if (_phone) {
      return [
        IconButton(
          tooltip: 'Отмена',
          onPressed: _saving ? null : _cancelEditing,
          icon: const Icon(Icons.close),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: Colors.green.shade700),
          tooltip: 'Сохранить',
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined),
        ),
        const SizedBox(width: 8),
      ];
    }
    return _wideEditActions();
  }

  List<Widget> _wideEditActions() => [
    TextButton(
      onPressed: _saving ? null : _cancelEditing,
      child: const Text('Отмена'),
    ),
    const SizedBox(width: 8),
    Padding(
      padding: const EdgeInsets.only(right: 16),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_outlined, size: 18),
        label: const Text('Сохранить'),
      ),
    ),
  ];

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text('«${doc.name}» будет удалён из программы.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, ViewerResult.delete);
    }
  }

  Widget _body() {
    switch (doc.kind) {
      case DocumentKind.pdf:
        return PdfViewer.file(
          doc.path,
          params: PdfViewerParams(
            backgroundColor: const Color(0xFFEDEEF1),
            errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                _unsupported('Не удалось открыть PDF: $error'),
          ),
        );
      case DocumentKind.image:
        return InteractiveViewer(
          maxScale: 8,
          child: Center(child: Image.file(File(doc.path))),
        );
      case DocumentKind.spreadsheet:
        return _SpreadsheetView(
          future: _sheetFuture!,
          editing: _editing,
          edits: _cellEdits,
          onChanged: () => setState(() {}),
          onError: (e) => _unsupported('Не удалось прочитать таблицу: $e'),
        );
      case DocumentKind.text:
        return FutureBuilder<String>(
          future: readText(doc.path),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _unsupported('${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _paper(
              SelectableText(
                snapshot.data!,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            );
          },
        );
      case DocumentKind.word:
      case DocumentKind.presentation:
        return FutureBuilder<DocContent>(
          future: _docFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _unsupported(
                'Не удалось прочитать документ: ${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return DocumentContentView(
              content: snapshot.data!,
              editing: _editing && snapshot.data!.editable,
              edits: _docEdits,
              onChanged: () => setState(() {}),
            );
          },
        );
      case DocumentKind.other:
        if (doc.isLegacyOffice) {
          final modern = '${doc.extension}x'.toUpperCase();
          return _unsupported(
            'Это старый формат ${doc.extension.toUpperCase()} (Office 97–2003), '
            'его содержимое нельзя прочитать без Office.\n'
            'Откройте файл и сохраните как $modern («Сохранить как» → $modern), '
            'затем добавьте снова — он будет показываться прямо здесь.',
          );
        }
        return _unsupported(
          'Этот формат (${doc.extension.toUpperCase()}) нельзя показать '
          'внутри программы.',
        );
    }
  }

  Widget _paper(Widget child) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_narrow(context) ? 8 : 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          width: double.infinity,
          padding: EdgeInsets.all(_narrow(context) ? 16 : 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _unsupported(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(doc.icon, size: 80, color: doc.color),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: _openExternal,
            icon: const Icon(Icons.launch),
            label: const Text('Открыть в другой программе'),
          ),
        ],
      ),
    );
  }
}

/// Узкое окно — меньше отступы вокруг листа.
bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width < 720;

class _SpreadsheetView extends StatelessWidget {
  const _SpreadsheetView({
    required this.future,
    required this.editing,
    required this.edits,
    required this.onChanged,
    required this.onError,
  });

  final Future<List<SheetData>> future;
  final bool editing;
  final Map<String, Map<String, String>> edits;
  final VoidCallback onChanged;
  final Widget Function(Object error) onError;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SheetData>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return onError(snapshot.error!);
        final sheets = snapshot.data;
        if (sheets == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (sheets.isEmpty) return onError('таблица пустая');
        Widget table(SheetData s) => _SheetTable(
          key: ValueKey('${s.xmlPath}_$editing'),
          sheet: s,
          editing: editing && s.xmlPath != null,
          edits: edits.putIfAbsent(s.xmlPath ?? '', () => {}),
          onChanged: onChanged,
        );
        if (sheets.length == 1) return table(sheets.first);
        return DefaultTabController(
          length: sheets.length,
          child: Column(
            children: [
              Material(
                color: Colors.white,
                child: TabBar(
                  isScrollable: true,
                  tabs: [for (final s in sheets) Tab(text: s.name)],
                ),
              ),
              Expanded(
                child: TabBarView(children: [for (final s in sheets) table(s)]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetTable extends StatefulWidget {
  const _SheetTable({
    super.key,
    required this.sheet,
    required this.editing,
    required this.edits,
    required this.onChanged,
  });

  final SheetData sheet;
  final bool editing;

  /// Адрес ячейки ("B3") → новый текст.
  final Map<String, String> edits;
  final VoidCallback onChanged;

  @override
  State<_SheetTable> createState() => _SheetTableState();
}

class _SheetTableState extends State<_SheetTable> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.sheet.rows;
    if (rows.isEmpty) {
      return const Center(child: Text('Лист пустой'));
    }
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    // В режиме редактирования ширина колонок считается по самому
    // длинному тексту, чтобы поля ввода не прыгали.
    final widths = <int, TableColumnWidth>{};
    if (widget.editing) {
      for (var j = 0; j < cols; j++) {
        var longest = 4;
        for (final r in rows) {
          if (j < r.length && r[j].length > longest) longest = r[j].length;
        }
        widths[j] = FixedColumnWidth((longest * 8.0 + 32).clamp(70, 460));
      }
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(_narrow(context) ? 8 : 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 600),
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                columnWidths: widths,
                border: TableBorder.all(color: Colors.black12),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: i == 0
                            ? _primary.withValues(alpha: 0.07)
                            : (i.isOdd ? null : const Color(0xFFFAFAFB)),
                      ),
                      children: [
                        for (var j = 0; j < cols; j++)
                          widget.editing ? _editCell(i, j) : _viewCell(i, j),
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

  String _original(int i, int j) {
    final row = widget.sheet.rows[i];
    return j < row.length ? row[j] : '';
  }

  Widget _viewCell(int i, int j) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SelectableText(
          _original(i, j),
          style: TextStyle(
            fontSize: 14,
            fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _editCell(int i, int j) {
    final original = _original(i, j);
    final ref = widget.sheet.cellRef(i, j);
    final controller = _controllers.putIfAbsent(
      ref,
      () => TextEditingController(text: widget.edits[ref] ?? original),
    );
    final changed = widget.edits.containsKey(ref);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: TextField(
        controller: controller,
        maxLines: null,
        style: TextStyle(
          fontSize: 14,
          fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: changed
              ? const Color(0xFFFFF0C2)
              : const Color(0xFFFFFBF0),
          hoverColor: const Color(0xFFFFF3D6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: _primary, width: 1.5),
          ),
        ),
        onChanged: (value) {
          if (value == original) {
            widget.edits.remove(ref);
          } else {
            widget.edits[ref] = value;
          }
          widget.onChanged();
        },
      ),
    );
  }
}
