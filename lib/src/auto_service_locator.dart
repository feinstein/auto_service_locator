import 'dart:async';

import 'package:meta/meta.dart';

class AutoServiceLocator {
  // TODO(mfeinstein): Test null being registered
  @visibleForTesting
  Map<(Type, String?), ServiceEntry<dynamic>> servicesMap = {};

  Set<String> keys = {};

  @visibleForTesting
  Map<(Type, String?), Completer<dynamic>> pendingInitializations = {};

  @visibleForTesting
  final List<(Type, String?)> resolutionStack = [];

  /// During tests it is normal to reassign types with different implementations
  /// multiple times. In case you need this, set this to `true`.
  ///
  /// Be aware that if there are any pending initializations for a type that is being
  /// registered again, the pending initialization will complete with an error.
  @visibleForTesting
  bool allowReassignment = false;

  /// Registers a Singleton of type [T], that will be lazily created once by
  /// [singletonFactory], when first requested by [get].
  ///
  /// When registering a type, the [singletonFactory] will be provided with an instance of
  /// [get], this allows you to easily retrieve async dependencies that your factory may
  /// need to register the new type. This can be seen in the examples below:
  ///
  /// ```dart
  /// class Orange {
  ///   Orange(Water water, Soil soil);
  ///   ...
  /// }
  ///
  /// Future<Soil> slowAsyncCreateSoil() async {...}
  ///
  /// locator.registerSingleton((get) async => Orange(await get(), await get()));
  /// locator.registerSingleton((_) => Water());
  /// locator.registerSingleton((_) => slowAsyncCreateSoil());
  /// ```
  /// {@template register}
  /// Only one instance of type [T] can be registered at a given time, unless keys are
  /// being used (more on this later).
  ///
  /// If you need to reassign an instance, try to [unregister] it first. If you are
  /// running tests and needs constant reassignments, consider enabling
  /// [allowReassignment]. This option is not allowed by default, since most of the times
  /// reassignments are unintentional and a source of hard to track bugs.
  ///
  /// If you need to register multiple factories for the same type, you can use
  /// [withKey]. Keys are optional but must be unique.
  /// If a type is registered with a key, then multiple factories for the same
  /// type [T] can be used, and the key is what will make them unique.
  ///
  /// If [allowReassignment] is `true` and there are pending async initializations for
  /// this type or key, the initialization will be aborted with an
  /// [ServiceLocatorRegistrationOverrideException].
  ///
  /// Throws [ServiceLocatorTypeAlreadyRegisteredError] if the type or key is already
  /// registered and [allowReassignment] is `false`.
  /// {@endtemplate}
  void registerSingleton<T>(Factory<T> singletonFactory, {String? withKey}) {
    _register(singletonFactory, isSingleton: true, withKey: withKey);
  }

  /// Registers a [factory] that lazily creates new instances of type [T], when requested
  /// by [get].
  ///
  ///  When registering a type, the [factory] will be provided with an instance of [get],
  ///  this allows you to easily retrieve async dependencies that your factory may need to
  ///  register the new type. This can be seen in the examples below:
  ///
  ///  ```dart
  ///  class Orange {
  ///   Orange(Water water, Soil soil);
  ///    ...
  ///  }
  ///
  ///  Future<Soil> slowAsyncCreateSoil() async {...}
  ///
  ///  locator.registerFactory((get) async => Orange(await get(), await get()));
  ///  locator.registerFactory((_) => Water());
  ///  locator.registerFactory((_) => slowAsyncCreateSoil());
  ///  ```
  ///
  /// {@macro register}
  void registerFactory<T>(Factory<T> factory, {String? withKey}) {
    _register(factory, isSingleton: false, withKey: withKey);
  }

  void _register<T>(Factory<T> factory, {required bool isSingleton, String? withKey}) {
    if (!allowReassignment && servicesMap.containsKey((T, withKey))) {
      throw ServiceLocatorTypeAlreadyRegisteredError(T, withKey);
    }

    if (withKey != null) {
      if (keys.contains(withKey)) {
        throw ServiceLocatorKeyAlreadyRegisteredError(withKey);
      }

      keys.add(withKey);
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

  /// Unregisters a given type [T] with an optional [key].
  void unregister<T>({String? key}) {
    final removedEntry = servicesMap.remove((T, key));

    // If there were any pending initializations for this type or key, we abort
    // it with an exception.
    _abortPendingInitializationsFor(T, key);

    if (removedEntry == null) {
      throw ServiceLocatorUnregisterTypeNotRegisteredError(T, key);
    }

    keys.remove(key);
  }

  /// Unregisters a specific instance. If this same instance was registered multiple
  /// times, with different keys, then all of them will be unregistered.
  ///
  /// If you have registered a large quantity of items, this might not have good
  /// performance, as it will do a linear search for that instance.
  void unregisterInstance(Object? instance) {
    final entriesToRemove = servicesMap.entries.where((mapEntry) {
      return identical(mapEntry.value.instance, instance);
    });

    if (entriesToRemove.isEmpty) {
      throw ServiceLocatorUnregisterTypeNotRegisteredError(instance.runtimeType, null);
    }

    for (final entry in entriesToRemove) {
      servicesMap.remove(entry.key);
      final stringKey = entry.key.$2;
      if (stringKey != null) {
        keys.remove(stringKey);
      }

      // If there were any pending initializations for this type or key, we abort
      // it with an exception.
      _abortPendingInitializationsFor(entry.key.$1, entry.key.$2);
    }
  }

  /// Returns a previously registered instance of a given type, with an optional key. The
  /// instance being returned will be a singleton if it was registered to be a singleton,
  /// or it will be a new instance, if it was registered to be created with a factory.
  ///
  /// The method returns a [Future] because it will always try to satisfy a dependency
  /// chain, where the current type being requested, might depend on other types that are
  /// still initializing in async factories. This allows you to register types in any
  /// given order, and the [AutoServiceLocator] will take care of the initialization order
  /// for you.
  ///
  /// Throws [ServiceLocatorTypeOrKeyNotFoundError] if the type or key were not found.
  /// Throws [ServiceLocatorCircularDependencyError] if a circular dependency was detected.
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
      final chain = [...resolutionStack, (T, withKey)];
      throw ServiceLocatorCircularDependencyError(chain, withKey);
    }

    // Wait for this instance, as it is already being initialized elsewhere
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

  /// Waits for all current pending initializations to complete.
  ///
  /// This might be useful if you only want to proceed in case you are sure all your
  /// dependencies have been initialized and your application doesn't want to wait for
  /// them when retrieving instances in later stages.
  ///
  /// Throws if any pending initialisation fails.
  Future<void> waitPendingInitializations() async {
    await Future.wait(pendingInitializations.entries.map((entry) => entry.value.future));
  }

  /// Resets the locator's internal caches. This should only be used for testing purposes.
  @visibleForTesting
  void reset() {
    servicesMap.clear();
    pendingInitializations.clear();
    resolutionStack.clear();
    keys.clear();
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
    return '${key != null ? 'The Key $key with ' : ''}Type $type is already registered. Unregister it before trying to register this type again.';
  }
}

class ServiceLocatorKeyAlreadyRegisteredError extends Error {
  ServiceLocatorKeyAlreadyRegisteredError(this.key);

  final String? key;

  @override
  String toString() {
    return 'The Key $key is already registered. Unregister it before trying to register it again.';
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

class ServiceLocatorUnregisterKeyNotRegisteredError implements Exception {
  ServiceLocatorUnregisterKeyNotRegisteredError(this.key);

  final String key;

  @override
  String toString() {
    return 'The Key $key was not registered. Unregister expects the key to be already registered. Unregistering a key that was not already registered is likely a bug.';
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
