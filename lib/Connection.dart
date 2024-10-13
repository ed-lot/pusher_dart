import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pusher_dart/Channel.dart';
import 'package:pusher_dart/EventEmitter.dart';
import 'package:pusher_dart/PresenceChannel.dart';
import 'package:pusher_dart/Pusher.dart';
import 'package:pusher_dart/PusherOptions.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The main connection class for pusher
/// It holds the state, reconnects if necessary, and forwards method calls
class Connection with EventEmitter {
  /// @see https://pusher.com/docs/channels/using_channels/connection#available-states
  String state = 'initialized';

  /// Socket ID provided by pusher
  String? socketId;

  /// Get the API key from pusher dashboard.
  String apiKey;
  PusherOptions options;
  IOWebSocketChannel? webSocketChannel;
  final Map<String, Channel> channels = {};
  bool _autoReconnection = true;

  /// Default constructor
  Connection({required this.apiKey, required this.options}) {
    if (options.autoConnect) _connect();
  }

  _connect() {
    if (state == "connecting" || state == "connected") {
      return;
    }
    state = 'connecting';
    Pusher.log("$state ...");
    super.broadcast('connecting');
    String protocol = options.encrypted ? 'wss://' : 'ws://';
    String host = options.host;
    if (host.startsWith("http://")) host = host.substring(7);
    if (host.startsWith("https://")) host = host.substring(8);
    String domain = protocol + host;
    domain = domain + ":" + (options.encrypted ? "443" : "80");
    Pusher.log('Connecting to ' + domain);
    webSocketChannel = IOWebSocketChannel.connect(domain + '/app/$apiKey', pingInterval: options.pingInterval);
    webSocketChannel!.stream.listen(_handleMessage, onDone: () {
      this.webSocketChannel!.sink.close();
      this.state = 'disconnected';
      super.broadcast('disconnected');
      if (Pusher.log != null) Pusher.log("$state !");
      if (this._autoReconnection) this._connect();
    }, onError: (error) {
      if (Pusher.log != null) Pusher.log("error : $error");
    });
  }

  /// Authenticate a specific channel
  Future<Map<String, dynamic>> authenticate(String channelName) async {
    if (socketId == null) throw WebSocketChannelException('Pusher has not yet established connection');
    String host = options.host;
    late String sheme;
    if (host.startsWith("http://")) {
      sheme = "http";
      host = host.substring(7);
    } else if (host.startsWith("https://")) {
      sheme = "https";
      host = host.substring(8);
    }
    final response = await http.post(
      Uri(
        scheme: sheme,
        host: host,
        port: options.port,
        path: options.authEndpoint,
      ),
      headers: options.auth.headers,
      body: jsonEncode({'channel_name': channelName, 'socket_id': socketId}),
    );
    if (response.statusCode == 200) {
      try {
        Map<String, dynamic> result = jsonDecode(response.body);
        return result;
      } catch (e) {
        throw e;
      }
    }
    throw response;
  }

  _handleMessage(dynamic message) {
    final json = Map<String, dynamic>.from(jsonDecode(message as String));
    final String eventName = json['event'] as String;
    Pusher.log("eventName : $eventName - $json");
    Map<String, dynamic>? data = json['data'] is String ? jsonDecode(json['data'] as String) : json["data"];
    super.broadcast(eventName, data);
    switch (eventName) {
      case 'pusher:connection_established':
        socketId = data!['socket_id'];
        state = 'connected';
        Pusher.log("$state !");
        super.broadcast('connected', data);
        _subscribeAll();
        break;
      case 'pusher:error':
        super.broadcast('error', data);
        _handlePusherError(data!);
        break;
      default:
        final channel = channels[json['channel']];
        if (channel != null) {
          channel.handleChannelMessage(json);
        }
    }
  }

  /// Connect from pusher
  connect() {
    if (Pusher.log != null) Pusher.log("Connect called");
    this._autoReconnection = true;
    this._connect();
  }

  bool isConnected() {
    return state == 'connected';
  }

  /// Disconnect from pusher
  Future disconnect() async {
    Pusher.log("Disconnect called");
    this._autoReconnection = false;
    return webSocketChannel?.sink.close();
  }

  /// Subscribe to channel using channel name
  Channel subscribe(String channelName, [String? data]) {
    Channel channel;
    if (channelName.startsWith("presence-")) {
      channel = PresenceChannel(channelName, this, data);
    } else {
      channel = Channel(channelName, this, data);
    }
    channels[channelName] = channel;
    if (state == 'connected') {
      channel.connect();
    }
    return channel;
  }

  _subscribeAll() {
    channels.forEach((channelName, channel) {
      channel.connect();
    });
  }

  /// Unsubscribe a channel using channel name
  /// @see https://pusher.com/docs/channels/getting_started/javascript#subscribe-to-a-channel
  void unsubscribe(String channelName) {
    channels.remove(channelName);
    webSocketChannel?.sink.add(jsonEncode({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channelName}
    }));
  }

  void _handlePusherError(Map<String, dynamic> json) {
    final int errorCode = json['code'] == null ? 1 : json['code'] as int;
    if (errorCode >= 4200) {
      _connect();
    } else if (errorCode > 4100) {
      Future.delayed(Duration(seconds: 2), _connect);
    }
  }
}
