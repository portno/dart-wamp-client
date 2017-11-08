part of wamp_client;

class MsgPackSerializer extends Serializer {
  WebSocket _webSocket;
  MsgPackSerializer();

  @override
  Stream<List<dynamic>> read() async* {
    await for (final mm in _webSocket.onMessage) {
      var m = mm.data as ByteBuffer;
      yield unpack(m.asInt32List()) as List<dynamic>;
    }
  }

  @override
  void write(dynamic obj) {
    _webSocket.send(pack(obj));
  }

  @override
  set webSocket(WebSocket socket) {
    _webSocket = socket;
    _webSocket.binaryType = "arraybuffer";
  }
}
