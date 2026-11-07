part of 'main.dart';

class Client {
  final String id, host;
  String nick = '', user = '', real = '', away = '';
  final int connected;
  int signon = -1,
      lastReceived,
      lastSpeaking = 0,
      pingAt = 0,
      tokens,
      refill = -1,
      received = 0,
      sent = 0;
  bool invisible = false, registered = false, pinging = false, alive = true;
  final List<String> queue = [];
  final List<Channel> channels = [], invites = [];
  Client(this.id, this.host, this.connected, this.tokens)
    : lastReceived = connected;
  String get addressee => nick.isEmpty ? '*' : nick;
  String get prefix => '$nick!$user@$host';
  String get mode => invisible ? '+i' : '+';
  void use(int t, int bucket, int interval) {
    if (tokens == bucket) refill = t + interval;
    tokens--;
  }

  void refillTokens(int t, int bucket, int interval) {
    if (refill == t) {
      tokens++;
      refill = tokens < bucket ? t + interval : -1;
    }
  }
}
