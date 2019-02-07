part of wamp_client;

/// WAMP subscription event.
class WampEvent {
  final int id;
  final Map details;
  final WampArgs args;

  const WampEvent(this.id, this.details, this.args);

  Map toJson() => new Map<String, dynamic>()
    ..['id'] = id
    ..['details'] = details
    ..['args'] = args.args
    ..['params'] = args.params;

  String toString() => jsonEncode(this);
}
