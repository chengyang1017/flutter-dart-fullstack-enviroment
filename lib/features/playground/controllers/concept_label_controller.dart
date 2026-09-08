import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

enum ConceptLabelScope {
  language,
  line,
}

class ConceptLabelRule {
  const ConceptLabelRule({
    required this.id,
    required this.language,
    required this.source,
    required this.label,
    required this.scope,
    this.filePath,
    this.lineNumber,
  });

  final String id;
  final String language;
  final String source;
  final String label;
  final ConceptLabelScope scope;
  final String? filePath;
  final int? lineNumber;

  bool get isReusable => scope == ConceptLabelScope.language;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'language': language,
        'source': source,
        'label': label,
        'scope': scope.name,
        'filePath': filePath,
        'lineNumber': lineNumber,
      };

  static ConceptLabelRule? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final id = raw['id']?.toString();
    final language = raw['language']?.toString();
    final source = raw['source']?.toString();
    final label = raw['label']?.toString();
    if (id == null ||
        language == null ||
        source == null ||
        label == null ||
        source.isEmpty ||
        label.isEmpty) {
      return null;
    }

    final scopeName = raw['scope']?.toString();
    final scope = ConceptLabelScope.values.where((value) {
      return value.name == scopeName;
    }).firstOrNull;

    return ConceptLabelRule(
      id: id,
      language: language,
      source: source,
      label: label,
      scope: scope ?? ConceptLabelScope.language,
      filePath: raw['filePath']?.toString(),
      lineNumber: raw['lineNumber'] is int ? raw['lineNumber'] as int : null,
    );
  }
}

class ConceptLabelController extends ChangeNotifier {
  static const boxName = 'concept_label_rules';

  final List<ConceptLabelRule> _rules = <ConceptLabelRule>[];
  Box<dynamic>? _box;
  bool _loaded = false;

  bool get loaded => _loaded;
  List<ConceptLabelRule> get rules => List.unmodifiable(_rules);

  Future<void> load() async {
    if (_loaded) return;

    try {
      _box = Hive.isBoxOpen(boxName)
          ? Hive.box<dynamic>(boxName)
          : await Hive.openBox<dynamic>(boxName);

      _rules
        ..clear()
        ..addAll(
          _box!.values
              .map(ConceptLabelRule.fromJson)
              .whereType<ConceptLabelRule>(),
        );
    } catch (_) {
      // Widget tests or embedders may construct this controller without
      // initializing Hive. In that case labels still work in memory.
      _box = null;
    }

    _loaded = true;
    notifyListeners();
  }

  List<ConceptLabelRule> reusableRulesForPath(String path) {
    final language = languageForPath(path);
    return _rules
        .where(
          (rule) => rule.scope == ConceptLabelScope.language &&
              rule.language == language,
        )
        .toList(growable: false);
  }

  ConceptLabelRule? lineRuleFor({
    required String path,
    required int lineNumber,
  }) {
    final language = languageForPath(path);
    for (final rule in _rules.reversed) {
      if (rule.scope == ConceptLabelScope.line &&
          rule.language == language &&
          rule.filePath == path &&
          rule.lineNumber == lineNumber) {
        return rule;
      }
    }
    return null;
  }

  Future<void> addReusableRule({
    required String path,
    required String source,
    required String label,
  }) async {
    final normalizedSource = source.trim();
    final normalizedLabel = label.trim();
    if (normalizedSource.isEmpty || normalizedLabel.isEmpty) return;

    final language = languageForPath(path);
    final existingIndex = _rules.indexWhere(
      (rule) => rule.scope == ConceptLabelScope.language &&
          rule.language == language &&
          rule.source == normalizedSource,
    );

    final rule = ConceptLabelRule(
      id: existingIndex >= 0
          ? _rules[existingIndex].id
          : 'language-$language-${DateTime.now().microsecondsSinceEpoch}',
      language: language,
      source: normalizedSource,
      label: normalizedLabel,
      scope: ConceptLabelScope.language,
    );

    if (existingIndex >= 0) {
      _rules[existingIndex] = rule;
    } else {
      _rules.add(rule);
    }

    await _persist(rule);
    notifyListeners();
  }

  Future<void> setLineLabel({
    required String path,
    required int lineNumber,
    required String sourceLine,
    required String label,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) return;

    final language = languageForPath(path);
    final existingIndex = _rules.indexWhere(
      (rule) => rule.scope == ConceptLabelScope.line &&
          rule.filePath == path &&
          rule.lineNumber == lineNumber,
    );

    final rule = ConceptLabelRule(
      id: existingIndex >= 0
          ? _rules[existingIndex].id
          : 'line-$language-${DateTime.now().microsecondsSinceEpoch}',
      language: language,
      source: sourceLine,
      label: normalizedLabel,
      scope: ConceptLabelScope.line,
      filePath: path,
      lineNumber: lineNumber,
    );

    if (existingIndex >= 0) {
      _rules[existingIndex] = rule;
    } else {
      _rules.add(rule);
    }

    await _persist(rule);
    notifyListeners();
  }

  Future<void> removeRule(String id) async {
    _rules.removeWhere((rule) => rule.id == id);
    await _box?.delete(id);
    notifyListeners();
  }

  Future<void> _persist(ConceptLabelRule rule) async {
    try {
      await _box?.put(rule.id, rule.toJson());
    } catch (_) {
      // Keep the current session usable even if local persistence is unavailable.
    }
  }

  static String languageForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return 'dart';
    if (lower.endsWith('.js') || lower.endsWith('.ts')) return 'javascript';
    if (lower.endsWith('.java')) return 'java';
    if (lower.endsWith('.py')) return 'python';
    return 'plain';
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
