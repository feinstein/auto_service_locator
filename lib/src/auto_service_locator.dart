import 'dart:async';

import 'package:meta/meta.dart';

class AutoServiceLocator {
  // TODO: Test null being registered
  @visibleForTesting
  Map<Type, ServiceEntry> servicesMap = {};

  @visibleForTesting
  Map<Type, Completer> pendingInitialisations = {};

  @visibleForTesting
  final List<Type> resolutionStack = [];

  void registerSingleton<T>(Factory<T> singletonFactory) {
    _register(singletonFactory, isSingleton: true);
  }

  void registerFactory<T>(Factory<T> factory) {
    _register(factory, isSingleton: false);
  }

  void _register<T>(Factory<T> factory, {required bool isSingleton}) {
    if (servicesMap.containsKey(T)) {
      throw ServiceLocatorTypeAlreadyRegisteredError(T);
    }

    servicesMap[T] = ServiceEntry(factory: factory, isSingleton: isSingleton);
  }

  void unregister<T>() => servicesMap.remove(T);

  Future<T> get<T>() async {
    final service = servicesMap[T];
    if (service == null) {
      throw ServiceLocatorTypeNotFoundError(T);
    }

    if (service.instance != null) {
      // Should only happen if it is a Singleton, so we don't have to check it
      return service.instance as T;
    }

    // Check for circular dependency (same call chain)
    if (resolutionStack.contains(T)) {
      final chain = [...resolutionStack, T];
      throw ServiceLocatorCircularDependencyError(chain);
    }

    // Wait for this instance, as it is already being initialised elsewhere
    final pendingInitialisation = pendingInitialisations[T];
    if (pendingInitialisation != null) {
      return await pendingInitialisation.future as T;
    }

    resolutionStack.add(T);
    final completer = Completer<T>();
    pendingInitialisations[T] = completer;

    try {
      final factoryResult = service.factory(get);
      final serviceInstance = factoryResult is Future<T>
          ? await factoryResult
          : factoryResult as T;

      if (service.isSingleton) {
        // Add the missing singleton instance cache
        servicesMap[T] = ServiceEntry(
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
      pendingInitialisations.remove(T);
    }
  }

  @visibleForTesting
  void reset() {
    servicesMap.clear();
    pendingInitialisations.clear();
    resolutionStack.clear();
  }
}

typedef Factory<TRegister> =
    FutureOr<TRegister> Function(FutureOr<TWanted> Function<TWanted>() get);

@visibleForTesting
class ServiceEntry<T> {
  ServiceEntry({
    required this.factory,
    required this.isSingleton,
    this.instance,
  });

  final Factory<T> factory;
  final bool isSingleton;
  final T? instance;
}

class ServiceLocatorTypeAlreadyRegisteredError extends Error {
  ServiceLocatorTypeAlreadyRegisteredError(this.type);

  final Type type;

  @override
  String toString() {
    return 'Type $type is already registered. Unregister it before you try to register this type again.';
  }
}

class ServiceLocatorTypeNotFoundError extends Error {
  ServiceLocatorTypeNotFoundError(this.type);

  final Type type;

  @override
  String toString() {
    return 'The type $type was not registered. You need to register the type before you can use it.';
  }
}

class ServiceLocatorCircularDependencyError extends Error {
  ServiceLocatorCircularDependencyError(this.chain);

  final List<Type> chain;

  @override
  String toString() {
    return 'Circular dependency detected: ${chain.join(' -> ')}';
  }
}
