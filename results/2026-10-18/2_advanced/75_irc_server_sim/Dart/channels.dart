part of 'main.dart';

class Member {
  final Client client;
  bool op, voice = false;
  Member(this.client, this.op);
  String get marker => op
      ? '@'
      : voice
      ? '+'
      : '';
}

class Ban {
  final String mask, setter;
  final int time;
  Ban(this.mask, this.setter, this.time);
}

class Channel {
  final String name;
  String topic = '', setter = '', key = '';
  final int created;
  int topicTime = 0, limit = 0, peak = 0, messages = 0;
  final List<Member> members = [];
  final List<Ban> bans = [];
  final Map<String, bool> flags = {'n': true, 't': true};
  Channel(this.name, this.created);
  Member? member(Client c) {
    for (final m in members) {
      if (m.client == c) return m;
    }
    return null;
  }

  void add(Client c) {
    members.add(Member(c, members.isEmpty));
    c.channels.add(this);
    peak = max(peak, members.length);
  }

  void remove(Client c) {
    members.removeWhere((m) => m.client == c);
    c.channels.remove(this);
  }

  String names(Client c) {
    final inside = member(c) != null;
    return [
      for (final m in members)
        if (inside || !m.client.invisible) '${m.marker}${m.client.nick}',
    ].join(' ');
  }

  bool banned(Client c) => bans.any((b) => matchMask(b.mask, c.prefix));
  bool canSpeak(Client c) {
    final m = member(c), privileged = m != null && (m.op || m.voice);
    return (m != null || flags['n'] != true) &&
        (flags['m'] != true || privileged) &&
        (privileged || !banned(c));
  }

  String mode(bool includeKey) {
    var out = '+';
    for (final flag in ['i', 'k', 'l', 'm', 'n', 't']) {
      if (flag == 'k' && key.isNotEmpty ||
          flag == 'l' && limit > 0 ||
          flag != 'k' && flag != 'l' && flags[flag] == true)
        out += flag;
    }
    if (includeKey && key.isNotEmpty) out += ' $key';
    if (limit > 0) out += ' $limit';
    return out;
  }
}

String channelNames(Client c, String separator) => [
  for (final ch in c.channels) '${ch.member(c)!.marker}${ch.name}',
].join(separator);
