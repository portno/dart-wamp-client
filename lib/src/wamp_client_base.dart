part of wamp_client;

/// WAMP Client.
///
///     var wamp = new WampClient('realm1')
///       ..onConnect.listen((c) {
///         // setup code here...
///       });
///
///     await wamp.connect('ws://localhost:8080/ws');
///
///
/// * [publish] / [subscribe] for PubSub.
/// * [register] / [call] for RPC.
///
class WampClient {
  /// realm.
  final String realm;
  Random _random;
  int _timeout = 0;
  Map<int, StreamController<dynamic>> _inflights;
  Map<int, _Subscription> _subscriptions;
  Map<int, WampProcedure> _registrations;
  StreamController<int> _onConnectController =
      new StreamController<int>.broadcast();

  WebSocket _ws;
  Serializer _serializer;
  var _sessionState = #closed;
  var _sessionId = 0;
  var _sessionDetails = const <String, dynamic>{};
  String _subProtocol;
  bool _autoReconnect = false;
  List<String> _authMethods = ["ticket"];
  String _authid;
  String _role;
  String _ticket;
  String _authMethod;
  bool _shouldReconnect = true;

  /// create WAMP client with [realm].
  WampClient(this.realm,
      {bool autoReconnect: true,
      String authMethod: null,
      String role = null,
      String authid = null,
      Serializer serializer = null,
      String subProtocol = "wamp.2.json",
      int defaultRpcTimeout: 5000}) {
    _random = new Random.secure();
    _inflights = <int, StreamController<dynamic>>{};
    _subscriptions = {};
    _registrations = {};
    _serializer = serializer;
    if (_serializer == null) _serializer = new JsonSerializer();
    _autoReconnect = autoReconnect;
    _authMethod = authMethod;
    _role = role;
    _authid = authid;
    _subProtocol = subProtocol;
  }

  /// default client roles.
  static const Map<String, dynamic> defaultClientRoles =
      const <String, dynamic>{
    'publisher': const <String, dynamic>{},
    'subscriber': const <String, dynamic>{},
  };

  static const _keyAcknowledge = 'acknowledge';

  /// [publish] should await acknowledge from server.
  static const Map<String, dynamic> optShouldAcknowledge =
      const <String, dynamic>{_keyAcknowledge: true};

  /// [subscribe] ([register]) should prefix match on topic (url).
  static const Map<String, dynamic> optPrefixMatching = const <String, dynamic>{
    'match': 'prefix'
  };

  /// [subscribe] ([register]) should wildcard match on topic (url).
  static const Map<String, dynamic> optWildcardMatching =
      const <String, dynamic>{'match': 'wildcard'};

  /// on [connect] handler.
  ///
  ///     var wamp = new WampClient('realm1')
  ///       ..onConnect.listen((args){
  ///             //do stuff
  ///       });
  ///
  ///     await wamp.connect('ws://localhost:8080/ws');
  ///
  Stream get onConnect => _onConnectController.stream;

  /// connect to WAMP server at [url].
  ///
  ///     await wamp.connect('wss://example.com/ws');
  Future connect(String url) async {
    await _initializeWebsocket(url);
  }

  void _initializeWebsocket(String url) {
    _ws = new WebSocket(url, [_subProtocol]);
    _serializer.webSocket = _ws;
    _ws.onClose.listen((args) async {
      _sessionState = #closed;
      if (_closed || !_autoReconnect || !_shouldReconnect) return;
      await new Future<Null>.delayed(
          new Duration(seconds: 3 + new Random().nextInt(5)));
      await _initializeWebsocket(url);
    });

    _ws.onOpen.listen((args) async {
      _hello();
      try {
        await for (final msg in _serializer.read()) {
          _handle(msg);
        }
        print('disconnect');
      } catch (e) {
        print(e);
      }
    });
  }

  void _handle(List<dynamic> msg) {
    switch (msg[0] as int) {
      case WampCodes.hello:
        if (_sessionState == #establishing) {
          _sessionState = #closed;
        } else if (_sessionState == #established) {
          _sessionState = #failed;
        } else if (_sessionState == #shutting_down) {
          // ignore.
        } else {
          throw new Exception('on: $_sessionState, msg: $msg');
        }
        break;

      case WampCodes.welcome:
        if (_sessionState == #establishing) {
          _sessionState = #established;
          _sessionId = msg[1] as int;
          _sessionDetails = msg[2] as Map<String, dynamic>;
          _onConnectController.add(null);
        } else if (_sessionState == #shutting_down) {
          // ignore.
        } else {
          throw new Exception('on: $_sessionState, msg: $msg');
        }
        break;

      case WampCodes.abort:
        if (_sessionState == #shutting_down) {
          // ignore.
        } else if (_sessionState == #establishing) {
          _sessionState = #closed;
          print('aborted $msg');
        }
        break;

      case WampCodes.goodbye:
        if (_sessionState == #shutting_down) {
          _sessionState = #closed;
          print('closed both!');
        } else if (_sessionState == #established) {
          _sessionState = #closing;
          goodbye();
        } else if (_sessionState == #establishing) {
          _sessionState = #failed;
        } else {
          throw new Exception('on: $_sessionState, msg: $msg');
        }
        break;

      case WampCodes.subscribed:
        final code = msg[1] as int;
        final subid = msg[2] as int;
        final cntl = _inflights[code];
        if (cntl != null) {
          _inflights.remove(code);
          final sub = new _Subscription();
          sub.cntl.onCancel = () {
            _unsubscribe(subid);
          };
          _subscriptions[subid] = sub;
          cntl.add(sub.cntl.stream);
          cntl.close();
        } else {
          print('unknown subscribed: $msg');
        }
        break;

      case WampCodes.unsubscribed:
        final code = msg[1] as int;
        final cntl = _inflights[code];
        if (cntl != null) {
          _inflights.remove(code);
          cntl.add(null);
          cntl.close();
        } else {
          print('unknown unsubscribed: $msg');
        }
        break;

      case WampCodes.published:
        final code = msg[1] as int;
        final cntl = _inflights[code];
        if (cntl != null) {
          _inflights.remove(code);
          cntl.add(null);
          cntl.close();
        } else {
          print('unknown published: $msg');
        }
        break;

      case WampCodes.event:
        final subid = msg[1] as int;
        final pubid = msg[2] as int;
        final details = msg[3] as Map<String, dynamic>;
        print(msg);
        final event = new WampEvent(
            pubid,
            details,
            new WampArgs(
                4 < msg.length
                    ? (msg[4] as List<dynamic>)
                    : (const <dynamic>[]),
                5 < msg.length
                    ? (msg[5] as Map<String, dynamic>)
                    : (const <String, dynamic>{})));
        final sub = _subscriptions[subid];
        if (sub != null) {
          sub.cntl.add(event);
        }
        break;

      case WampCodes.registered:
        final code = msg[1] as int;
        final regid = msg[2] as int;
        final cntl = _inflights[code];
        if (cntl != null) {
          _inflights.remove(code);
          cntl.add(regid);
          cntl.close();
        } else {
          print('unknown registered: $msg');
        }
        break;

      case WampCodes.unregistered:
        final code = msg[1] as int;
        final cntl = _inflights[code];
        if (cntl != null) {
          _inflights.remove(code);
          cntl.add(null);
          cntl.close();
        } else {
          print('unknown registered: $msg');
        }
        break;

      case WampCodes.invocation:
        _invocation(msg);
        break;

      case WampCodes.result:
        final code = msg[1] as int;
        final cntl = _inflights[code];
        if (cntl != null) {
          _inflights.remove(code);
          final args = new WampArgs._toWampArgs(msg, 3);
          cntl.add(args);
          cntl.close();
        } else {
          print('unknown result: $msg');
        }
        break;

      case WampCodes.error:
        final cmd = msg[1] as int;
        switch (cmd) {
          case WampCodes.call:
            final code = msg[2] as int;
            final cntl = _inflights[code];
            if (cntl != null) {
              _inflights.remove(code);
              final args = new WampArgs._toWampArgs(msg, 5);
              cntl.addError(args);
              cntl.close();
            } else {
              print('unknown invocation error: $msg');
            }
            break;

          case WampCodes.register:
            final code = msg[2] as int;
            final cntl = _inflights[code];
            if (cntl != null) {
              _inflights.remove(code);
              final args = msg[4] as String;
              cntl.addError(new WampArgs(<dynamic>[args]));
              cntl.close();
            } else {
              print('unknown register error: $msg');
            }
            break;

          case WampCodes.unregister:
            final code = msg[2] as int;
            final cntl = _inflights[code];
            if (cntl != null) {
              _inflights.remove(code);
              final args = msg[4] as String;
              cntl.addError(new WampArgs(<dynamic>[args]));
              cntl.close();
            } else {
              print('unknown unregister error: $msg');
            }
            break;

          default:
            print('unimplemented error: $msg');
        }
        break;

      case WampCodes.publish:
      case WampCodes.subscribe:
      case WampCodes.unsubscribe:
      case WampCodes.call:
      case WampCodes.register:
      case WampCodes.unregister:
      case WampCodes.yield:
        if (_sessionState == #shutting_down) {
          // ignore.
        } else if (_sessionState == #establishing) {
          _sessionState = #failed;
        } else {
          print('unimplemented: $msg');
        }
        break;

      case WampCodes.challenge:
        print("challenge");
        send([
          WampCodes.authenticate,
          this._ticket,
          {"extra": ""}
        ]);
        break;
      case WampCodes.authenticate:
        print("authenticate");
        break;
      case WampCodes.cancel:
      case WampCodes.interrupt:

      default:
        print('unexpected: $msg');
        break;
    }
  }

  void _invocation(List<dynamic> msg) {
    final code = msg[1] as int;
    final regid = msg[2] as int;
    final args = new WampArgs._toWampArgs(msg);
    final proc = _registrations[regid];
    if (proc != null) {
      try {
        final result = proc(args);
        send([
          WampCodes.yield,
          code,
          <String, dynamic>{},
          result.args,
          result.params
        ]);
      } on WampArgs catch (ex) {
        print('ex=$ex');
        send([
          WampCodes.error,
          WampCodes.invocation,
          code,
          <String, dynamic>{},
          'wamp.error',
          ex.args,
          ex.params
        ]);
      } catch (ex) {
        send([
          WampCodes.error,
          WampCodes.invocation,
          code,
          <String, dynamic>{},
          'error'
        ]);
      }
    } else {
      print('unknown invocation: $msg');
    }
  }

  void _hello() {
    if (_sessionState != #closed) {
      throw new Exception('cant send Hello after session established.');
    }
    Map<String, Object> payload = {
      'roles': defaultClientRoles,
    };
    if (_ticket != null) {
      payload["authrole"] = _role;
      payload["authid"] = _authid;
      payload["authmethods"] = _authMethods;
    }
    var message = [WampCodes.hello, realm, payload];
    if (_authMethods != null) {
      //message[2]["user"]= _role;
    }
    send(message);
    _sessionState = #establishing;
  }

  bool _closed = false;
  void goodbye([Map<String, dynamic> details = const <String, dynamic>{}]) {
    _closed = true;
    if (_sessionState != #established && _sessionState != #closing) {
      throw new Exception('cant send Goodbye before session established.');
    }

    void send_goodbye(String reason, Symbol next) {
      send([
        WampCodes.goodbye,
        details,
        reason,
      ]);
      _sessionState = next;
    }

    if (_sessionState == #established) {
      send_goodbye('wamp.error.close_realm', #shutting_down);
    } else {
      send_goodbye('wamp.error.goodbye_and_out', #closed);
    }
  }

  void _abort([Map<String, dynamic> details = const <String, dynamic>{}]) {
    if (_sessionState != #establishing) {
      throw new Exception('cant send Goodbye before session established.');
    }

    send([
      WampCodes.abort,
      details,
      'abort',
    ]);
    _shouldReconnect = false;
    _sessionState = #closed;
  }

  /// register RPC at [uri] with [proc].
  ///
  ///     wamp.register('your.rpc.name', (arg) {
  ///       print('got $arg');
  ///       return arg;
  ///     });
  Future<WampRegistration> register(String uri, WampProcedure proc,
      [Map options = const <String, dynamic>{}]) {
    final cntl = new StreamController<int>();
    _goFlight(cntl, (code) => [WampCodes.register, code, options, uri]);
    return cntl.stream.last.then((regid) {
      _registrations[regid] = proc;
      return new WampRegistration(regid);
    });
  }

  /// unregister RPC [id].
  ///
  ///     wamp.unregister(your_rpc_id);
  Future<Null> unregister(WampRegistration reg) {
    final cntl = new StreamController<int>();
    _goFlight(cntl, (code) => [WampCodes.unregister, code, reg.id]);
    return cntl.stream.last.then((dynamic _) {
      _registrations.remove(reg.id);
      return null;
    });
  }

  /// call RPC with [args] and [params].
  ///
  ///     wamp.call('your.rpc.name', ['myarg', 3], {'hello': 'world'})
  ///       .then((result) {
  ///         print('got result=$result');
  ///       })
  ///       .catchError((error) {
  ///         print('call error=$error');
  ///       });
  Future<WampArgs> call(String uri,
      [List<dynamic> args = const <dynamic>[],
      Map<String, dynamic> params = const <String, dynamic>{},
      Map options = const <String, dynamic>{}]) async {
    final cntl = new StreamController<WampArgs>();
    if (_timeout > 0) {
      new Future<Null>.delayed(new Duration(milliseconds: _timeout))
          .then((args) {
        if (cntl.isClosed) return;
        cntl.addError(new WampArgs(<dynamic>["RPC timed out"]));
        cntl.close();
        _ws.close();
      });
    }
    if (_sessionState != #established) {
      await onConnect.first;
    }
    _goFlight(
        cntl, (code) => [WampCodes.call, code, options, uri, args, params]);

    return cntl.stream.last;
  }

  /// subscribe [topic].
  ///
  ///     wamp.subscribe('topic').then((stream) async {
  ///       await for (var event in stream) {
  ///         print('event=$event');
  ///       }
  ///     });
  Future<Stream<WampEvent>> subscribe(String topic,
      [Map options = const <String, dynamic>{}]) async {
    final cntl = new StreamController<Stream<WampEvent>>();
    if (_sessionState != #established) {
      await onConnect.first;
    }
    _goFlight(cntl, (code) => [WampCodes.subscribe, code, options, topic]);
    return cntl.stream.last;
  }

  Future _unsubscribe(int subid) async {
    _subscriptions.remove(subid);

    final cntl = new StreamController<Null>();
    if (_sessionState != #established) {
      await onConnect.first;
    }
    _goFlight(cntl, (code) => [WampCodes.unsubscribe, code, subid]);
    return cntl.stream.last;
  }

  /// publish [topic].
  ///
  ///     wamp.publish('topic');
  Future<Null> publish(
    String topic, [
    List<dynamic> args = const <dynamic>[],
    Map<String, dynamic> params = const <String, dynamic>{},
    Map options = const <String, dynamic>{},
  ]) async {
    final cntl = new StreamController<Null>();
    if (_sessionState != #established) {
      await onConnect.first;
    }
    final code = _goFlight(cntl,
        (code) => [WampCodes.publish, code, options, topic, args, params]);

    final dynamic acknowledge = options[_keyAcknowledge];
    if (acknowledge is bool && acknowledge) {
      return cntl.stream.last;
    } else {
      _inflights.remove(code);
      return new Future<Null>.value(null);
    }
  }

  int _flightCode(StreamController<dynamic> val) {
    int code = 0;
    do {
      code = _random.nextInt(1000000000);
    } while (_inflights.containsKey(code));

    _inflights[code] = val;
    return code;
  }

  int _goFlight(StreamController<dynamic> cntl, dynamic data(int code)) {
    final code = _flightCode(cntl);
    try {
      send(data(code));
      return code;
    } catch (_) {
      _inflights.remove(code);
      rethrow;
    }
  }

  void send(dynamic obj) {
    _serializer.write(obj);
  }
}
