import 'package:flutter/material.dart';

import '../../playground/models/ui_value.dart';
import '../models/lesson.dart';
import '../models/lesson_project.dart';
import '../models/lesson_requirement.dart';
import '../models/lesson_step.dart';

abstract final class LessonCatalogCodec {
  static Map<String, Object?> encodeProjects(List<LessonProject> projects) {
    return <String, Object?>{
      'schemaVersion': 1,
      'projects': projects.map(_encodeProject).toList(growable: false),
    };
  }

  static List<LessonProject> decodeProjects(Map<String, dynamic> json) {
    final rawProjects = json['projects'];
    if (rawProjects is! Iterable) {
      throw const FormatException('Lesson catalog projects must be an array.');
    }
    return rawProjects.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Lesson project must be an object.');
      }
      return _decodeProject(Map<String, dynamic>.from(raw));
    }).toList(growable: false);
  }

  static Map<String, Object?> _encodeProject(LessonProject project) {
    return <String, Object?>{
      'id': project.id,
      'title': project.title,
      'description': project.description,
      'icon': _encodeIcon(project.icon),
      'lessons': project.lessons.map(_encodeLesson).toList(growable: false),
    };
  }

  static LessonProject _decodeProject(Map<String, dynamic> json) {
    final lessons = _list(json, 'lessons').map((raw) {
      if (raw is! Map) {
        throw const FormatException('Lesson must be an object.');
      }
      return _decodeLesson(Map<String, dynamic>.from(raw));
    }).toList(growable: false);

    return LessonProject(
      id: _string(json, 'id'),
      title: _string(json, 'title'),
      description: _string(json, 'description'),
      icon: _decodeIcon(json['icon']?.toString()),
      lessons: lessons,
    );
  }

  static Map<String, Object?> _encodeLesson(Lesson lesson) {
    return <String, Object?>{
      'id': lesson.id,
      'title': lesson.title,
      'description': lesson.description,
      'difficulty': lesson.difficulty,
      'category': lesson.category,
      'tags': lesson.tags,
      'estimatedMinutes': lesson.estimatedMinutes,
      'prerequisites': lesson.prerequisites,
      'comingSoon': lesson.comingSoon,
      'version': lesson.version.name,
      'steps': lesson.steps.map(_encodeStep).toList(growable: false),
    };
  }

  static Lesson _decodeLesson(Map<String, dynamic> json) {
    final versionName = json['version']?.toString() ?? LessonVersion.beginner.name;
    return Lesson(
      id: _string(json, 'id'),
      title: _string(json, 'title'),
      description: _string(json, 'description'),
      difficulty: _string(json, 'difficulty'),
      category: _string(json, 'category'),
      tags: _stringList(json['tags']),
      estimatedMinutes: _integer(json, 'estimatedMinutes'),
      prerequisites: _stringList(json['prerequisites']),
      comingSoon: json['comingSoon'] == true,
      version: LessonVersion.values.firstWhere(
        (value) => value.name == versionName,
        orElse: () => LessonVersion.beginner,
      ),
      steps: _list(json, 'steps').map((raw) {
        if (raw is! Map) {
          throw const FormatException('Lesson step must be an object.');
        }
        return _decodeStep(Map<String, dynamic>.from(raw));
      }).toList(growable: false),
    );
  }

  static Map<String, Object?> _encodeStep(LessonStep step) {
    return <String, Object?>{
      'id': step.id,
      'part': step.part,
      'title': step.title,
      'instruction': step.instruction,
      'stepType': step.stepType.name,
      'explanation': step.explanation,
      'starterCode': step.starterCode,
      'standardAnswerAssets': step.standardAnswerAssets,
      'hints': step.hints,
      'requirements':
          step.requirements.map(_encodeRequirement).toList(growable: false),
      'relatedFiles': step.relatedFiles,
      'checkMode': step.checkMode.name,
    };
  }

  static LessonStep _decodeStep(Map<String, dynamic> json) {
    final stepTypeName = json['stepType']?.toString() ?? LessonStepType.ui.name;
    final checkModeName = json['checkMode']?.toString() ?? CheckMode.uiAst.name;

    final rawAssets = json['standardAnswerAssets'];
    final answerAssets = <String, String>{};
    if (rawAssets is Map) {
      for (final entry in rawAssets.entries) {
        answerAssets[entry.key.toString()] = entry.value.toString();
      }
    }

    return LessonStep(
      id: _string(json, 'id'),
      part: _string(json, 'part'),
      title: _string(json, 'title'),
      instruction: _string(json, 'instruction'),
      stepType: LessonStepType.values.firstWhere(
        (value) => value.name == stepTypeName,
        orElse: () => LessonStepType.ui,
      ),
      explanation: _string(json, 'explanation'),
      starterCode: _string(json, 'starterCode'),
      standardAnswerAssets: answerAssets,
      hints: _stringList(json['hints']),
      requirements: _list(json, 'requirements').map((raw) {
        if (raw is! Map) {
          throw const FormatException('Lesson requirement must be an object.');
        }
        return _decodeRequirement(Map<String, dynamic>.from(raw));
      }).toList(growable: false),
      relatedFiles: _stringList(json['relatedFiles']),
      checkMode: CheckMode.values.firstWhere(
        (value) => value.name == checkModeName,
        orElse: () => CheckMode.uiAst,
      ),
    );
  }

  static Map<String, Object?> _encodeRequirement(
    LessonRequirement requirement,
  ) {
    return switch (requirement) {
      RequiredWidgetRequirement value => <String, Object?>{
          'type': 'widget',
          'widgetName': value.widgetName,
        },
      RequiredWidgetCountRequirement value => <String, Object?>{
          'type': 'widgetCount',
          'widgetName': value.widgetName,
          'count': value.count,
        },
      RequiredTextRequirement value => <String, Object?>{
          'type': 'text',
          'text': value.text,
        },
      RequiredPropertyRequirement value => <String, Object?>{
          'type': 'property',
          'widgetName': value.widgetName,
          'propertyName': value.propertyName,
          if (value.expectedValue != null)
            'expectedValue': _encodeUiValue(value.expectedValue!),
        },
      RequiredChildRelationshipRequirement value => <String, Object?>{
          'type': 'childRelationship',
          'parentName': value.parentName,
          'childName': value.childName,
        },
      RequiredClassRequirement value => <String, Object?>{
          'type': 'class',
          'className': value.className,
        },
      RequiredFieldRequirement value => <String, Object?>{
          'type': 'field',
          'fieldName': value.fieldName,
        },
      RequiredMethodRequirement value => <String, Object?>{
          'type': 'method',
          'methodName': value.methodName,
        },
      RequiredMethodCallRequirement value => <String, Object?>{
          'type': 'methodCall',
          'methodName': value.methodName,
        },
      RequiredAwaitRequirement() => const <String, Object?>{'type': 'await'},
      RequiredIfRequirement() => const <String, Object?>{'type': 'if'},
      RequiredTrimRequirement() => const <String, Object?>{'type': 'trim'},
      RequiredCurrentUserRequirement() =>
        const <String, Object?>{'type': 'currentUser'},
      RequiredCollectionRequirement value => <String, Object?>{
          'type': 'collection',
          'collection': value.collection,
        },
      RequiredMapFieldsRequirement value => <String, Object?>{
          'type': 'mapFields',
          'fields': value.fields,
        },
      RequiredServerTimestampRequirement() =>
        const <String, Object?>{'type': 'serverTimestamp'},
      RequiredCodeIdentifierRequirement value => <String, Object?>{
          'type': 'identifier',
          'identifier': value.identifier,
        },
      RequiredIntegerLiteralRequirement value => <String, Object?>{
          'type': 'integerLiteral',
          'value': value.value,
        },
      RequiredRethrowRequirement() =>
        const <String, Object?>{'type': 'rethrow'},
    };
  }

  static LessonRequirement _decodeRequirement(Map<String, dynamic> json) {
    return switch (_string(json, 'type')) {
      'widget' => RequiredWidgetRequirement(_string(json, 'widgetName')),
      'widgetCount' => RequiredWidgetCountRequirement(
          _string(json, 'widgetName'),
          _integer(json, 'count'),
        ),
      'text' => RequiredTextRequirement(_string(json, 'text')),
      'property' => RequiredPropertyRequirement(
          _string(json, 'widgetName'),
          _string(json, 'propertyName'),
          json['expectedValue'] is Map
              ? _decodeUiValue(
                  Map<String, dynamic>.from(json['expectedValue'] as Map),
                )
              : null,
        ),
      'childRelationship' => RequiredChildRelationshipRequirement(
          _string(json, 'parentName'),
          _string(json, 'childName'),
        ),
      'class' => RequiredClassRequirement(_string(json, 'className')),
      'field' => RequiredFieldRequirement(_string(json, 'fieldName')),
      'method' => RequiredMethodRequirement(_string(json, 'methodName')),
      'methodCall' =>
        RequiredMethodCallRequirement(_string(json, 'methodName')),
      'await' => const RequiredAwaitRequirement(),
      'if' => const RequiredIfRequirement(),
      'trim' => const RequiredTrimRequirement(),
      'currentUser' => const RequiredCurrentUserRequirement(),
      'collection' =>
        RequiredCollectionRequirement(_string(json, 'collection')),
      'mapFields' => RequiredMapFieldsRequirement(
          _stringList(json['fields']),
        ),
      'serverTimestamp' => const RequiredServerTimestampRequirement(),
      'identifier' =>
        RequiredCodeIdentifierRequirement(_string(json, 'identifier')),
      'integerLiteral' =>
        RequiredIntegerLiteralRequirement(_integer(json, 'value')),
      'rethrow' => const RequiredRethrowRequirement(),
      final type => throw FormatException(
          'Unsupported lesson requirement type: $type',
        ),
    };
  }

  static Map<String, Object?> _encodeUiValue(UiValue value) {
    return switch (value) {
      StringUiValue item => <String, Object?>{
          'type': 'string',
          'value': item.value,
        },
      NumberUiValue item => <String, Object?>{
          'type': 'number',
          'value': item.value,
        },
      BooleanUiValue item => <String, Object?>{
          'type': 'boolean',
          'value': item.value,
        },
      NullUiValue() => const <String, Object?>{'type': 'null'},
      IdentifierUiValue item => <String, Object?>{
          'type': 'identifier',
          'value': item.value,
        },
      ListUiValue item => <String, Object?>{
          'type': 'list',
          'values': item.values.map(_encodeUiValue).toList(growable: false),
        },
      NodeUiValue() => throw const FormatException(
          'NodeUiValue is not supported in persisted lesson requirements.',
        ),
    };
  }

  static UiValue _decodeUiValue(Map<String, dynamic> json) {
    return switch (_string(json, 'type')) {
      'string' => StringUiValue(_string(json, 'value')),
      'number' => NumberUiValue(
          json['value'] is num
              ? json['value'] as num
              : num.parse(json['value'].toString()),
        ),
      'boolean' => BooleanUiValue(json['value'] == true),
      'null' => const NullUiValue(),
      'identifier' => IdentifierUiValue(_string(json, 'value')),
      'list' => ListUiValue(
          _list(json, 'values').map((raw) {
            if (raw is! Map) {
              throw const FormatException('UiValue list entry must be an object.');
            }
            return _decodeUiValue(Map<String, dynamic>.from(raw));
          }).toList(growable: false),
        ),
      final type => throw FormatException('Unsupported UiValue type: $type'),
    };
  }

  static String _encodeIcon(IconData icon) {
    if (icon == Icons.forum_outlined) return 'forum';
    if (icon == Icons.shopping_bag_outlined) return 'shoppingBag';
    if (icon == Icons.school_outlined) return 'school';
    if (icon == Icons.code_rounded) return 'code';
    return 'school';
  }

  static IconData _decodeIcon(String? value) {
    return switch (value) {
      'forum' => Icons.forum_outlined,
      'shoppingBag' => Icons.shopping_bag_outlined,
      'code' => Icons.code_rounded,
      _ => Icons.school_outlined,
    };
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) throw FormatException('$key is required.');
    final result = value.toString();
    if (result.isEmpty) throw FormatException('$key is required.');
    return result;
  }

  static int _integer(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('$key must be an integer.');
    return parsed;
  }

  static List<dynamic> _list(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) throw FormatException('$key must be an array.');
    return value;
  }

  static List<String> _stringList(Object? value) {
    if (value == null) return const <String>[];
    if (value is! Iterable) {
      throw const FormatException('Expected an array of strings.');
    }
    return value.map((item) => item.toString()).toList(growable: false);
  }
}
