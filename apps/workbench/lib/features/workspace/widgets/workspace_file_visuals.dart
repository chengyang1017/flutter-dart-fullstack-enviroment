import 'package:flutter/material.dart';

/// IDE-style icon + accent mapping for files commonly found in Flutter projects.
///
/// Exact scaffold/config file names are matched first, then extensions are used
/// as a fallback so imported/custom project files still get a useful visual.
@immutable
class WorkspaceFileVisual {
  const WorkspaceFileVisual(this.icon, this.color);

  final IconData icon;
  final Color color;

  static const fallback = WorkspaceFileVisual(
    Icons.description_outlined,
    Color(0xff8b93a1),
  );

  static WorkspaceFileVisual forName(
    String name, {
    bool binary = false,
  }) {
    final lower = name.toLowerCase();

    final exact = _exactNames[lower];
    if (exact != null) return exact;

    if (binary) {
      return _binaryVisual(lower);
    }

    final dot = lower.lastIndexOf('.');
    final extension = dot >= 0 && dot < lower.length - 1
        ? lower.substring(dot + 1)
        : '';

    return _extensions[extension] ?? fallback;
  }

  static WorkspaceFileVisual _binaryVisual(String lower) {
    final dot = lower.lastIndexOf('.');
    final extension = dot >= 0 && dot < lower.length - 1
        ? lower.substring(dot + 1)
        : '';

    if (_fontExtensions.contains(extension)) {
      return const WorkspaceFileVisual(
        Icons.font_download,
        Color(0xffc792ea),
      );
    }

    if (extension == 'ico') {
      return const WorkspaceFileVisual(
        Icons.apps,
        Color(0xff82aaff),
      );
    }

    return const WorkspaceFileVisual(
      Icons.image_outlined,
      Color(0xffff7ab2),
    );
  }

  static const _fontExtensions = <String>{
    'ttf',
    'otf',
    'woff',
    'woff2',
  };

  static const Map<String, WorkspaceFileVisual> _exactNames = {
    'pubspec.yaml': WorkspaceFileVisual(
      Icons.flutter_dash,
      Color(0xff54c5f8),
    ),
    'pubspec.lock': WorkspaceFileVisual(
      Icons.lock_outline,
      Color(0xff54c5f8),
    ),
    'analysis_options.yaml': WorkspaceFileVisual(
      Icons.rule,
      Color(0xff7dd3fc),
    ),
    'l10n.yaml': WorkspaceFileVisual(
      Icons.translate,
      Color(0xff7dd3fc),
    ),
    'androidmanifest.xml': WorkspaceFileVisual(
      Icons.android,
      Color(0xff9ccc65),
    ),
    'cmakelists.txt': WorkspaceFileVisual(
      Icons.construction_outlined,
      Color(0xff5ccfe6),
    ),
    '.gitignore': WorkspaceFileVisual(
      Icons.account_tree_outlined,
      Color(0xfff05133),
    ),
    '.gitattributes': WorkspaceFileVisual(
      Icons.account_tree_outlined,
      Color(0xfff05133),
    ),
    '.metadata': WorkspaceFileVisual(
      Icons.info_outline,
      Color(0xff82aaff),
    ),
    '.flutter-plugins': WorkspaceFileVisual(
      Icons.extension_outlined,
      Color(0xff54c5f8),
    ),
    '.flutter-plugins-dependencies': WorkspaceFileVisual(
      Icons.extension_outlined,
      Color(0xff54c5f8),
    ),
    'gradlew': WorkspaceFileVisual(
      Icons.build,
      Color(0xff80cbc4),
    ),
    'gradlew.bat': WorkspaceFileVisual(
      Icons.build,
      Color(0xff80cbc4),
    ),
    'gradle.properties': WorkspaceFileVisual(
      Icons.tune_outlined,
      Color(0xff80cbc4),
    ),
    'local.properties': WorkspaceFileVisual(
      Icons.tune_outlined,
      Color(0xff80cbc4),
    ),
    'podfile': WorkspaceFileVisual(
      Icons.inventory_2,
      Color(0xffff6f61),
    ),
    'podfile.lock': WorkspaceFileVisual(
      Icons.lock_outline,
      Color(0xffff6f61),
    ),
    'info.plist': WorkspaceFileVisual(
      Icons.apple,
      Color(0xffb8c0cc),
    ),
    'readme.md': WorkspaceFileVisual(
      Icons.menu_book,
      Color(0xff82aaff),
    ),
    'license': WorkspaceFileVisual(
      Icons.policy,
      Color(0xffd7aa5c),
    ),
    'license.md': WorkspaceFileVisual(
      Icons.policy,
      Color(0xffd7aa5c),
    ),
  };

  static const Map<String, WorkspaceFileVisual> _extensions = {
    'dart': WorkspaceFileVisual(
      Icons.code,
      Color(0xff54c5f8),
    ),
    'xml': WorkspaceFileVisual(
      Icons.code_outlined,
      Color(0xffffb86c),
    ),
    'yaml': WorkspaceFileVisual(
      Icons.tune_outlined,
      Color(0xffc792ea),
    ),
    'yml': WorkspaceFileVisual(
      Icons.tune_outlined,
      Color(0xffc792ea),
    ),
    'gradle': WorkspaceFileVisual(
      Icons.build,
      Color(0xff80cbc4),
    ),
    'kts': WorkspaceFileVisual(
      Icons.android,
      Color(0xffb39ddb),
    ),
    'kt': WorkspaceFileVisual(
      Icons.android,
      Color(0xffb39ddb),
    ),
    'java': WorkspaceFileVisual(
      Icons.code,
      Color(0xffffb86c),
    ),
    'properties': WorkspaceFileVisual(
      Icons.tune_outlined,
      Color(0xff80cbc4),
    ),
    'swift': WorkspaceFileVisual(
      Icons.apple,
      Color(0xffff8a65),
    ),
    'plist': WorkspaceFileVisual(
      Icons.list_alt,
      Color(0xffb8c0cc),
    ),
    'pbxproj': WorkspaceFileVisual(
      Icons.account_tree_outlined,
      Color(0xffb8c0cc),
    ),
    'xcconfig': WorkspaceFileVisual(
      Icons.tune_outlined,
      Color(0xffb8c0cc),
    ),
    'xcscheme': WorkspaceFileVisual(
      Icons.settings_outlined,
      Color(0xffb8c0cc),
    ),
    'xcworkspacedata': WorkspaceFileVisual(
      Icons.folder_copy_outlined,
      Color(0xffb8c0cc),
    ),
    'storyboard': WorkspaceFileVisual(
      Icons.dashboard_customize,
      Color(0xffff8a65),
    ),
    'entitlements': WorkspaceFileVisual(
      Icons.security,
      Color(0xffb8c0cc),
    ),
    'html': WorkspaceFileVisual(
      Icons.language_outlined,
      Color(0xffff8a65),
    ),
    'htm': WorkspaceFileVisual(
      Icons.language_outlined,
      Color(0xffff8a65),
    ),
    'js': WorkspaceFileVisual(
      Icons.javascript,
      Color(0xffffd866),
    ),
    'mjs': WorkspaceFileVisual(
      Icons.javascript,
      Color(0xffffd866),
    ),
    'ts': WorkspaceFileVisual(
      Icons.code,
      Color(0xff82aaff),
    ),
    'json': WorkspaceFileVisual(
      Icons.data_object,
      Color(0xffffd866),
    ),
    'arb': WorkspaceFileVisual(
      Icons.translate,
      Color(0xffc792ea),
    ),
    'cmake': WorkspaceFileVisual(
      Icons.construction_outlined,
      Color(0xff5ccfe6),
    ),
    'c': WorkspaceFileVisual(
      Icons.code,
      Color(0xffaab2bf),
    ),
    'cc': WorkspaceFileVisual(
      Icons.code,
      Color(0xff82aaff),
    ),
    'cpp': WorkspaceFileVisual(
      Icons.code,
      Color(0xff82aaff),
    ),
    'cxx': WorkspaceFileVisual(
      Icons.code,
      Color(0xff82aaff),
    ),
    'h': WorkspaceFileVisual(
      Icons.integration_instructions,
      Color(0xffc792ea),
    ),
    'hpp': WorkspaceFileVisual(
      Icons.integration_instructions,
      Color(0xffc792ea),
    ),
    'rc': WorkspaceFileVisual(
      Icons.settings_applications,
      Color(0xff82aaff),
    ),
    'manifest': WorkspaceFileVisual(
      Icons.description_outlined,
      Color(0xff9ccc65),
    ),
    'bat': WorkspaceFileVisual(
      Icons.terminal,
      Color(0xff7dd3fc),
    ),
    'cmd': WorkspaceFileVisual(
      Icons.terminal,
      Color(0xff7dd3fc),
    ),
    'ps1': WorkspaceFileVisual(
      Icons.terminal,
      Color(0xff82aaff),
    ),
    'sh': WorkspaceFileVisual(
      Icons.terminal,
      Color(0xff9ccc65),
    ),
    'md': WorkspaceFileVisual(
      Icons.article,
      Color(0xff82aaff),
    ),
    'txt': WorkspaceFileVisual(
      Icons.description_outlined,
      Color(0xffaab2bf),
    ),
    'lock': WorkspaceFileVisual(
      Icons.lock_outline,
      Color(0xffd7aa5c),
    ),
    'iml': WorkspaceFileVisual(
      Icons.developer_mode,
      Color(0xffff8a65),
    ),
    'png': WorkspaceFileVisual(
      Icons.image_outlined,
      Color(0xffff7ab2),
    ),
    'jpg': WorkspaceFileVisual(
      Icons.image_outlined,
      Color(0xffff7ab2),
    ),
    'jpeg': WorkspaceFileVisual(
      Icons.image_outlined,
      Color(0xffff7ab2),
    ),
    'gif': WorkspaceFileVisual(
      Icons.image_outlined,
      Color(0xffff7ab2),
    ),
    'webp': WorkspaceFileVisual(
      Icons.image_outlined,
      Color(0xffff7ab2),
    ),
    'svg': WorkspaceFileVisual(
      Icons.image_outlined,
      Color(0xffff7ab2),
    ),
    'ico': WorkspaceFileVisual(
      Icons.apps,
      Color(0xff82aaff),
    ),
    'ttf': WorkspaceFileVisual(
      Icons.font_download,
      Color(0xffc792ea),
    ),
    'otf': WorkspaceFileVisual(
      Icons.font_download,
      Color(0xffc792ea),
    ),
    'woff': WorkspaceFileVisual(
      Icons.font_download,
      Color(0xffc792ea),
    ),
    'woff2': WorkspaceFileVisual(
      Icons.font_download,
      Color(0xffc792ea),
    ),
  };
}
