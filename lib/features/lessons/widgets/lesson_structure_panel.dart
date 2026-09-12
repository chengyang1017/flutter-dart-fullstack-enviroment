import 'package:flutter/material.dart';

import '../controllers/lesson_controller.dart';
import 'lesson_result_panel.dart';

class LessonStructurePanel extends StatelessWidget {
  const LessonStructurePanel({super.key, required this.controller});
  final LessonController controller;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(child: LessonResultPanel(controller: controller)),
          Card(
            margin: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('完整调用链'),
                  SizedBox(height: 10),
                  SelectableText(
                    'TextField / 发布按钮\n→ _publishPost()\n→ PostService.createPost()\n→ Firebase Auth、Storage、Firestore',
                    style: TextStyle(fontFamily: 'monospace', height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}
