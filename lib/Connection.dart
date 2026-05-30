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

   // Backoff exponentiel pour les tentatives de reconnexion automatique.
  //
  // Quand on perd la connexion (onDone, error de handshake, etc.), on ne
  // retente pas immédiatement — on attend un délai qui double à chaque échec
  // pour ne pas marteler le serveur si c'est lui qui est down :
  //   attempt 1 → 2s, attempt 2 → 4s, attempt 3 → 8s, attempt 4 → 16s,
  //   attempt 5 → 32s, puis plafonné à 60s.
  //
  // Le compteur _reconnectAttempts est remis à 0 quand :
  //   - une connexion réussit (cf. _resetReconnectBackoff dans _handleMessage)
  //   - disconnect() est appelé explicitement
  static const int _baseReconnectSeconds = 2;
  static const int _maxReconnectSeconds = 60;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

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

    try {
      webSocketChannel = IOWebSocketChannel.connect(
        domain + '/app/$apiKey',
        pingInterval: options.pingInterval,
      );
    } catch (e) {
      Pusher.log("Connect failed: $e");
      _onConnectionLost();
      return;
    }

    // Catch les erreurs async du handshake WebSocket sous-jacent
    // (ex: SocketException quand le réseau est injoignable). Sans ça,
    // l'erreur s'échappe vers la root zone et reste non gérée → spam.
    webSocketChannel!.ready.catchError((Object error) {
      Pusher.log("Connect handshake failed: $error");
      _onConnectionLost();
    });

    webSocketChannel!.stream.listen(_handleMessage, onDone: () {
      try {
        this.webSocketChannel!.sink.close();
      } catch (_) {}
      _onConnectionLost();
    }, onError: (error) {
      Pusher.log("error : $error");
    });
  }

  void _onConnectionLost() {
    if (state == 'disconnected') return;
    state = 'disconnected';
    super.broadcast('disconnected');
    Pusher.log("$state !");
    if (_autoReconnection) _scheduleReconnect();
  }

  // Programme la prochaine tentative de reconnexion. On annule un éventuel
  // timer en attente (cas où plusieurs erreurs successives déclenchent
  // _onConnectionLost) avant d'en planifier un nouveau.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _computeBackoffDelay();
    Pusher.log(
        "Reconnecting in ${delay.inSeconds}s (attempt ${_reconnectAttempts + 1})");
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _connect();
    });
  }

  // Calcule le délai d'attente : 2 << attempts secondes, plafonné à 60s.
  // Le clamp sur shift à 5 évite que le bit-shift dépasse la capacité int.
  Duration _computeBackoffDelay() {
    final shift = _reconnectAttempts.clamp(0, 5);
    final seconds = (_baseReconnectSeconds << shift)
        .clamp(_baseReconnectSeconds, _maxReconnectSeconds);
    return Duration(seconds: seconds);
  }

  // Reset complet du backoff : appelé quand on a une connexion réussie
  // (pour repartir de 2s la prochaine fois) ou quand on disconnect
  // explicitement (pour ne pas relancer une tentative après).
  void _resetReconnectBackoff() {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
        _resetReconnectBackoff();
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
    _resetReconnectBackoff();
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
