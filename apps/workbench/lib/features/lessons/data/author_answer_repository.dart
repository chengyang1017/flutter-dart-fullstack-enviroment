import 'package:flutter/services.dart';

enum AuthorAnswerStatus { available, notRecorded }

class AuthorAnswer {
  const AuthorAnswer._(this.status, this.code);

  const AuthorAnswer.available(String code)
      : this._(AuthorAnswerStatus.available, code);
  const AuthorAnswer.notRecorded()
      : this._(AuthorAnswerStatus.notRecorded, null);

  final AuthorAnswerStatus status;
  final String? code;
  bool get isAvailable => status == AuthorAnswerStatus.available;
}

class AuthorAnswerRepository {
  AuthorAnswerRepository({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final Map<String, AuthorAnswer> _cache = {};

  Future<AuthorAnswer> load(String assetPath) async {
    final cached = _cache[assetPath];
    if (cached != null) return cached;
    try {
      final originalCode = await _bundle.loadString(assetPath, cache: false);
      final answer = AuthorAnswer.available(originalCode);
      _cache[assetPath] = answer;
      return answer;
    } on Object {
      const answer = AuthorAnswer.notRecorded();
      _cache[assetPath] = answer;
      return answer;
    }
  }
}
