class RunnerPubGetResult {
  const RunnerPubGetResult({
    required this.hasPackageConfig,
    this.lockFile,
  });

  final bool hasPackageConfig;
  final String? lockFile;

  factory RunnerPubGetResult.fromJson(Map<String, dynamic> json) {
    return RunnerPubGetResult(
      hasPackageConfig: json['hasPackageConfig'] == true,
      lockFile: json['lockFile'] is String ? json['lockFile'] as String : null,
    );
  }
}
