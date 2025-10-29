class ServiceLocatorTypeAlreadyRegisteredError extends Error {
  ServiceLocatorTypeAlreadyRegisteredError(this.type, this.key);

  final Type type;
  final String? key;

  @override
  String toString() {
    return '${key != null ? 'The Key $key with ' : ''}Type $type is already registered. Unregister it before trying to register this type again.';
  }
}

class ServiceLocatorUnregisterTypeNotRegisteredError implements Exception {
  ServiceLocatorUnregisterTypeNotRegisteredError(this.type, this.key);

  final Type type;
  final String? key;

  @override
  String toString() {
    return '${key != null ? 'The Key $key with ' : ''}Type $type was not registered. Unregister expects the type to be already registered. Unregistering a type that was not already registered is likely a bug.';
  }
}

class ServiceLocatorTypeOrKeyNotFoundError extends Error {
  ServiceLocatorTypeOrKeyNotFoundError(this.type, this.key);

  final Type type;
  final String? key;

  @override
  String toString() {
    return '${key != null ? 'The Key $key with t' : 'T'}he type $type was not registered. You need to register the type or key before you can use it.';
  }
}

class ServiceLocatorCircularDependencyError extends Error {
  ServiceLocatorCircularDependencyError(this.chain, this.key);

  final List<(Type, String?)> chain;
  final String? key;

  @override
  String toString() {
    final chainString = chain
        .map((entry) {
      return entry.$2 != null ? '${entry.$1}(key: ${entry.$2})' : '${entry.$1}';
    })
        .join(' -> ');
    return 'Circular dependency detected${key != null ? ' for Key $key' : ''}. Dependency resolution chain: $chainString';
  }
}

class ServiceLocatorRegistrationOverrideException implements Exception {
  ServiceLocatorRegistrationOverrideException(this.type, this.key);

  final Type type;
  final String? key;

  @override
  String toString() {
    return '${key != null ? 'The Key $key with t' : 'T'}he type $type was registered again, but the old instance was still initializing, and the initialization was aborted with this Exception.';
  }
}
