part of wamp_client;

class WampCodes {
  static const int hello = 1;
  static const int welcome = 2;
  static const int abort = 3;
  static const int challenge = 4;
  static const int authenticate = 5;
  static const int goodbye = 6;
  static const int error = 8;
  static const int publish = 16;
  static const int published = 17;
  static const int subscribe = 32;
  static const int subscribed = 33;
  static const int unsubscribe = 34;
  static const int unsubscribed = 35;
  static const int event = 36;
  static const int call = 48;
  static const int cancel = 49;
  static const int result = 50;
  static const int register = 64;
  static const int registered = 65;
  static const int unregister = 66;
  static const int unregistered = 67;
  static const int invocation = 68;
  static const int interrupt = 69;
  static const int yield = 70;
}