part of wamp_client;

abstract class Serializer{
  Stream<List<dynamic>> read();
  void write(dynamic obj);
  void set webSocket(WebSocket socket);
}