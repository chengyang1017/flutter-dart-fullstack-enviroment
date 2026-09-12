enum PackageDependencyGroup {
  dependencies,
  devDependencies;

  String get yamlKey => switch (this) {
        PackageDependencyGroup.dependencies => 'dependencies',
        PackageDependencyGroup.devDependencies => 'dev_dependencies',
      };
}

enum PackageDependencySource {
  hosted,
  sdk,
  git,
  path,
  other;

  String get label => switch (this) {
        PackageDependencySource.hosted => 'pub.dev',
        PackageDependencySource.sdk => 'SDK',
        PackageDependencySource.git => 'Git',
        PackageDependencySource.path => 'Path',
        PackageDependencySource.other => 'Other',
      };
}

class PackageDependencyInfo {
  const PackageDependencyInfo({
    required this.name,
    required this.constraint,
    required this.group,
    required this.source,
    this.resolvedVersion,
  });

  final String name;
  final String constraint;
  final PackageDependencyGroup group;
  final PackageDependencySource source;
  final String? resolvedVersion;
}

class PubDevPackageInfo {
  const PubDevPackageInfo({
    required this.name,
    required this.latestVersion,
    required this.versions,
    required this.description,
  });

  final String name;
  final String latestVersion;
  final List<String> versions;
  final String description;
}
