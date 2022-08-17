# Pusher
Unofficial pusher client for dart.

## Usage
Using this package is similar to how one would use PusherJS.

I use it with my [Echo](https://github.com/ed-lot/echo) project with [laravel-websockets](https://github.com/beyondcode/laravel-websockets) server.

### Initialize
```dart
  Pusher pusher = Pusher(
      "YOUR_PUSHER_APP_KEY",
      PusherOptions(
          host: "YOUR_PUSHER_DOMAIN",
          port: "YOUR_PUSHER_PORT",
          authEndpoint: "YOUR_PUSHER_AUTH_ENDPOINT",
          cluster: "YOUR_PUSHER_CLUSTER",
          encrypted: false,
          auth: PusherAuth(headers: {
            "Content-Type": "application/json",
            "authorization": "Bearer token",
          }),
          autoConnect: true,
          pingInterval: Duration(seconds: 5)),
    );
```
### Subscribe to a channel
```dart
final channel = pusher.subscribe('my-channel');
```

### Bind to events
```dart
eventHandler(Object data) async {
    final jsonData = Map<String, dynamic>.from(jsonDecode(data));
}

channel.bind('my-event', eventHandler);
```

### Trigger event on a channel
You can pass any data that can be converted to JSON using `jsonEncode(data);`.  
```dart
Map<String, String> jsonData = {};
channel.trigger('my-event', jsonData);
```

### Close the connection
```dart
pusher.disconnect();
```