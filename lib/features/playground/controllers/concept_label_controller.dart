import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../services/concept_label_cloud_service.dart';

enum ConceptLabelScope {
  /// Legacy global replacement rule. Kept only so old saved data still loads.
  /// New labels are never created with this scope.
  language,

  /// A whole-line label anchored to one concrete source location.
  line,

  /// A selected source range anchored to one concrete source location.
  range,

  /// A user-defined display name for one function-call graph node.
  node,
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
    this.startColumn,
    this.endColumn,
    this.prefix,
    this.suffix,
    this.previousLine,
    this.nextLine,
    this.contextFingerprint,
  });

  final String id;
  final String language;
  final String source;
  final String label;
  final ConceptLabelScope scope;
  final String? filePath;

  /// Last known 1-based Workspace line.
  final int? lineNumber;

  /// Last known 0-based range inside [lineNumber]. [endColumn] is exclusive.
  final int? startColumn;
  final int? endColumn;

  /// Nearby source context used to relocate this one label after edits.
  final String? prefix;
  final String? suffix;
  final String? previousLine;
  final String? nextLine;

  /// Stable-ish source context for function-node custom names.
  final String? contextFingerprint;

  bool get isReusable => scope == ConceptLabelScope.language;
  bool get isPositionScoped =>
      scope == ConceptLabelScope.line || scope == ConceptLabelScope.range;
  bool get isNodeName => scope == ConceptLabelScope.node;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'language': language,
        'source': source,
        'label': label,
        'scope': scope.name,
        'filePath': filePath,
        'lineNumber': lineNumber,
        'startColumn': startColumn,
        'endColumn': endColumn,
        'prefix': prefix,
        'suffix': suffix,
        'previousLine': previousLine,
        'nextLine': nextLine,
        'contextFingerprint': contextFingerprint,
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

    int? readInt(String key) {
      final value = raw[key];
      return value is int ? value : int.tryParse(value?.toString() ?? '');
    }

    return ConceptLabelRule(
      id: id,
      language: language,
      source: source,
      label: label,
      scope: scope ?? ConceptLabelScope.language,
      filePath: raw['filePath']?.toString(),
      lineNumber: readInt('lineNumber'),
      startColumn: readInt('startColumn'),
      endColumn: readInt('endColumn'),
      prefix: raw['prefix']?.toString(),
      suffix: raw['suffix']?.toString(),
      previousLine: raw['previousLine']?.toString(),
      nextLine: raw['nextLine']?.toString(),
      contextFingerprint: raw['contextFingerprint']?.toString(),
    );
  }
}

class ResolvedConceptLabel {
  const ResolvedConceptLabel({
    required this.rule,
    required this.lineNumber,
    required this.startColumn,
    required this.endColumn,
    required this.source,
  });

  final ConceptLabelRule rule;

  /// 1-based Workspace line after smart relocation.
  final int lineNumber;

  /// 0-based columns in [lineNumber], with [endColumn] exclusive.
  final int startColumn;
  final int endColumn;

  /// The current source text under this resolved anchor. It can differ from the
  /// originally saved [ConceptLabelRule.source] when a long labelled expression
  /// was edited but its surrounding context still identifies it confidently.
  final String source;

  bool get lineScoped => rule.scope == ConceptLabelScope.line;
}

class ConceptLabelController extends ChangeNotifier {
  ConceptLabelController({
    ConceptLabelCloudService? cloudService,
  })  : _cloudService = cloudService ?? ConceptLabelCloudService(),
        _ownsCloudService = cloudService == null;

  static const boxName = 'concept_label_rules';
  static const int _contextChars = 48;

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

  /// Legacy API kept for old persisted rules/tests. New UI code deliberately
  /// does not apply language-wide rules anymore: every new label is anchored to
  /// one concrete source location.
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

  List<ConceptLabelRule> positionRulesForPath(String path) {
    return _rules
        .where(
          (rule) => rule.filePath == path && rule.isPositionScoped,
        )
        .toList(growable: false);
  }

  /// Resolves every position-specific label against the *current* source text.
  ///
  /// The stored line/column is only a fast first guess. If lines were inserted,
  /// removed, reformatted, or nearby source changed, the resolver searches for
  /// the original target and scores candidates by prefix/suffix, neighbouring
  /// lines, and last-known proximity. Ambiguous candidates are intentionally
  /// dropped instead of attaching a label to the wrong source occurrence.
  ///
  /// [baseLineNumber] lets callers resolve against a function snippet while
  /// keeping Workspace-global line numbers (the call graph uses this).
  List<ResolvedConceptLabel> resolveLabelsForSource({
    required String path,
    required String sourceText,
    int baseLineNumber = 1,
  }) {
    final lines = sourceText.split('\n');
    final resolved = <ResolvedConceptLabel>[];

    for (final rule in positionRulesForPath(path)) {
      final match = _resolvePositionRule(
        rule: rule,
        lines: lines,
        baseLineNumber: baseLineNumber,
      );
      if (match != null) resolved.add(match);
    }

    resolved.sort((a, b) {
      final byLine = a.lineNumber.compareTo(b.lineNumber);
      if (byLine != 0) return byLine;
      final byStart = a.startColumn.compareTo(b.startColumn);
      if (byStart != 0) return byStart;
      return b.endColumn.compareTo(a.endColumn);
    });
    return resolved;
  }

  Future<void> setPositionLabel({
    required String path,
    required String sourceText,
    required int lineNumber,
    required int startColumn,
    required int endColumn,
    required String label,
    required bool wholeLine,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) return;

    final lines = sourceText.split('\n');
    final lineIndex = lineNumber - 1;
    if (lineIndex < 0 || lineIndex >= lines.length) return;

    final line = lines[lineIndex];
    final safeStart = startColumn.clamp(0, line.length).toInt();
    final safeEnd = endColumn.clamp(safeStart, line.length).toInt();
    if (safeStart == safeEnd) return;

    final target = line.substring(safeStart, safeEnd);
    if (target.trim().isEmpty) return;

    final language = languageForPath(path);
    final scope = wholeLine ? ConceptLabelScope.line : ConceptLabelScope.range;
    final existingIndex = _rules.indexWhere(
      (rule) =>
          rule.scope == scope &&
          rule.filePath == path &&
          rule.lineNumber == lineNumber &&
          rule.startColumn == safeStart &&
          rule.endColumn == safeEnd,
    );

    final rule = ConceptLabelRule(
      id: existingIndex >= 0
          ? _rules[existingIndex].id
          : '${scope.name}-$language-${DateTime.now().microsecondsSinceEpoch}',
      language: language,
      source: target,
      label: normalizedLabel,
      scope: scope,
      filePath: path,
      lineNumber: lineNumber,
      startColumn: safeStart,
      endColumn: safeEnd,
      prefix: _tail(line.substring(0, safeStart), _contextChars),
      suffix: _head(line.substring(safeEnd), _contextChars),
      previousLine:
          lineIndex > 0 ? _normalizeContextLine(lines[lineIndex - 1]) : null,
      nextLine: lineIndex + 1 < lines.length
          ? _normalizeContextLine(lines[lineIndex + 1])
          : null,
    );

    if (existingIndex >= 0) {
      _rules[existingIndex] = rule;
    } else {
      _rules.add(rule);
    }

    await _persistAndSync(rule);
  }

  /// Backward-compatible whole-line API. New callers should use
  /// [setPositionLabel] so smart anchor context can be captured.
  Future<void> setLineLabel({
    required String path,
    required int lineNumber,
    required String sourceLine,
    required String label,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) return;

    final indent =
        RegExp(r'^\s*').firstMatch(sourceLine)?.group(0)?.length ?? 0;
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
      source: sourceLine.substring(indent),
      label: normalizedLabel,
      scope: ConceptLabelScope.line,
      filePath: path,
      lineNumber: lineNumber,
      startColumn: indent,
      endColumn: sourceLine.length,
      prefix: sourceLine.substring(0, indent),
      suffix: '',
    );

    if (existingIndex >= 0) {
      _rules[existingIndex] = rule;
    } else {
      _rules.add(rule);
    }

    await _persistAndSync(rule);
  }

  /// Legacy writer retained so old call sites/tests compile. The new UI does
  /// not call this method because global source replacement is intentionally
  /// disabled for newly-created labels.
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

    await _persistAndSync(rule);
  }

  ConceptLabelRule? nodeNameRuleFor({
    required String path,
    required String originalName,
    required int lineNumber,
    required String sourceCode,
  }) {
    final candidates = _rules
        .where(
          (rule) =>
              rule.scope == ConceptLabelScope.node && rule.filePath == path,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    final fingerprint = _nodeFingerprint(sourceCode);
    final ranked = <({ConceptLabelRule rule, int score})>[];
    for (final rule in candidates) {
      var score = 0;
      if (rule.source == originalName) score += 30;

      final savedFingerprint = rule.contextFingerprint;
      if (savedFingerprint != null) {
        if (savedFingerprint == fingerprint) {
          score += 140;
        } else {
          final similarity =
              _nodeContextSimilarity(savedFingerprint, fingerprint);
          if (similarity >= 0.35) {
            score += (similarity * 70).round();
          }
        }
      }

      final storedLine = rule.lineNumber;
      if (storedLine != null) {
        final distance = (storedLine - lineNumber).abs();
        if (distance == 0) {
          score += 80;
        } else if (distance <= 3) {
          score += 55;
        } else if (distance <= 20) {
          score += 35;
        } else if (distance <= 100) {
          score += 15;
        }
      }

      if (score >= 75) ranked.add((rule: rule, score: score));
    }

    if (ranked.isEmpty) return null;
    ranked.sort((a, b) => b.score.compareTo(a.score));
    if (ranked.length > 1 && ranked[0].score - ranked[1].score < 15) {
      return null;
    }
    return ranked.first.rule;
  }

  String? nodeNameFor({
    required String path,
    required String originalName,
    required int lineNumber,
    required String sourceCode,
  }) {
    return nodeNameRuleFor(
      path: path,
      originalName: originalName,
      lineNumber: lineNumber,
      sourceCode: sourceCode,
    )?.label;
  }

  Future<void> setNodeName({
    required String path,
    required String originalName,
    required int lineNumber,
    required String sourceCode,
    required String name,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return;

    final language = languageForPath(path);
    final existing = nodeNameRuleFor(
      path: path,
      originalName: originalName,
      lineNumber: lineNumber,
      sourceCode: sourceCode,
    );
    final existingIndex = existing == null
        ? -1
        : _rules.indexWhere((rule) => rule.id == existing.id);

    final rule = ConceptLabelRule(
      id: existingIndex >= 0
          ? _rules[existingIndex].id
          : 'node-$language-${DateTime.now().microsecondsSinceEpoch}',
      language: language,
      source: originalName,
      label: normalizedName,
      scope: ConceptLabelScope.node,
      filePath: path,
      lineNumber: lineNumber,
      contextFingerprint: _nodeFingerprint(sourceCode),
    );

    if (existingIndex >= 0) {
      _rules[existingIndex] = rule;
    } else {
      _rules.add(rule);
    }

    await _persistAndSync(rule);
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

  Future<void> _persistAndSync(ConceptLabelRule rule) async {
    await _persistLocal(rule);
    notifyListeners();

    await _syncCloud();
    notifyListeners();
  }

  ResolvedConceptLabel? _resolvePositionRule({
    required ConceptLabelRule rule,
    required List<String> lines,
    required int baseLineNumber,
  }) {
    if (lines.isEmpty || rule.source.isEmpty) return null;

    final storedLine = rule.lineNumber;
    final storedStart = rule.startColumn;
    final storedEnd = rule.endColumn;

    // Fast path: the exact saved location still contains the same source.
    if (storedLine != null) {
      final localLine = storedLine - baseLineNumber;
      if (localLine >= 0 && localLine < lines.length) {
        final line = lines[localLine];
        if (storedStart != null &&
            storedEnd != null &&
            storedStart >= 0 &&
            storedEnd >= storedStart &&
            storedEnd <= line.length &&
            line.substring(storedStart, storedEnd) == rule.source) {
          return ResolvedConceptLabel(
            rule: rule,
            lineNumber: storedLine,
            startColumn: storedStart,
            endColumn: storedEnd,
            source: rule.source,
          );
        }

        // Old line rules did not save columns. Preserve them when the original
        // line is still in place.
        if (rule.scope == ConceptLabelScope.line &&
            line.trim() == rule.source.trim()) {
          final start = _indentLength(line);
          return ResolvedConceptLabel(
            rule: rule,
            lineNumber: storedLine,
            startColumn: start,
            endColumn: line.length,
            source: line.substring(start),
          );
        }
      }
    }

    final candidates = <_AnchorCandidate>[];
    for (var localLine = 0; localLine < lines.length; localLine++) {
      final line = lines[localLine];
      final globalLine = baseLineNumber + localLine;

      if (rule.scope == ConceptLabelScope.line &&
          line.trim() == rule.source.trim()) {
        final start = _indentLength(line);
        candidates.add(
          _AnchorCandidate(
            lineNumber: globalLine,
            startColumn: start,
            endColumn: line.length,
            source: line.substring(start),
            score: _candidateScore(
                  rule: rule,
                  lines: lines,
                  localLine: localLine,
                  baseLineNumber: baseLineNumber,
                  startColumn: start,
                  endColumn: line.length,
                ) +
                30,
          ),
        );
        continue;
      }

      var from = 0;
      while (from <= line.length - rule.source.length) {
        final index = line.indexOf(rule.source, from);
        if (index < 0) break;
        final end = index + rule.source.length;
        candidates.add(
          _AnchorCandidate(
            lineNumber: globalLine,
            startColumn: index,
            endColumn: end,
            source: rule.source,
            score: _candidateScore(
              rule: rule,
              lines: lines,
              localLine: localLine,
              baseLineNumber: baseLineNumber,
              startColumn: index,
              endColumn: end,
            ),
          ),
        );
        from = index + rule.source.length;
      }
    }

    final exact = _pickCandidate(candidates);
    if (exact != null) {
      return ResolvedConceptLabel(
        rule: rule,
        lineNumber: exact.lineNumber,
        startColumn: exact.startColumn,
        endColumn: exact.endColumn,
        source: exact.source,
      );
    }

    if (rule.scope == ConceptLabelScope.line) {
      final changedLine = _pickCandidate(
        _changedLineCandidates(
          rule: rule,
          lines: lines,
          baseLineNumber: baseLineNumber,
        ),
        minimumScore: 80,
      );
      if (changedLine != null) {
        return ResolvedConceptLabel(
          rule: rule,
          lineNumber: changedLine.lineNumber,
          startColumn: changedLine.startColumn,
          endColumn: changedLine.endColumn,
          source: changedLine.source,
        );
      }
    }

    // If a longer labelled expression changed internally, keep the label only
    // when both surrounding anchors still identify one unambiguous range. Short
    // tokens such as `await` intentionally do not use this fallback: deleting
    // that token should make its label unresolved rather than moving elsewhere.
    if (rule.source.length < 6) return null;
    final contextual = _contextRangeCandidates(
      rule: rule,
      lines: lines,
      baseLineNumber: baseLineNumber,
    );
    final contextMatch = _pickCandidate(contextual, minimumScore: 70);
    if (contextMatch == null) return null;

    return ResolvedConceptLabel(
      rule: rule,
      lineNumber: contextMatch.lineNumber,
      startColumn: contextMatch.startColumn,
      endColumn: contextMatch.endColumn,
      source: contextMatch.source,
    );
  }

  List<_AnchorCandidate> _changedLineCandidates({
    required ConceptLabelRule rule,
    required List<String> lines,
    required int baseLineNumber,
  }) {
    final original = _normalizeContextLine(rule.source);
    if (original.isEmpty) return const <_AnchorCandidate>[];

    final result = <_AnchorCandidate>[];
    for (var localLine = 0; localLine < lines.length; localLine++) {
      final line = lines[localLine];
      final start = _indentLength(line);
      if (start >= line.length) continue;
      final current = line.substring(start);
      final similarity =
          _tokenSimilarity(original, _normalizeContextLine(current));
      if (similarity < 0.45) continue;

      result.add(
        _AnchorCandidate(
          lineNumber: baseLineNumber + localLine,
          startColumn: start,
          endColumn: line.length,
          source: current,
          score: (similarity * 90).round() +
              _candidateScore(
                rule: rule,
                lines: lines,
                localLine: localLine,
                baseLineNumber: baseLineNumber,
                startColumn: start,
                endColumn: line.length,
              ),
        ),
      );
    }
    return result;
  }

  List<_AnchorCandidate> _contextRangeCandidates({
    required ConceptLabelRule rule,
    required List<String> lines,
    required int baseLineNumber,
  }) {
    final prefix = rule.prefix;
    final suffix = rule.suffix;
    if (prefix == null || suffix == null) return const <_AnchorCandidate>[];

    final leftAnchor = _usefulTail(prefix);
    final rightAnchor = _usefulHead(suffix);
    if (leftAnchor.isEmpty || rightAnchor.isEmpty) {
      return const <_AnchorCandidate>[];
    }

    final result = <_AnchorCandidate>[];
    for (var localLine = 0; localLine < lines.length; localLine++) {
      final line = lines[localLine];
      var leftFrom = 0;
      while (leftFrom < line.length) {
        final leftIndex = line.indexOf(leftAnchor, leftFrom);
        if (leftIndex < 0) break;
        final start = leftIndex + leftAnchor.length;
        final rightIndex = line.indexOf(rightAnchor, start);
        if (rightIndex < 0) break;
        final end = rightIndex;
        final length = end - start;
        final maxReasonableLength = (rule.source.length * 4).clamp(24, 180);
        if (length > 0 && length <= maxReasonableLength) {
          final source = line.substring(start, end);
          result.add(
            _AnchorCandidate(
              lineNumber: baseLineNumber + localLine,
              startColumn: start,
              endColumn: end,
              source: source,
              score: 70 +
                  _candidateScore(
                    rule: rule,
                    lines: lines,
                    localLine: localLine,
                    baseLineNumber: baseLineNumber,
                    startColumn: start,
                    endColumn: end,
                  ),
            ),
          );
        }
        leftFrom = leftIndex + leftAnchor.length;
      }
    }
    return result;
  }

  int _candidateScore({
    required ConceptLabelRule rule,
    required List<String> lines,
    required int localLine,
    required int baseLineNumber,
    required int startColumn,
    required int endColumn,
  }) {
    var score = 0;
    final globalLine = baseLineNumber + localLine;
    final storedLine = rule.lineNumber;
    if (storedLine != null) {
      final distance = (storedLine - globalLine).abs();
      if (distance == 0) {
        score += 70;
      } else if (distance <= 2) {
        score += 35;
      } else if (distance <= 8) {
        score += 22;
      } else if (distance <= 40) {
        score += 12;
      } else if (distance <= 200) {
        score += 4;
      }
    }

    if (rule.startColumn != null && rule.startColumn == startColumn) {
      score += 18;
    }

    final line = lines[localLine];
    if (rule.prefix != null && rule.prefix!.isNotEmpty) {
      score += (_commonSuffixRatio(
                _normalizeInline(line.substring(0, startColumn)),
                _normalizeInline(rule.prefix!),
              ) *
              42)
          .round();
    }
    if (rule.suffix != null && rule.suffix!.isNotEmpty) {
      score += (_commonPrefixRatio(
                _normalizeInline(line.substring(endColumn)),
                _normalizeInline(rule.suffix!),
              ) *
              42)
          .round();
    }

    final previous = rule.previousLine;
    if (previous != null && localLine > 0) {
      if (_normalizeContextLine(lines[localLine - 1]) == previous) score += 24;
    }
    final next = rule.nextLine;
    if (next != null && localLine + 1 < lines.length) {
      if (_normalizeContextLine(lines[localLine + 1]) == next) score += 24;
    }
    return score;
  }

  _AnchorCandidate? _pickCandidate(
    List<_AnchorCandidate> candidates, {
    int minimumScore = 24,
  }) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) {
      return candidates.first.score >= minimumScore ? candidates.first : null;
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;
    final second = candidates[1];
    if (best.score < minimumScore) return null;
    if (best.score - second.score < 12) return null;
    return best;
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

  static int _indentLength(String line) =>
      RegExp(r'^\s*').firstMatch(line)?.group(0)?.length ?? 0;

  static String _normalizeInline(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _normalizeContextLine(String value) {
    final normalized = _normalizeInline(value);
    return normalized.length <= 160 ? normalized : normalized.substring(0, 160);
  }

  static String _tail(String value, int count) =>
      value.length <= count ? value : value.substring(value.length - count);

  static String _head(String value, int count) =>
      value.length <= count ? value : value.substring(0, count);

  static String _usefulTail(String value) {
    final compact = value.trimRight();
    return _tail(compact, 20);
  }

  static String _usefulHead(String value) {
    final compact = value.trimLeft();
    return _head(compact, 20);
  }

  static double _commonSuffixRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final limit = a.length < b.length ? a.length : b.length;
    var count = 0;
    while (count < limit &&
        a.codeUnitAt(a.length - 1 - count) ==
            b.codeUnitAt(b.length - 1 - count)) {
      count++;
    }
    return count / limit;
  }

  static double _commonPrefixRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final limit = a.length < b.length ? a.length : b.length;
    var count = 0;
    while (count < limit && a.codeUnitAt(count) == b.codeUnitAt(count)) {
      count++;
    }
    return count / limit;
  }

  static String _nodeFingerprint(String sourceCode) {
    final normalized = _normalizeInline(sourceCode);
    if (normalized.length <= 280) return normalized;
    final head = normalized.substring(0, 180);
    final tail = normalized.substring(normalized.length - 80);
    return '$head…$tail';
  }

  static double _nodeContextSimilarity(String a, String b) =>
      _tokenSimilarity(a, b);

  static double _tokenSimilarity(String a, String b) {
    Set<String> tokens(String value) => value
        .split(RegExp(r'[^A-Za-z0-9_$]+'))
        .where((token) => token.length >= 2)
        .toSet();

    final left = tokens(a);
    final right = tokens(b);
    if (left.isEmpty || right.isEmpty) {
      return a == b ? 1 : 0;
    }
    final intersection = left.intersection(right).length;
    final union = left.union(right).length;
    return union == 0 ? 0 : intersection / union;
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

class _AnchorCandidate {
  const _AnchorCandidate({
    required this.lineNumber,
    required this.startColumn,
    required this.endColumn,
    required this.source,
    required this.score,
  });

  final int lineNumber;
  final int startColumn;
  final int endColumn;
  final String source;
  final int score;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
