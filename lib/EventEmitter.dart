mixin EventEmitter {
  final Map<String, Set<Function(Object? data)>> _listeners = {};

  void bind(String eventName, Function(Object? data) callback) {
    if (_listeners[eventName] == null) {
      _listeners[eventName] = Set<Function(Object? data)>();
    }
    _listeners[eventName]!.add(callback);
  }

  void unbind(String eventName, Function(Object data) callback) {
    if (_listeners[eventName] != null) {
      _listeners[eventName]!.remove(callback);
    }
  }

  void broadcast(String eventName, [Object? data]) {
    (_listeners[eventName] ?? Set()).forEach((listener) {
      listener(data);
    });
  }
}
