import 'dart:async';

import 'package:meta/meta.dart';

class AutoServiceLocator {
  // TODO(mfeinstein): Test null being registered
  @visibleForTesting
  Map<(Type, String?), ServiceEntry<dynamic>> servicesMap = {};

  @visibleForTesting
  Map<(Type, String?), Completer<dynamic>> pendingInitializations = {};

  @visibleForTesting
  final List<(Type, String?)> resolutionStack = [];

  /// During tests it is normal to reassign types with different implementations
  /// multiple times. In case you need this, set this to `true`.
  @visibleForTesting
  bool allowReassignment = false;

  void registerSingleton<T>(Factory<T> singletonFactory, {String? withKey}) {
    _register(singletonFactory, isSingleton: true, withKey: withKey);
  }

  void registerFactory<T>(Factory<T> factory, {String? withKey}) {
    _register(factory, isSingleton: false, withKey: withKey);
  }

  void _register<T>(Factory<T> factory, {required bool isSingleton, String? withKey}) {
    if (!allowReassignment && servicesMap.containsKey((T, withKey))) {
      throw ServiceLocatorTypeAlreadyRegisteredError(T, withKey);
    }

    servicesMap[(T, withKey)] = ServiceEntry(factory: factory, isSingleton: isSingleton);

    // If there were any pending initializations for this type or key, we abort
    // it with an exception.
    _abortPendingInitializationsFor(T, withKey);
  }

  void _abortPendingInitializationsFor(Type type, String? key) {
    final pendingInitialization = pendingInitializations[(type, key)];
    if (pendingInitialization != null) {
      pendingInitializations.remove((type, key));
      pendingInitialization.completeError(
        ServiceLocatorRegistrationOverrideException(type, key),
      );
    }
  }

  void unregister<T>({String? key}) {
    final removedEntry = servicesMap.remove((T, key));

    // If there were any pending initializations for this type or key, we abort
    // it with an exception.
    _abortPendingInitializationsFor(T, key);

    if (removedEntry == null) {
      throw ServiceLocatorTypeNotRegisteredError(T, key);
    }
  }

  /// Unregisters a specific instance.
  ///
  /// If you have registered a large quantity of items, this might not have good
  /// performance, as it will do a linear search for that instance.
  void unregisterInstance(Object? instance) {
    final entriesToRemove = servicesMap.entries.where((mapEntry) {
      return identical(mapEntry.value.instance, instance);
    });

    if (entriesToRemove.isEmpty) {
      throw ServiceLocatorTypeNotRegisteredError(instance.runtimeType, null);
    }

    for (final entry in entriesToRemove) {
      servicesMap.remove(entry.key);
      // If there were any pending initializations for this type or key, we abort
      // it with an exception.
      _abortPendingInitializationsFor(entry.key.$1, entry.key.$2);
    }
  }

  Future<T> get<T>({String? withKey}) async {
    // Due to Dart's generics limitations, we can only get a ServiceEntry<dynamic> and not ServiceEntry<T>
    final service = servicesMap[(T, withKey)];

    if (service == null) {
      throw ServiceLocatorTypeOrKeyNotFoundError(T, withKey);
    }

    if (service.instance != null) {
      // Should only happen if it is a Singleton, so we don't have to check it
      return service.instance as T;
    }

    // Check for circular dependency (same call chain)
    if (resolutionStack.contains((T, withKey))) {
      final chain = [...resolutionStack.map((entry) => entry.$1), T];
      throw ServiceLocatorCircularDependencyError(chain, withKey);
    }

    // Wait for this instance, as it is already being initialised elsewhere
    final pendingInitialization = pendingInitializations[(T, withKey)];
    if (pendingInitialization != null) {
      return await pendingInitialization.future as T;
    }

    resolutionStack.add((T, withKey));
    final completer = Completer<T>();
    pendingInitializations[(T, withKey)] = completer;

    try {
      final factoryResult = service.factory(get);
      final serviceInstance = factoryResult is Future<T>
          ? await factoryResult
          : factoryResult as T;

      if (service.isSingleton) {
        // Add the missing singleton instance cache
        servicesMap[(T, withKey)] = ServiceEntry(
          factory: service.factory,
          isSingleton: true,
          instance: serviceInstance,
        );
      }

      completer.complete(serviceInstance);

      return serviceInstance;
    } catch (error) {
      completer.completeError(error);
      rethrow;
    } finally {
      resolutionStack.removeLast();
      pendingInitializations.remove((T, withKey));
    }
  }

  /// Returns if a Type [T] has been already registered or not.
  /// You can narrow down the result by providing a key using [withKey] to
  /// filter if the type was registered with that key, and a specific [instance]
  /// to check if that instance was registered for the Type and Key.
  bool isRegistered<T>({String? withKey, Object? instance}) {
    final service = servicesMap[(T, withKey)];
    if (service == null) {
      return false;
    }

    if (instance != null) {
      return identical(service.instance, instance);
    }

    return true;
  }

  @visibleForTesting
  void reset() {
    servicesMap.clear();
    pendingInitializations.clear();
    resolutionStack.clear();
  }
}

typedef Factory<TRegister> =
    FutureOr<TRegister> Function(
      FutureOr<TWanted> Function<TWanted>({String? withKey}) get,
    );

@visibleForTesting
class ServiceEntry<T> {
  ServiceEntry({required this.factory, required this.isSingleton, this.instance});

  final Factory<T> factory;
  final bool isSingleton;
  final T? instance;
}

class ServiceLocatorTypeAlreadyRegisteredError extends Error {
  ServiceLocatorTypeAlreadyRegisteredError(this.type, this.key);

  final Type type;
  final String? key;

  @override
  String toString() {
    return '${key != null ? 'The Key $key with ' : ''}Type $type is already registered. Unregister it before you try to register this type again.';
  }
}

class ServiceLocatorTypeNotRegisteredError implements Exception {
  ServiceLocatorTypeNotRegisteredError(this.type, this.key);

  final Type type;
  final String? key;

  @override
  String toString() {
    return '${key != null ? 'The Key $key with ' : ''}Type $type is was not registered. Unregister expects the type to be already registered. Unregistering a type that was not already registered is likely a bug.';
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

  final List<Type> chain;
  final String? key;

  @override
  String toString() {
    return 'Circular dependency detected${key != null ? 'for Key $key' : ''}: ${chain.join(' -> ')}';
  }
}

class ServiceLocatorRegistrationOverrideException implements Exception {
  ServiceLocatorRegistrationOverrideException(this.type, this.key);

  final Type type;
  final String? key;

  @override
  String toString() {
    return '${key != null ? 'The Key $key with t' : 'T'}he type $type was registered again, but the old instance was still initialising, and the initialisation was aborted with this Exception.';
  }
}
