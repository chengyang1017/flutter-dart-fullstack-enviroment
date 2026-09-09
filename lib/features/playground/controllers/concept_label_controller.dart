import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../services/concept_label_cloud_service.dart';

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
  ConceptLabelController({
    ConceptLabelCloudService? cloudService,
  })  : _cloudService = cloudService ?? ConceptLabelCloudService(),
        _ownsCloudService = cloudService == null;

  static const boxName = 'concept_label_rules';

  final List<ConceptLabelRule> _rules = <ConceptLabelRule>[];
  final ConceptLabelCloudService _cloudService;
  final bool _ownsCloudService;

  Box<dynamic>? _box;
  bool _loaded = false;
  bool _cloudSynced = false;
  String? _cloudSyncError;

  bool get loaded => _loaded;
  bool get cloudAvailable => _cloudService.available;
  bool get cloudSynced => _cloudSynced;
  String? get cloudSyncError => _cloudSyncError;
  List<ConceptLabelRule> get rules => List.unmodifiable(_rules);

  Future<void> load() async {
    if (_loaded) return;

    await _loadLocal();
    _loaded = true;
    notifyListeners();

    if (_cloudService.available) {
      await _loadCloud();
      notifyListeners();
    }
  }

  Future<void> _loadLocal() async {
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
  }

  Future<void> _loadCloud() async {
    try {
      final payload = await _cloudService.loadPayload();

      if (payload == null) {
        // First cloud run: migrate whatever the user already had in Hive,
        // including an empty list, so cloud becomes authoritative afterwards.
        await _cloudService.savePayload(_encodeRules());
      } else {
        final cloudRules = _decodeRules(payload);
        _rules
          ..clear()
          ..addAll(cloudRules);
        await _replaceLocalCache();
      }

      _cloudSynced = true;
      _cloudSyncError = null;
    } catch (error) {
      // Keep the offline cache usable. A later add/remove operation will retry
      // a full cloud snapshot save automatically.
      _cloudSynced = false;
      _cloudSyncError = error.toString();
    }
  }

  List<ConceptLabelRule> reusableRulesForPath(String path) {
    final language = languageForPath(path);
    return _rules
        .where(
          (rule) =>
              rule.scope == ConceptLabelScope.language &&
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
      (rule) =>
          rule.scope == ConceptLabelScope.language &&
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

    await _persistLocal(rule);
    notifyListeners();

    await _syncCloud();
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
      (rule) =>
          rule.scope == ConceptLabelScope.line &&
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

    await _persistLocal(rule);
    notifyListeners();

    await _syncCloud();
    notifyListeners();
  }

  Future<void> removeRule(String id) async {
    _rules.removeWhere((rule) => rule.id == id);

    try {
      await _box?.delete(id);
    } catch (_) {
      // The in-memory state is still authoritative for this session.
    }

    notifyListeners();

    await _syncCloud();
    notifyListeners();
  }

  Future<void> _persistLocal(ConceptLabelRule rule) async {
    try {
      await _box?.put(rule.id, rule.toJson());
    } catch (_) {
      // Keep the current session usable even if local persistence is unavailable.
    }
  }

  Future<void> _replaceLocalCache() async {
    final box = _box;
    if (box == null) return;

    try {
      await box.clear();
      for (final rule in _rules) {
        await box.put(rule.id, rule.toJson());
      }
    } catch (_) {
      // Cloud remains authoritative; local cache failure should not drop labels.
    }
  }

  Future<void> _syncCloud() async {
    if (!_cloudService.available) {
      _cloudSynced = false;
      _cloudSyncError = null;
      return;
    }

    try {
      await _cloudService.savePayload(_encodeRules());
      _cloudSynced = true;
      _cloudSyncError = null;
    } catch (error) {
      _cloudSynced = false;
      _cloudSyncError = error.toString();
    }
  }

  String _encodeRules() => jsonEncode(
        _rules.map((rule) => rule.toJson()).toList(growable: false),
      );

  List<ConceptLabelRule> _decodeRules(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Iterable) {
      throw const FormatException('Cloud concept labels must be a JSON array.');
    }

    return decoded
        .map(ConceptLabelRule.fromJson)
        .whereType<ConceptLabelRule>()
        .toList(growable: false);
  }

  static String languageForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return 'dart';
    if (lower.endsWith('.js') || lower.endsWith('.ts')) return 'javascript';
    if (lower.endsWith('.java')) return 'java';
    if (lower.endsWith('.py')) return 'python';
    return 'plain';
  }

  @override
  void dispose() {
    if (_ownsCloudService) {
      _cloudService.dispose();
    }
    super.dispose();
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
