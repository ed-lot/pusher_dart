import 'dart:convert';

import 'package:pusher_dart/Connection.dart';
import 'package:pusher_dart/EventEmitter.dart';

/// A channel
class Channel with EventEmitter {
  /// Channel name
  /// Ex. `private-Customer.1`
  final String name;
  String? data;
  Connection connection;

  /// Default constructor
  Channel(this.name, this.connection, [String? this.data]);

  /// @see https://pusher.com/docs/channels/getting_started/javascript#listen-for-events-on-your-channel
  bool trigger(String eventName, Object data) {
    try {
      connection.webSocketChannel?.sink.add(jsonEncode({'event': eventName, 'data': data}));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Subscribes to the channel
  /// If it is a private channel, authenticates using provided details
  Future<bool> connect() async {
    String? auth;
    String? channel_data;
    if (name.startsWith('private-')) {
      try {
        var data = await connection.authenticate(name);
        if (data.containsKey("auth")) auth = data["auth"];
        if (data.containsKey("channel_data")) channel_data = data["channel_data"];
      } catch (e) {
        print("Error: ${e.toString()}");
      }
    }
    return trigger('pusher:subscribe', {'channel': name, 'auth': auth, 'channel_data': data ?? channel_data});
  }

  handleChannelMessage(Map<String, dynamic> message) {
    this.broadcast(message['event'] as String, message['data']);
  }
}
