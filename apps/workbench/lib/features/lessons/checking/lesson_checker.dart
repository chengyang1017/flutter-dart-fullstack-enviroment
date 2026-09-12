import '../../playground/models/ui_node.dart';
import '../../playground/models/ui_value.dart';
import '../../playground/parser/flutter_ui_parser.dart';
import '../models/lesson_check_result.dart';
import '../models/lesson_requirement.dart';
import '../models/lesson_step.dart';
import 'dart_ast_checker.dart';
import 'ui_node_query.dart';

class LessonChecker {
  LessonChecker({FlutterUiParser? parser})
      : _parser = parser ?? FlutterUiParser();
  final FlutterUiParser _parser;
  final DartAstChecker _dartChecker = DartAstChecker();

  LessonCheckResult checkStep(String code, LessonStep step) {
    if (step.checkMode == CheckMode.uiAst) {
      return check(code, step.requirements);
    }
    if (step.checkMode == CheckMode.dartAst) {
      final parseError = _dartChecker.syntaxError(code);
      if (parseError != null) {
        return LessonCheckResult(results: const [], parseError: parseError);
      }
      return LessonCheckResult(
        results: step.requirements
            .map((requirement) => RequirementCheckResult(
                  requirement: requirement,
                  passed: _dartChecker.check(code, requirement),
                ))
            .toList(),
      );
    }
    return LessonCheckResult(
      results: step.requirements
          .map((requirement) =>
              RequirementCheckResult(requirement: requirement, passed: false))
          .toList(),
    );
  }

  LessonCheckResult check(String code, List<LessonRequirement> requirements) {
    try {
      final root = _parser.parse(code);
      return LessonCheckResult(
        results: requirements
            .map(
              (requirement) => RequirementCheckResult(
                requirement: requirement,
                passed: _matches(root, requirement),
              ),
            )
            .toList(),
      );
    } catch (error) {
      return LessonCheckResult(results: const [], parseError: error.toString());
    }
  }

  bool _matches(UiNode root, LessonRequirement requirement) =>
      switch (requirement) {
        RequiredWidgetRequirement r => root.containsWidget(r.widgetName),
        RequiredWidgetCountRequirement r =>
          root.countWidget(r.widgetName) >= r.count,
        RequiredTextRequirement r => root.hasText(r.text),
        RequiredPropertyRequirement r => root.findWidgets(r.widgetName).any(
              (node) =>
                  node.namedArguments.containsKey(r.propertyName) &&
                  (r.expectedValue == null ||
                      _sameValue(node.namedArguments[r.propertyName],
                          r.expectedValue)),
            ),
        RequiredChildRelationshipRequirement r =>
          root.hasParentChild(r.parentName, r.childName),
        _ => false,
      };

  bool _sameValue(UiValue? actual, UiValue? expected) {
    if (actual.runtimeType != expected.runtimeType) return false;
    return switch ((actual, expected)) {
      (StringUiValue a, StringUiValue e) => a.value == e.value,
      (NumberUiValue a, NumberUiValue e) => a.value == e.value,
      (BooleanUiValue a, BooleanUiValue e) => a.value == e.value,
      (IdentifierUiValue a, IdentifierUiValue e) => a.value == e.value,
      (NullUiValue _, NullUiValue _) => true,
      (NodeUiValue a, NodeUiValue e) => _sameNode(a.value, e.value),
      (ListUiValue a, ListUiValue e) => a.values.length == e.values.length &&
          Iterable.generate(a.values.length).every(
            (index) => _sameValue(a.values[index], e.values[index]),
          ),
      _ => false,
    };
  }

  bool _sameNode(UiNode actual, UiNode expected) =>
      actual.type == expected.type &&
      actual.positionalArguments.length ==
          expected.positionalArguments.length &&
      Iterable.generate(actual.positionalArguments.length).every(
        (index) => _sameValue(
          actual.positionalArguments[index],
          expected.positionalArguments[index],
        ),
      ) &&
      expected.namedArguments.entries.every(
        (entry) => _sameValue(actual.namedArguments[entry.key], entry.value),
      );
}
