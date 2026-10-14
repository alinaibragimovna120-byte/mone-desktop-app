import 'package:flutter/material.dart';

import '../services/document_parsers.dart';

const _primary = Color(0xFF4A1525);

/// Показывает содержимое Word / PowerPoint / RTF как листы бумаги:
/// заголовки, абзацы, списки, таблицы и картинки.
/// В режиме [editing] абзацы и ячейки таблиц можно исправлять.
class DocumentContentView extends StatefulWidget {
  const DocumentContentView({
    super.key,
    required this.content,
    this.editing = false,
    this.edits,
    this.onChanged,
  });

  final DocContent content;
  final bool editing;

  /// Исправления: номер абзаца → новый текст.
  final Map<int, String>? edits;
  final VoidCallback? onChanged;

  @override
  State<DocumentContentView> createState() => _DocumentContentViewState();
}

class _DocumentContentViewState extends State<DocumentContentView> {
  final Map<int, TextEditingController> _controllers = {};

  @override
  void didUpdateWidget(DocumentContentView old) {
    super.didUpdateWidget(old);
    if (!widget.editing || old.content != widget.content) _disposeControllers();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.content.pages;
    final narrow = MediaQuery.sizeOf(context).width < 720;
    return ListView.separated(
      padding: EdgeInsets.all(narrow ? 8 : 24),
      itemCount: pages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 24),
      itemBuilder: (context, i) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          width: double.infinity,
          padding: narrow
              ? const EdgeInsets.all(16)
              : const EdgeInsets.fromLTRB(48, 40, 48, 48),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child: widget.editing
              ? _page(pages[i])
              : SelectionArea(child: _page(pages[i])),
        ),
      ),
    );
  }

  Widget _page(DocPage page) {
    final blocks = page.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (page.title != null) ...[
          Text(
            page.title!,
            style: const TextStyle(
              color: Colors.black38,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (blocks.isEmpty)
          const Text('(пусто)', style: TextStyle(color: Colors.black38)),
        for (final block in blocks)
          widget.editing ? _editableBlock(block) : docBlockWidget(block),
      ],
    );
  }

  Widget _editableBlock(DocBlock block) {
    switch (block) {
      case DocParagraph(id: final int _):
        return Padding(
          padding: EdgeInsets.only(
            top: block.headingLevel > 0 ? 10 : 2,
            bottom: 2,
          ),
          child: _field(block, _paragraphStyle(block, 1)),
        );
      case DocTable():
        return _tableLayout(
          block,
          1,
          (cell, header) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in cell.paragraphs)
                if (p.id != null)
                  _field(
                    p,
                    TextStyle(
                      fontSize: 13,
                      fontWeight: header ? FontWeight.bold : null,
                    ),
                  ),
            ],
          ),
        );
      case DocParagraph():
      case DocImage():
        return docBlockWidget(block);
    }
  }

  Widget _field(DocParagraph p, TextStyle style) {
    final id = p.id!;
    final controller = _controllers.putIfAbsent(
      id,
      () => TextEditingController(text: widget.edits?[id] ?? p.text),
    );
    final allBold =
        p.runs.isNotEmpty &&
        p.runs.where((r) => r.text.trim().isNotEmpty).every((r) => r.bold);
    final field = TextField(
      controller: controller,
      maxLines: null,
      style: allBold ? style.copyWith(fontWeight: FontWeight.bold) : style,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFFFBF0),
        hoverColor: const Color(0xFFFFF3D6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
      ),
      onChanged: (value) {
        final edits = widget.edits;
        if (edits == null) return;
        if (value == p.text) {
          edits.remove(id);
        } else {
          edits[id] = value;
        }
        widget.onChanged?.call();
      },
    );
    if (!p.bullet) return field;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('  •  ', style: style),
        ),
        Expanded(child: field),
      ],
    );
  }
}

Widget docBlockWidget(DocBlock block, {double scale = 1}) {
  switch (block) {
    case DocParagraph():
      return _paragraph(block, scale);
    case DocTable():
      return _tableLayout(
        block,
        scale,
        (cell, header) => Text(
          cell.text,
          style: TextStyle(
            fontSize: 13 * scale,
            fontWeight: header ? FontWeight.bold : null,
          ),
        ),
      );
    case DocImage():
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * scale),
        child: Image.memory(
          block.bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
  }
}

TextStyle _paragraphStyle(DocParagraph p, double scale) {
  final base = switch (p.headingLevel) {
    1 => const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    2 => const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
    3 => const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    _ => const TextStyle(fontSize: 14, height: 1.5),
  };
  return base.copyWith(
    fontSize: base.fontSize! * scale,
    color: const Color(0xFF2D3142),
  );
}

Widget _paragraph(DocParagraph p, double scale) {
  if (p.text.trim().isEmpty) return SizedBox(height: 10 * scale);
  final style = _paragraphStyle(p, scale);
  final text = Text.rich(
    TextSpan(
      style: style,
      children: [
        for (final r in p.runs)
          TextSpan(
            text: r.text,
            style: TextStyle(
              fontWeight: r.bold ? FontWeight.bold : null,
              fontStyle: r.italic ? FontStyle.italic : null,
              decoration: r.underline ? TextDecoration.underline : null,
            ),
          ),
      ],
    ),
  );
  return Padding(
    padding: EdgeInsets.only(
      top: (p.headingLevel > 0 ? 12 : 2) * scale,
      bottom: (p.headingLevel > 0 ? 6 : 2) * scale,
    ),
    child: p.bullet
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('  •  ', style: style),
              Expanded(child: text),
            ],
          )
        : text,
  );
}

Widget _tableLayout(
  DocTable t,
  double scale,
  Widget Function(DocCell cell, bool header) cellBuilder,
) {
  if (t.rows.isEmpty) return const SizedBox.shrink();
  final cols = t.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 10 * scale),
    child: Table(
      border: TableBorder.all(color: Colors.black26),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var i = 0; i < t.rows.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: i == 0 ? _primary.withValues(alpha: 0.07) : null,
            ),
            children: [
              for (var j = 0; j < cols; j++)
                Padding(
                  padding: EdgeInsets.all(8 * scale),
                  child: j < t.rows[i].length
                      ? cellBuilder(t.rows[i][j], i == 0)
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    ),
  );
}
