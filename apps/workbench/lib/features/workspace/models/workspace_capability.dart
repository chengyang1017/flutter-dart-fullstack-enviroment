enum FirebaseCapability {
  auth,
  firestore,
  storage,
  messaging,
  functions,
}

extension FirebaseCapabilityMetadata on FirebaseCapability {
  String get flutterPackage => switch (this) {
        FirebaseCapability.auth => 'firebase_auth',
        FirebaseCapability.firestore => 'cloud_firestore',
        FirebaseCapability.storage => 'firebase_storage',
        FirebaseCapability.messaging => 'firebase_messaging',
        FirebaseCapability.functions => 'cloud_functions',
      };
}

class FirebaseCapabilityCodec {
  const FirebaseCapabilityCodec._();

  static Set<FirebaseCapability> decode(Object? source) {
    if (source == null) return const <FirebaseCapability>{};
    if (source is! Iterable) {
      throw const FormatException('Firebase capabilities must be a list.');
    }

    final result = <FirebaseCapability>{};
    for (final raw in source) {
      if (raw is! String) {
        throw const FormatException(
          'Firebase capability names must be strings.',
        );
      }
      for (final capability in FirebaseCapability.values) {
        if (capability.name == raw) {
          result.add(capability);
          break;
        }
      }
    }
    return Set<FirebaseCapability>.unmodifiable(result);
  }

  static List<String> encode(Iterable<FirebaseCapability> capabilities) {
    final names = capabilities.map((value) => value.name).toSet().toList()
      ..sort();
    return List<String>.unmodifiable(names);
  }
}

Set<String> firebaseFlutterPackages(
  Iterable<FirebaseCapability> capabilities,
) {
  final selected = capabilities.toSet();
  if (selected.isEmpty) return const <String>{};

  final packages = <String>{'firebase_core'};
  for (final capability in selected) {
    packages.add(capability.flutterPackage);
  }
  return Set<String>.unmodifiable(packages);
}
