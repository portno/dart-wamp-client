/// WAMP protocol client.
///
/// [WampClient] is main entrypoint.
library wamp_client;

import 'dart:html';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:msgpack2/msgpack2.dart';

part 'src/serializers/serializer.dart';
part 'src/serializers/json_serializer.dart';
part 'src/serializers/msgpack_serializer.dart';
part 'src/wamp_args.dart';
part 'src/subscription.dart';
part 'src/wamp_codes.dart';
part 'src/wamp_event.dart';
part 'src/wamp_registration.dart';
part 'src/wamp_client_base.dart';

//export 'src/wamp_client_base.dart';

// TODO: Export any libraries intended for clients of this package.
