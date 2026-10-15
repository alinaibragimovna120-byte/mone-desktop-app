import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../models/document_item.dart';
import '../services/document_storage.dart';
import '../services/file_store.dart';
import '../services/platform.dart';
import '../services/shared_files.dart';
import '../widgets/add_files_dialog.dart';
import '../widgets/document_card.dart';
import '../widgets/file_drop_area.dart';
import 'document_viewer_screen.dart';

const _primary = Color(0xFF4A1525);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.storage});

  final DocumentStorage storage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<DocumentItem> _docs = [];
  bool _loading = true;
  bool _dragging = false;
  bool _dialogOpen = false;
  String _query = '';

  DocumentStorage get _storage => widget.storage;

  @override
  void initState() {
    super.initState();
    _storage.load().then((docs) {
      if (!mounted) return;
      setState(() {
        _docs.addAll(docs);
        _loading = false;
      });
      // Только после загрузки списка, иначе сохранение затрёт его.
      listenSharedFiles(_addPaths);
    });
  }

  Future<void> _persist() => _storage.save(_docs);

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

  // ---------- Добавление файлов ----------

  Future<void> _addPaths(List<String> paths) => _import([
    for (final path in paths) (path, () => _storage.importFile(path)),
  ]);

  /// [jobs]: название файла (для сообщения об ошибке) и его добавление.
  Future<void> _import(
    List<(String, Future<DocumentItem> Function())> jobs,
  ) async {
    if (jobs.isEmpty) return;
    var added = 0;
    final failed = <String>[];
    for (final (name, importDoc) in jobs) {
      try {
        _docs.insert(0, await importDoc());
        added++;
      } catch (_) {
        failed.add(name);
      }
    }
    setState(() {});
    await _persist();
    if (failed.isNotEmpty) {
      _toast('Не удалось добавить: ${failed.join(', ')}', error: true);
    } else {
      _toast(added == 1 ? 'Файл добавлен' : 'Добавлено файлов: $added');
    }
  }

  Future<void> _pickFiles() async {
    try {
      // В браузере путей к файлам нет — берём сразу содержимое.
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result == null) return;
      if (kIsWeb) {
        await _import([
          for (final f in result.files)
            if (f.bytes != null)
              (f.name, () => _storage.importBytes(f.name, f.bytes!)),
        ]);
      } else {
        await _addPaths(
          result.files.map((f) => f.path).whereType<String>().toList(),
        );
      }
    } catch (e) {
      _toast('Ошибка при выборе файла: $e', error: true);
    }
  }

  /// Ctrl+V: вставляет скопированные в проводнике файлы
  /// или скопированную картинку (скриншот).
  Future<void> _pasteFromClipboard() async {
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        await _addPaths(files);
        return;
      }
      final image = await Pasteboard.image;
      if (image != null && image.isNotEmpty) {
        final doc = await _storage.importImageBytes(image);
        setState(() => _docs.insert(0, doc));
        await _persist();
        _toast('Картинка из буфера добавлена');
        return;
      }
      _toast(
        'В буфере обмена нет файлов. Скопируйте файл в проводнике (Ctrl+C).',
      );
    } catch (e) {
      _toast('Не удалось вставить из буфера: $e', error: true);
    }
  }

  Future<void> _showAddDialog() async {
    setState(() => _dialogOpen = true);
    await showDialog<void>(
      context: context,
      builder: (_) => AddFilesDialog(
        onPick: _pickFiles,
        onPaste: _pasteFromClipboard,
        onDrop: _addPaths,
      ),
    );
    if (mounted) setState(() => _dialogOpen = false);
  }

  // ---------- Действия с документом ----------

  Future<void> _open(DocumentItem doc) async {
    final result = await Navigator.of(context).push<ViewerResult>(
      MaterialPageRoute(builder: (_) => DocumentViewerScreen(doc: doc)),
    );
    if (result == ViewerResult.delete) {
      await _delete(doc, confirm: false);
    } else if (mounted) {
      // Файл могли исправить — обновляем превью и размер.
      setState(() {});
      await _persist();
    }
  }

  Future<void> _openExternal(DocumentItem doc) async {
    final ok = await openInSystemApp(doc.path, doc.name);
    if (!ok) _toast('Не найдена программа для открытия файла', error: true);
  }

  Future<void> _rename(DocumentItem doc) async {
    final controller = TextEditingController(text: doc.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    setState(() => doc.name = name.trim());
    await _persist();
  }

  Future<void> _setCover(DocumentItem doc) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? await readFileBytes(file.path!);
    await _storage.removeCover(doc);
    final cover = await _storage.importCover(file.name, bytes);
    setState(() => doc.coverPath = cover);
    await _persist();
  }

  Future<void> _removeCover(DocumentItem doc) async {
    await _storage.removeCover(doc);
    setState(() {});
    await _persist();
  }

  Future<void> _delete(DocumentItem doc, {bool confirm = true}) async {
    if (confirm) {
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
      if (ok != true) return;
    }
    setState(() => _docs.remove(doc));
    await _storage.delete(doc);
    await _persist();
    _toast('Документ удалён');
  }

  void _onCardAction(DocumentItem doc, DocumentCardAction action) {
    switch (action) {
      case DocumentCardAction.open:
        _open(doc);
      case DocumentCardAction.rename:
        _rename(doc);
      case DocumentCardAction.setCover:
        _setCover(doc);
      case DocumentCardAction.removeCover:
        _removeCover(doc);
      case DocumentCardAction.openExternal:
        _openExternal(doc);
      case DocumentCardAction.delete:
        _delete(doc);
    }
  }

  // ---------- Интерфейс ----------

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? _docs
        : _docs
              .where((d) => d.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();

    // Узкое окно (или маленький экран) — компактная раскладка.
    final compact = MediaQuery.sizeOf(context).width < 720;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteFromClipboard,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _pickFiles,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _showAddDialog,
      },
      child: Focus(
        autofocus: true,
        child: FileDropArea(
          enable: !_dialogOpen,
          onHover: (v) => setState(() => _dragging = v),
          onDrop: _addPaths,
          child: Stack(
            children: [
              Scaffold(
                appBar: _appBar(compact),
                body: Padding(
                  padding: EdgeInsets.all(compact ? 12 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(compact),
                      if (compact && _docs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _searchField(),
                      ],
                      SizedBox(height: compact ? 12 : 20),
                      Expanded(child: _grid(visible, compact)),
                    ],
                  ),
                ),
              ),
              if (_dragging) _dropOverlay(compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Поиск по названию',
        prefixIcon: const Icon(Icons.search, size: 20),
        filled: true,
        fillColor: const Color(0xFFF2F3F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool compact) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 1,
      shadowColor: Colors.black12,
      titleSpacing: compact ? 12 : 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.folder_open_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              compact ? 'Mone App' : 'Mone App · Техкарты и документы',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: Color(0xFF2D3142),
              ),
            ),
          ),
        ],
      ),
      actions: [
        // На узком окне поиск переезжает под заголовок.
        if (!compact) ...[
          SizedBox(width: 260, child: _searchField()),
          const SizedBox(width: 16),
        ],
      ],
    );
  }

  Widget _header(bool compact) {
    final showButton = !_loading && _docs.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Все файлы и техкарты кафе',
                style: TextStyle(
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2D3142),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                !isDesktop
                    ? 'Нажмите на карточку, чтобы открыть файл.'
                    : compact
                    ? 'Нажмите на карточку, чтобы открыть. Ctrl+V — вставить файл.'
                    : 'Нажмите на карточку, чтобы открыть файл. '
                          'Перетащите файлы в окно или нажмите Ctrl+V, чтобы вставить.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  fontSize: compact ? 12 : 14,
                ),
              ),
            ],
          ),
        ),
        if (showButton) ...[
          const SizedBox(width: 12),
          // Совсем узкое окно — только значок «+».
          MediaQuery.sizeOf(context).width < 460
              ? IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: _primary),
                  tooltip: 'Добавить файл',
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add),
                )
              : _addButton(),
        ],
      ],
    );
  }

  Widget _addButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      onPressed: _showAddDialog,
      icon: const Icon(Icons.add, size: 18),
      label: const Text(
        'Добавить файл',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _grid(List<DocumentItem> visible, bool compact) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_docs.isEmpty) {
      // Нет файлов: окно «Добавить файл» по центру вместо кнопки сверху.
      // Размер подстраивается под окно, на маленьком — прокручивается.
      return LayoutBuilder(
        builder: (context, box) => Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: box.maxWidth < 540 ? box.maxWidth : 540,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight < 300 ? box.maxHeight : 300,
                ),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: _primary.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _showAddDialog,
                    hoverColor: _primary.withValues(alpha: 0.04),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 18 : 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: compact ? 48 : 64,
                            color: _primary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Пока нет файлов',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D3142),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isDesktop
                                ? 'Перетащите сюда PDF, Excel, Word или картинки '
                                      'либо нажмите Ctrl+V, чтобы вставить'
                                : 'Добавьте PDF, Excel, Word или картинки',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 20),
                          _addButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 200 : 240,
        mainAxisSpacing: compact ? 12 : 16,
        crossAxisSpacing: compact ? 12 : 16,
        childAspectRatio: 0.78,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final doc = visible[index];
        return DocumentCard(
          key: ValueKey(doc.id),
          doc: doc,
          onAction: (a) => _onCardAction(doc, a),
        );
      },
    );
  }

  Widget _dropOverlay(bool compact) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primary, width: 3),
          ),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.file_download,
                      size: compact ? 52 : 72,
                      color: _primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Отпустите файлы, чтобы добавить их',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 17 : 22,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
