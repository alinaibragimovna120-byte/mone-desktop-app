import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../services/platform.dart';

/// Область, куда можно перетащить файлы мышкой. Работает только на
/// компьютере; на телефоне просто показывает содержимое.
class FileDropArea extends StatelessWidget {
  const FileDropArea({
    super.key,
    required this.child,
    required this.onDrop,
    this.onHover,
    this.enable = true,
  });

  final Widget child;
  final ValueChanged<List<String>> onDrop;

  /// true — файлы тащат над областью, false — увели или отпустили.
  final ValueChanged<bool>? onHover;
  final bool enable;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return DropTarget(
      enable: enable,
      onDragEntered: (_) => onHover?.call(true),
      onDragExited: (_) => onHover?.call(false),
      onDragDone: (details) {
        onHover?.call(false);
        onDrop(details.files.map((f) => f.path).toList());
      },
      child: child,
    );
  }
}
