import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'features/workspace/services/hive_workspace_persistence.dart';
import 'features/workspace/services/workspace_cloud_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<dynamic>('lesson_progress');
  await HiveWorkspacePersistence.openBoxes();
  await WorkspaceCloudRuntime.initializeFromEnvironment();
  runApp(const PlaygroundApp());
}
