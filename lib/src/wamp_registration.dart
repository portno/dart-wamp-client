part of wamp_client;

/// WAMP RPC registration.
class WampRegistration {
  final int id;
  const WampRegistration(this.id);

  String toString() => 'WampRegistration(id: $id)';
}