import 'package:pusher_dart/Channel.dart';
import 'package:pusher_dart/Connection.dart';
import 'package:pusher_dart/EventEmitter.dart';
import 'package:pusher_dart/PusherOptions.dart';

class Pusher with EventEmitter {
  /// Log function called on all pusher actions
  static Function log = (Object message) {
    print('Pusher: $message');
  };

  Connection _connection;

  /// Default constructor
  Pusher(String apiKey, PusherOptions options) {
    _connection = Connection(apiKey, options);
  }

  /// Connect from pusher
  void connect() {
    _connection.connect();
  }

  /// Disconnect from pusher
  void disconnect() {
    _connection.disconnect();
  }

  bool isConnected() {
    return this._connection.isConnected();
  }

  Function connecting(Function callback) {
    _connection.bind("connecting", callback);
    return () {
      _connection.unbind("connecting", callback);
    };
  }

  Function connected(Function(Object data) callback) {
    _connection.bind("connected", callback);
    return () {
      _connection.unbind("connected", callback);
    };
  }

  Function disconnected(Function callback) {
    _connection.bind("disconnected", callback);
    return () {
      _connection.unbind("disconnected", callback);
    };
  }

  /// Get a channel using channel name
  Channel channel(String channelName) {
    return _connection.channels[channelName];
  }

  /// Subscribe to a channel using channel name
  Channel subscribe(String channelName, [String data]) {
    return _connection.subscribe(channelName, data);
  }

  /// Unsubscribe a channel using channel name
  void unsubscribe(String channelName) {
    _connection.unsubscribe(channelName);
  }

  String getSocketId(){
    return _connection.socketId;
  }
}