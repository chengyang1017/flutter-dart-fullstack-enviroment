import '../../playground/models/ui_value.dart';

sealed class LessonRequirement {
  const LessonRequirement(this.description);
  final String description;
}

class RequiredWidgetRequirement extends LessonRequirement {
  const RequiredWidgetRequirement(this.widgetName)
      : super('包含 $widgetName Widget');
  final String widgetName;
}

class RequiredWidgetCountRequirement extends LessonRequirement {
  const RequiredWidgetCountRequirement(this.widgetName, this.count)
      : super('$widgetName 数量至少为 $count');
  final String widgetName;
  final int count;
}

class RequiredTextRequirement extends LessonRequirement {
  const RequiredTextRequirement(this.text) : super('包含文本“$text”');
  final String text;
}

class RequiredPropertyRequirement extends LessonRequirement {
  const RequiredPropertyRequirement(
    this.widgetName,
    this.propertyName, [
    this.expectedValue,
  ]) : super('$widgetName 设置 $propertyName 属性');
  final String widgetName;
  final String propertyName;
  final UiValue? expectedValue;
}

class RequiredChildRelationshipRequirement extends LessonRequirement {
  const RequiredChildRelationshipRequirement(this.parentName, this.childName)
      : super('$parentName 直接包含 $childName');
  final String parentName;
  final String childName;
}

class RequiredClassRequirement extends LessonRequirement {
  const RequiredClassRequirement(this.className) : super('声明 class $className');
  final String className;
}

class RequiredFieldRequirement extends LessonRequirement {
  const RequiredFieldRequirement(this.fieldName) : super('声明字段 $fieldName');
  final String fieldName;
}

class RequiredMethodRequirement extends LessonRequirement {
  const RequiredMethodRequirement(this.methodName) : super('声明方法 $methodName');
  final String methodName;
}

class RequiredMethodCallRequirement extends LessonRequirement {
  const RequiredMethodCallRequirement(this.methodName)
      : super('调用 $methodName');
  final String methodName;
}

class RequiredAwaitRequirement extends LessonRequirement {
  const RequiredAwaitRequirement() : super('使用 await 等待异步操作');
}

class RequiredIfRequirement extends LessonRequirement {
  const RequiredIfRequirement() : super('包含 if 条件判断');
}

class RequiredTrimRequirement extends LessonRequirement {
  const RequiredTrimRequirement() : super('调用 trim() 清理输入');
}

class RequiredCurrentUserRequirement extends LessonRequirement {
  const RequiredCurrentUserRequirement() : super('访问 FirebaseAuth currentUser');
}

class RequiredCollectionRequirement extends LessonRequirement {
  const RequiredCollectionRequirement(this.collection)
      : super("访问 collection('$collection')");
  final String collection;
}

class RequiredMapFieldsRequirement extends LessonRequirement {
  const RequiredMapFieldsRequirement(this.fields) : super('写入指定数据字段');
  final List<String> fields;
}

class RequiredServerTimestampRequirement extends LessonRequirement {
  const RequiredServerTimestampRequirement()
      : super('使用 FieldValue.serverTimestamp()');
}

class RequiredCodeIdentifierRequirement extends LessonRequirement {
  const RequiredCodeIdentifierRequirement(this.identifier)
      : super('使用标识符 $identifier');
  final String identifier;
}

class RequiredIntegerLiteralRequirement extends LessonRequirement {
  const RequiredIntegerLiteralRequirement(this.value) : super('包含数值 $value');
  final int value;
}

class RequiredRethrowRequirement extends LessonRequirement {
  const RequiredRethrowRequirement() : super('失败时使用 rethrow');
}
