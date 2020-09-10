import 'package:meta/meta.dart';

/// Class to hold headers to send to authentication endpoint
/// Ex. `PusherAuth(headers: {'Authorization': 'Bearer $token'})`
@immutable
class PusherAuth {
  /// HTTP Headers
  /// Ex. `{'Authorization': 'Bearer $token'}`
  final Map<String, String> headers;

  /// Default constructor
  PusherAuth({this.headers});
}

/// Class to hold pusher configuration
/// Ex. `PusherOptions({authEndpoint: 'https://domain.com/auth', cluster: 'mt1', auth:  })`
@immutable
class PusherOptions {
  /// A URL string to send the authentication request to
  final String authEndpoint;
  final PusherAuth auth;

  /// for using a different host or port
  final String host;
  final int port;

  //use wss or ws
  final bool encrypted;

  /// Pusher cluster
  /// @see https://pusher.com/docs/channels/miscellaneous/clusters
  final String cluster;

  final bool autoConnect;
  final Duration pingInterval;

  /// Default constructor
  PusherOptions({this.authEndpoint, this.auth, this.cluster = 'mt1', this.host, this.port = 443, this.encrypted = true, this.autoConnect = true, this.pingInterval});
}
