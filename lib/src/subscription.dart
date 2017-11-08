part of wamp_client;

class _Subscription {
  final StreamController<WampEvent> cntl;

  _Subscription() : cntl = new StreamController.broadcast();
}
