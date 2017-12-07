# wamp_client

A library for Dart [WAMP] client.

Changes with original: can be used only for web applications (for example with angular)
TODOs
* [x] Auto reconnect configuration
* [ ] Auto subscribe and register after a lost connection (in progress)
* [ ] Support Authentication (in progress)
* [ ] Support MsgPack (in progress)


## Usage

A simple usage example:

    import 'package:wamp_client/wamp_client.dart';

    main() async {
      var wampClient = new WampClient(
        "myrealm",
        autoReconnect: true,
        subProtocol: "wamp.2.msgpack",
        serializer: new MsgPackSerializer());

      await wamp.connect('ws://localhost:8080/ws');
    }

[WAMP]: http://wamp-proto.org
