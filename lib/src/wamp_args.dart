part of wamp_client;


/// WAMP RPC arguments.
class WampArgs {
  /// Array arguments.
  final List<dynamic> args;

  /// Keyword arguments.
  final Map<String, dynamic> params;

  const WampArgs([
    this.args = const <dynamic>[],
    this.params = const <String, dynamic>{},
  ]);

  factory WampArgs._toWampArgs(List<dynamic> msg, [int idx = 4]) {
    return new WampArgs(
        idx < msg.length ? (msg[idx] as List<dynamic>) : (const <dynamic>[]),
        idx + 1 < msg.length
            ? (msg[idx + 1] as Map<String, dynamic>)
            : (const <String, dynamic>{}));
  }

  List toJson() => <dynamic>[args, params];

  String toString() => jsonEncode(this);
}


/// WAMP RPC procedure type.
typedef WampArgs WampProcedure(WampArgs args);
