import 'package:hive/hive.dart';

class LessonProgressStore {
  LessonProgressStore(this.box);
  LessonProgressStore.memory() : box = null;

  final Box<dynamic>? box;
  final Map<String, Map<String, dynamic>> _memory = {};

  Map<String, dynamic> load(String lessonId) {
    final hiveBox = box;
    if (hiveBox == null) {
      return Map<String, dynamic>.from(_memory[lessonId] ?? const {});
    }
    return Map<String, dynamic>.from(
      hiveBox.get(lessonId, defaultValue: <String, dynamic>{}) as Map,
    );
  }

  Future<void> save(String lessonId, Map<String, dynamic> progress) async {
    final hiveBox = box;
    if (hiveBox == null) {
      _memory[lessonId] = Map<String, dynamic>.from(progress);
      return;
    }
    await hiveBox.put(lessonId, progress);
  }
}
