import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/lessons/data/lesson_catalog_repository.dart';
import 'features/workspace/services/hive_workspace_persistence.dart';
import 'features/workspace/services/workspace_auth_runtime.dart';
import 'features/workspace/services/workspace_auth_session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await AppThemeController.initialize();
  await AppLocaleController.initialize();
  await Hive.openBox<dynamic>('lesson_progress');
  await HiveWorkspacePersistence.openBoxes();
  await WorkspaceAuthSessionStore.openBox();
  final authenticated = await WorkspaceAuthRuntime.bootstrap();
  runApp(const PlaygroundApp());

  // Migration is intentionally best-effort and runs after first paint. The
  // server only accepts the bootstrap from an administrator account and only
  // while the remote lesson catalog is still empty.
  if (authenticated) {
    unawaited(_bootstrapManagedLessonCatalog());
  }
}

Future<void> _bootstrapManagedLessonCatalog() async {
  final repository = LessonCatalogRepository();
  try {
    await repository.loadProjects();
  } finally {
    repository.close();
  }
}
