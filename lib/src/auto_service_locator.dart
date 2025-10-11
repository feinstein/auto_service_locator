import 'dart:async';

import 'package:meta/meta.dart';

class AutoServiceLocator {
  AutoServiceLocator._();

  static final AutoServiceLocator instance = AutoServiceLocator._();

  // TODO: Test null being registered
  @visibleForTesting
  Map<Type, ServiceEntry> servicesMap = {};

  @visibleForTesting
  Map<Type, Completer> pendingInitialisations = {};

  @visibleForTesting
  final List<Type> resolutionStack = [];

  void registerSingleton<T>(Factory<T> singletonFactory) {
    if (servicesMap.containsKey(T)) {
      throw ServiceLocatorRegistrationError(
        'Type $T is already registered. Unregister it before you try to register this type again.',
      );
    }

    servicesMap[T] = ServiceEntry(factory: singletonFactory, isSingleton: true);
  }

  void registerFactory<T>(Factory<T> factory) {
    if (servicesMap.containsKey(T)) {
      throw ServiceLocatorRegistrationError(
        'Type $T is already registered. Unregister it before you try to register this type again.',
      );
    }

    servicesMap[T] = ServiceEntry(factory: factory, isSingleton: false);
  }

  void unregister<T>() => servicesMap.remove(T);

  Future<T> get<T>() async {
    final service = servicesMap[T];
    if (service == null) {
      throw ServiceLocatorGetterError(
        'The type $T was not registered. You need to register the type before you can use it.',
      );
    }

    if (service.instance != null) {
      // Should only happen if it is a Singleton, so we don't have to check it
      return service.instance as T;
    }

    // Check for circular dependency (same call chain)
    if (resolutionStack.contains(T)) {
      final chain = [...resolutionStack, T];
      throw ServiceLocatorGetterError('Circular dependency detected: $chain');
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
      final serviceInstance = service.factory is Future
          ? await service.factory(get)
          : service.factory(get);

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
}

typedef Factory<TRegister> =
    TRegister Function(FutureOr<TWanted> Function<TWanted>() get);

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

class ServiceLocatorRegistrationError extends Error {
  ServiceLocatorRegistrationError([this.message, this.type]);

  final String? message;
  final Type? type;

  @override
  String toString() {
    return message ??
        'Error while trying to register the type ${type != null ? '$type' : ''}';
  }
}

class ServiceLocatorGetterError extends Error {
  ServiceLocatorGetterError([this.message, this.type]);

  final String? message;
  final Type? type;

  @override
  String toString() {
    return message ??
        'Error while trying to get type ${type != null ? '$type' : ''}';
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
