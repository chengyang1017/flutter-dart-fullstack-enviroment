import 'package:flutter_ui_playground/features/lessons/models/lesson.dart';
import 'package:flutter_ui_playground/features/lessons/models/lesson_requirement.dart';
import 'package:flutter_ui_playground/features/lessons/models/lesson_step.dart';

const Lesson testLesson = Lesson(
  id: 'test-create-post',
  title: 'Test create post lesson',
  description: 'Small in-memory lesson fixture for widget and controller tests.',
  difficulty: 'test',
  category: 'test',
  tags: <String>['test'],
  estimatedMinutes: 1,
  steps: <LessonStep>[
    LessonStep(
      id: 'test-ui-step',
      part: 'Part 1',
      title: 'Build UI',
      instruction: 'Create a text field and publish button.',
      stepType: LessonStepType.ui,
      explanation: 'UI fixture.',
      starterCode: "Text('fixture')",
      hints: <String>['Add the required widgets.'],
      requirements: <LessonRequirement>[
        RequiredWidgetRequirement('TextField'),
        RequiredWidgetRequirement('ElevatedButton'),
      ],
      relatedFiles: <String>['create_post_page.dart', 'post_service.dart'],
      checkMode: CheckMode.uiAst,
    ),
    LessonStep(
      id: 'test-logic-step',
      part: 'Part 2',
      title: 'Add logic',
      instruction: 'Add the publish logic.',
      stepType: LessonStepType.logic,
      explanation: 'Logic fixture.',
      starterCode: '',
      hints: <String>['Write Dart code.'],
      requirements: <LessonRequirement>[],
      relatedFiles: <String>['create_post_page.dart', 'post_service.dart'],
      checkMode: CheckMode.dartAst,
    ),
    LessonStep(
      id: 'test-service-step',
      part: 'Part 3',
      title: 'Add service',
      instruction: 'Add a service.',
      stepType: LessonStepType.service,
      explanation: 'Service fixture.',
      starterCode: '',
      hints: <String>['Write a service.'],
      requirements: <LessonRequirement>[],
      relatedFiles: <String>['post_service.dart', 'create_post_page.dart'],
      checkMode: CheckMode.dartAst,
    ),
  ],
);
