class RenderException implements Exception {
  const RenderException(this.message);
  final String message;
  @override
  String toString() => message;
}
