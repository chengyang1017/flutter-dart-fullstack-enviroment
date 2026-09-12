import 'package:flutter/material.dart';

@immutable
class WorkbenchPalette {
  const WorkbenchPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.selection,
    required this.editorBackground,
    required this.editorText,
    required this.lineNumber,
    required this.activeLineNumber,
  });

  factory WorkbenchPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    return WorkbenchPalette(
      background: scheme.surfaceContainerLow,
      surface: scheme.surface,
      surfaceRaised: scheme.surfaceContainer,
      border: scheme.outlineVariant,
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      accent: scheme.primary,
      selection: scheme.primaryContainer,
      editorBackground: dark ? const Color(0xff111318) : const Color(0xffffffff),
      editorText: dark ? const Color(0xffd6deeb) : const Color(0xff1f2937),
      lineNumber: dark ? const Color(0xff626a77) : const Color(0xff8a95a5),
      activeLineNumber:
          dark ? const Color(0xffc7ccd6) : const Color(0xff374151),
    );
  }

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color selection;
  final Color editorBackground;
  final Color editorText;
  final Color lineNumber;
  final Color activeLineNumber;
}
