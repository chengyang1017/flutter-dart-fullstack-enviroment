import '../../playground/models/ui_value.dart';

sealed class LessonRequirement {
  const LessonRequirement(this.description);

  final String description;
}

class RequiredWidgetRequirement extends LessonRequirement {
  const RequiredWidgetRequirement(this.widgetName)
      : super('Contains $widgetName widget');

  final String widgetName;
}

class RequiredWidgetCountRequirement extends LessonRequirement {
  const RequiredWidgetCountRequirement(
    this.widgetName,
    this.count,
  ) : super('Contains at least $count $widgetName widgets');

  final String widgetName;
  final int count;
}

class RequiredTextRequirement extends LessonRequirement {
  const RequiredTextRequirement(this.text)
      : super('Contains text "$text"');

  final String text;
}

class RequiredPropertyRequirement extends LessonRequirement {
  const RequiredPropertyRequirement(
    this.widgetName,
    this.propertyName, [
    this.expectedValue,
  ]) : super(
          '$widgetName has the $propertyName property configured',
        );

  final String widgetName;
  final String propertyName;
  final UiValue? expectedValue;
}

class RequiredChildRelationshipRequirement extends LessonRequirement {
  const RequiredChildRelationshipRequirement(
    this.parentName,
    this.childName,
  ) : super(
          '$parentName directly contains $childName',
        );

  final String parentName;
  final String childName;
}

class RequiredClassRequirement extends LessonRequirement {
  const RequiredClassRequirement(this.className)
      : super('Declares class $className');

  final String className;
}

class RequiredFieldRequirement extends LessonRequirement {
  const RequiredFieldRequirement(this.fieldName)
      : super('Declares field $fieldName');

  final String fieldName;
}

class RequiredMethodRequirement extends LessonRequirement {
  const RequiredMethodRequirement(this.methodName)
      : super('Declares method $methodName');

  final String methodName;
}

class RequiredMethodCallRequirement extends LessonRequirement {
  const RequiredMethodCallRequirement(this.methodName)
      : super('Calls $methodName');

  final String methodName;
}

class RequiredAwaitRequirement extends LessonRequirement {
  const RequiredAwaitRequirement()
      : super('Uses await for asynchronous operations');
}

class RequiredIfRequirement extends LessonRequirement {
  const RequiredIfRequirement()
      : super('Contains an if condition');
}

class RequiredTrimRequirement extends LessonRequirement {
  const RequiredTrimRequirement()
      : super('Calls trim() to clean the input');
}

class RequiredCurrentUserRequirement extends LessonRequirement {
  const RequiredCurrentUserRequirement()
      : super('Accesses FirebaseAuth currentUser');
}

class RequiredCollectionRequirement extends LessonRequirement {
  const RequiredCollectionRequirement(this.collection)
      : super("Accesses collection('$collection')");

  final String collection;
}

class RequiredMapFieldsRequirement extends LessonRequirement {
  const RequiredMapFieldsRequirement(this.fields)
      : super('Writes the required data fields');

  final List<String> fields;
}

class RequiredServerTimestampRequirement extends LessonRequirement {
  const RequiredServerTimestampRequirement()
      : super('Uses FieldValue.serverTimestamp()');
}

class RequiredCodeIdentifierRequirement extends LessonRequirement {
  const RequiredCodeIdentifierRequirement(this.identifier)
      : super('Uses identifier $identifier');

  final String identifier;
}

class RequiredIntegerLiteralRequirement extends LessonRequirement {
  const RequiredIntegerLiteralRequirement(this.value)
      : super('Contains numeric value $value');

  final int value;
}

class RequiredRethrowRequirement extends LessonRequirement {
  const RequiredRethrowRequirement()
      : super('Uses rethrow on failure');
}