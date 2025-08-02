import 'package:flutter/foundation.dart';

/// Simple service locator for dependency injection
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  final Map<Type, Object> _services = {};
  final Map<Type, Object Function()> _factories = {};

  /// Registers a singleton service
  void registerSingleton<T extends Object>(T service) {
    _services[T] = service;
  }

  /// Registers a factory for creating service instances
  void registerFactory<T extends Object>(T Function() factory) {
    _factories[T] = factory;
  }

  /// Registers a lazy singleton (created when first requested)
  void registerLazySingleton<T extends Object>(T Function() factory) {
    _factories[T] = () {
      final service = factory();
      _services[T] = service;
      _factories.remove(T);
      return service;
    };
  }

  /// Gets a service instance
  T get<T extends Object>() {
    final service = _services[T];
    if (service != null) {
      return service as T;
    }

    final factory = _factories[T];
    if (factory != null) {
      return factory() as T;
    }

    throw Exception('Service of type $T is not registered');
  }

  /// Checks if a service is registered
  bool isRegistered<T extends Object>() {
    return _services.containsKey(T) || _factories.containsKey(T);
  }

  /// Unregisters a service
  void unregister<T extends Object>() {
    _services.remove(T);
    _factories.remove(T);
  }

  /// Clears all registered services (useful for testing)
  void clear() {
    _services.clear();
    _factories.clear();
  }

  /// Gets all registered service types
  List<Type> get registeredTypes {
    final types = <Type>{};
    types.addAll(_services.keys);
    types.addAll(_factories.keys);
    return types.toList();
  }

  @visibleForTesting
  Map<Type, Object> get services => Map.unmodifiable(_services);

  @visibleForTesting
  Map<Type, Object Function()> get factories => Map.unmodifiable(_factories);
}

/// Global service locator instance
final ServiceLocator serviceLocator = ServiceLocator();

/// Extension methods for easier service access
extension ServiceLocatorExtensions on ServiceLocator {
  /// Tries to get a service, returns null if not found
  T? tryGet<T extends Object>() {
    try {
      return get<T>();
    } catch (e) {
      return null;
    }
  }
}
