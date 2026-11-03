import 'dart:io';
import 'dart:math';
part 'protocol.dart';
part 'masks.dart';
part 'clients.dart';
part 'channels.dart';
part 'modes.dart';

int number(String s) => int.parse(s);

class Traffic {
  final int time;
  final String id, body;
  Traffic(this.time, this.id, this.body);
}

class Server {
  final Map<String, String> config = {};
  final List<String> motd = [], sent = [], gone = [];
  final List<Traffic> traffic = [];
  final List<Client> clients = [];
  final List<Channel> channels = [];
  final Map<String, Client> byID = {};
  int time = 0, end = 0;
  final Map<String, int> commands = {}, disconnects = {};
  final Map<int, int> numerics = {};
  int connectLines = 0,
      disconnectLines = 0,
      messageLines = 0,
      dropped = 0,
      queued = 0,
      processed = 0,
      discarded = 0,
      empty = 0,
      pings = 0,
      errors = 0,
      peakConnections = 0,
      peakConnectionsAt = 0,
      peakRegistered = 0,
      peakRegisteredAt = 0;
  int setting(String key) => number(config[key]!);
  void send(Client c, String text) {
    sent.add('$time ${c.id} $text');
    c.sent++;
  }

  void numeric(Client c, int n, String text) {
    numerics[n] = (numerics[n] ?? 0) + 1;
    send(
      c,
      ':${config['NAME']} ${n.toString().padLeft(3, '0')} ${c.addressee} $text',
    );
  }

  void errorReply(Client c, int n, [String target = '']) {
    final text = {
      401: ':No such nick/channel',
      403: ':No such channel',
      404: ':Cannot send to channel',
      405: ':You have joined too many channels',
      431: ':No nickname given',
      432: ':Erroneous nickname',
      433: ':Nickname is already in use',
      442: ':You\'re not on that channel',
      451: ':You have not registered',
      462: ':You may not reregister',
      467: ':Channel key already set',
      471: ':Cannot join channel (+l)',
      473: ':Cannot join channel (+i)',
      474: ':Cannot join channel (+b)',
      475: ':Cannot join channel (+k)',
      482: ':You\'re not channel operator',
      501: ':Unknown MODE flag',
      502: ':Cannot change mode for other users',
    }[n]!;
    numeric(c, n, target.isEmpty ? text : '$target $text');
  }

  Client? user(String nick) {
    for (final c in clients) {
      if (c.registered && fold(c.nick) == fold(nick)) return c;
    }
    return null;
  }

  Channel? channel(String name) {
    for (final ch in channels) {
      if (fold(ch.name) == fold(name)) return ch;
    }
    return null;
  }

  void members(Channel ch, Client? except, String text) {
    for (final m in ch.members) {
      if (m.client != except) send(m.client, text);
    }
  }

  void peers(Client c, String text) {
    for (final other in clients) {
      if (other != c && c.channels.any((ch) => ch.member(other) != null))
        send(other, text);
    }
  }

  void remove(Client c, Channel ch) {
    ch.remove(c);
    if (ch.members.isEmpty) {
      channels.remove(ch);
      for (final other in clients) {
        other.invites.remove(ch);
      }
    }
  }

  void disconnect(Client c, String reason, String kind) {
    if (kind != 'closed') {
      errors++;
      send(c, 'ERROR :Closing Link: ${c.addressee}[${c.host}] ($reason)');
    }
    if (c.registered) peers(c, ':${c.prefix} QUIT :$reason');
    for (final ch in List<Channel>.of(c.channels)) {
      remove(c, ch);
    }
    discarded += c.queue.length;
    c.queue.clear();
    c.alive = false;
    byID.remove(c.id);
    clients.remove(c);
    gone.add('GONE $time ${c.id} ${c.addressee} $reason');
    disconnects[kind] = (disconnects[kind] ?? 0) + 1;
  }

  void register(Client c) {
    if (c.registered || c.nick.isEmpty || c.user.isEmpty) return;
    c.registered = true;
    c.signon = time;
    c.lastSpeaking = time;
    final count = clients.where((c) => c.registered).length;
    if (count > peakRegistered) {
      peakRegistered = count;
      peakRegisteredAt = time;
    }
    final name = config['NAME']!;
    numeric(c, 1, ':Welcome to the Internet Relay Network ${c.prefix}');
    numeric(c, 2, ':Your host is $name, running version ${config['VERSION']}');
    numeric(c, 3, ':This server was created ${config['CREATED']}');
    numeric(c, 4, '$name ${config['VERSION']} i biklmnotv');
    numeric(
      c,
      5,
      'CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=${config['NICKLEN']} CHANNELLEN=${config['CHANNELLEN']} TOPICLEN=${config['TOPICLEN']} CHANLIMIT=#:${config['MAXCHANNELS']} CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server',
    );
    numeric(c, 375, ':- $name Message of the day -');
    for (final text in motd) {
      numeric(c, 372, ':- $text');
    }
    numeric(c, 376, ':End of /MOTD command.');
    if (c.invisible) send(c, ':${c.nick} MODE ${c.nick} :+i');
  }

  void names(Client c, Channel ch) {
    final names = ch.names(c);
    if (names.isNotEmpty) numeric(c, 353, '= ${ch.name} :$names');
    numeric(c, 366, '${ch.name} :End of /NAMES list.');
  }

  void topic(Client c, Channel ch) {
    if (ch.topic.isEmpty) {
      numeric(c, 331, '${ch.name} :No topic is set');
    } else {
      numeric(c, 332, '${ch.name} :${ch.topic}');
      numeric(c, 333, '${ch.name} ${ch.setter} ${ch.topicTime}');
    }
  }

  bool need(Client c, String command, List<String> args, int count) {
    if (args.length >= count) return false;
    numeric(c, 461, '$command :Not enough parameters');
    return true;
  }

  void process(Client c, String raw) {
    processed++;
    final (cmd, a) = parse(raw);
    if (cmd.isEmpty) {
      empty++;
      return;
    }
    commands[cmd] = (commands[cmd] ?? 0) + 1;
    if (!c.registered &&
        !['NICK', 'USER', 'PING', 'PONG', 'QUIT'].contains(cmd)) {
      errorReply(c, 451);
      return;
    }
    switch (cmd) {
      case 'NICK':
        {
          if (a.isEmpty || a[0].isEmpty) {
            errorReply(c, 431);
            return;
          }
          final nick = a[0].substring(0, min(a[0].length, setting('NICKLEN')));
          if (!validNick(nick)) {
            errorReply(c, 432, nick);
            return;
          }
          if (nick == c.nick) return;
          for (final other in clients) {
            if (other != c &&
                other.nick.isNotEmpty &&
                fold(other.nick) == fold(nick)) {
              errorReply(c, 433, nick);
              return;
            }
          }
          if (c.registered) {
            final text = ':${c.prefix} NICK :$nick';
            send(c, text);
            peers(c, text);
          }
          c.nick = nick;
          register(c);
          break;
        }
      case 'USER':
        {
          if (c.user.isNotEmpty) {
            errorReply(c, 462);
            return;
          }
          if (need(c, cmd, a, 4)) return;
          c.user = a[0];
          c.real = a[3];
          c.invisible =
              digits(a[1]) && a[1].length <= 3 && (number(a[1]) ~/ 8) % 2 == 1;
          register(c);
          break;
        }
      case 'PING':
        {
          if (a.isEmpty || a[0].isEmpty) {
            numeric(c, 409, ':No origin specified');
            return;
          }
          send(c, ':${config['NAME']} PONG ${config['NAME']} :${a[0]}');
          break;
        }
      case 'PONG':
        return;
      case 'QUIT':
        {
          final reason = a.isNotEmpty && a[0].isNotEmpty
              ? 'Quit: ${a[0]}'
              : 'Client Quit';
          disconnect(c, reason, 'quit');
          break;
        }
      case 'JOIN':
        {
          if (need(c, cmd, a, 1)) return;
          if (a[0] == '0') {
            for (final ch in List<Channel>.of(c.channels)) {
              members(ch, null, ':${c.prefix} PART ${ch.name}');
              remove(c, ch);
            }
            return;
          }
          final keyList = a.length > 1 ? a[1].split(',') : <String>[],
              nameList = a[0].split(',');
          for (var i = 0; i < nameList.length; i++) {
            final x = nameList[i], key = i < keyList.length ? keyList[i] : '';
            if (!validChannel(x, setting('CHANNELLEN'))) {
              errorReply(c, 403, x);
              continue;
            }
            var ch = channel(x);
            if (ch != null && ch.member(c) != null) continue;
            if (c.channels.length >= setting('MAXCHANNELS')) {
              errorReply(c, 405, x);
              continue;
            }
            if (ch == null) {
              ch = Channel(x, time);
              channels.add(ch);
            } else {
              final invited = c.invites.contains(ch);
              var error = 0;
              if (ch.banned(c) && !invited) {
                error = 474;
              } else if (ch.flags['i'] == true && !invited) {
                error = 473;
              } else if (ch.key.isNotEmpty && key != ch.key) {
                error = 475;
              } else if (ch.limit > 0 && ch.members.length >= ch.limit) {
                error = 471;
              }
              if (error != 0) {
                errorReply(c, error, ch.name);
                continue;
              }
            }
            c.invites.remove(ch);
            ch.add(c);
            members(ch, null, ':${c.prefix} JOIN ${ch.name}');
            if (ch.topic.isNotEmpty) topic(c, ch);
            names(c, ch);
          }
          break;
        }
      case 'PART':
        {
          if (need(c, cmd, a, 1)) return;
          final suffix = a.length > 1 && a[1].isNotEmpty ? ' :${a[1]}' : '';
          for (final x in a[0].split(',')) {
            final ch = channel(x);
            if (ch == null) {
              errorReply(c, 403, x);
              continue;
            }
            if (ch.member(c) == null) {
              errorReply(c, 442, ch.name);
              continue;
            }
            members(ch, null, ':${c.prefix} PART ${ch.name}$suffix');
            remove(c, ch);
          }
          break;
        }
      case 'PRIVMSG':
      case 'NOTICE':
        {
          final notice = cmd == 'NOTICE';
          if (!notice) c.lastSpeaking = time;
          if (a.isEmpty || a[0].isEmpty) {
            if (!notice) numeric(c, 411, ':No recipient given ($cmd)');
            return;
          }
          if (a.length < 2 || a[1].isEmpty) {
            if (!notice) numeric(c, 412, ':No text to send');
            return;
          }
          for (final x in a[0].split(',')) {
            if (x.startsWith('#')) {
              final ch = channel(x);
              if (ch == null) {
                if (!notice) errorReply(c, 401, x);
                continue;
              }
              if (!ch.canSpeak(c)) {
                if (!notice) errorReply(c, 404, ch.name);
                continue;
              }
              ch.messages++;
              members(ch, c, ':${c.prefix} $cmd ${ch.name} :${a[1]}');
            } else {
              final u = user(x);
              if (u == null) {
                if (!notice) errorReply(c, 401, x);
                continue;
              }
              send(u, ':${c.prefix} $cmd ${u.nick} :${a[1]}');
              if (!notice && u.away.isNotEmpty)
                numeric(c, 301, '${u.nick} :${u.away}');
            }
          }
          break;
        }
      case 'TOPIC':
        {
          if (need(c, cmd, a, 1)) return;
          final ch = channel(a[0]);
          if (ch == null) {
            errorReply(c, 403, a[0]);
            return;
          }
          final m = ch.member(c);
          if (m == null) {
            errorReply(c, 442, ch.name);
            return;
          }
          if (a.length == 1) {
            topic(c, ch);
            return;
          }
          if (ch.flags['t'] == true && !m.op) {
            errorReply(c, 482, ch.name);
            return;
          }
          ch.topic = a[1].substring(0, min(a[1].length, setting('TOPICLEN')));
          ch.setter = c.nick;
          ch.topicTime = time;
          members(ch, null, ':${c.prefix} TOPIC ${ch.name} :${ch.topic}');
          break;
        }
      case 'NAMES':
        {
          if (a.isEmpty) {
            numeric(c, 366, '* :End of /NAMES list.');
            return;
          }
          for (final x in a[0].split(',')) {
            final ch = channel(x);
            if (ch == null) {
              numeric(c, 366, '$x :End of /NAMES list.');
            } else {
              names(c, ch);
            }
          }
          break;
        }
      case 'WHOIS':
        {
          if (a.isEmpty) {
            errorReply(c, 431);
            return;
          }
          final u = user(a[0]);
          if (u == null) {
            errorReply(c, 401, a[0]);
            numeric(c, 318, '${a[0]} :End of /WHOIS list.');
            return;
          }
          numeric(c, 311, '${u.nick} ${u.user} ${u.host} * :${u.real}');
          if (u.channels.isNotEmpty)
            numeric(c, 319, '${u.nick} :${channelNames(u, ' ')}');
          numeric(
            c,
            312,
            '${u.nick} ${config['NAME']} :${config['DESCRIPTION']}',
          );
          if (u.away.isNotEmpty) numeric(c, 301, '${u.nick} :${u.away}');
          numeric(
            c,
            317,
            '${u.nick} ${time - u.lastSpeaking} ${u.signon} :seconds idle, signon time',
          );
          numeric(c, 318, '${u.nick} :End of /WHOIS list.');
          break;
        }
      case 'AWAY':
        {
          if (a.isNotEmpty && a[0].isNotEmpty) {
            c.away = a[0];
            numeric(c, 306, ':You have been marked as being away');
          } else {
            c.away = '';
            numeric(c, 305, ':You are no longer marked as being away');
          }
          break;
        }
      case 'INVITE':
        {
          if (need(c, cmd, a, 2)) return;
          final u = user(a[0]);
          if (u == null) {
            errorReply(c, 401, a[0]);
            return;
          }
          final ch = channel(a[1]);
          if (ch == null) {
            errorReply(c, 403, a[1]);
            return;
          }
          final m = ch.member(c);
          if (m == null) {
            errorReply(c, 442, ch.name);
            return;
          }
          if (ch.member(u) != null) {
            numeric(c, 443, '${u.nick} ${ch.name} :is already on channel');
            return;
          }
          if (ch.flags['i'] == true && !m.op) {
            errorReply(c, 482, ch.name);
            return;
          }
          if (!u.invites.contains(ch)) u.invites.add(ch);
          numeric(c, 341, '${u.nick} ${ch.name}');
          if (u.away.isNotEmpty) numeric(c, 301, '${u.nick} :${u.away}');
          send(u, ':${c.prefix} INVITE ${u.nick} :${ch.name}');
          break;
        }
      case 'KICK':
        {
          if (need(c, cmd, a, 2)) return;
          final ch = channel(a[0]);
          if (ch == null) {
            errorReply(c, 403, a[0]);
            return;
          }
          final m = ch.member(c);
          if (m == null) {
            errorReply(c, 442, ch.name);
            return;
          }
          if (!m.op) {
            errorReply(c, 482, ch.name);
            return;
          }
          final u = user(a[1]);
          if (u == null) {
            errorReply(c, 401, a[1]);
            return;
          }
          if (ch.member(u) == null) {
            numeric(
              c,
              441,
              '${u.nick} ${ch.name} :They aren\'t on that channel',
            );
            return;
          }
          final reason = a.length > 2 && a[2].isNotEmpty ? a[2] : c.nick;
          members(ch, null, ':${c.prefix} KICK ${ch.name} ${u.nick} :$reason');
          remove(u, ch);
          break;
        }
      case 'MODE':
        {
          if (need(c, cmd, a, 1)) return;
          if (a[0].startsWith('#')) {
            channelMode(c, a);
          } else {
            userMode(c, a);
          }
          break;
        }
      default:
        numeric(c, 421, '$cmd :Unknown command');
    }
  }

  void userMode(Client c, List<String> a) {
    final u = user(a[0]);
    if (u == null) {
      errorReply(c, 401, a[0]);
      return;
    }
    if (u != c) {
      errorReply(c, 502);
      return;
    }
    if (a.length == 1) {
      numeric(c, 221, c.mode);
      return;
    }
    final changes = <ModeItem>[];
    var sign = '+', unknown = false;
    for (var i = 0; i < a[1].length; i++) {
      final flag = a[1][i];
      if (flag == '+' || flag == '-') {
        sign = flag;
      } else if (flag == 'i') {
        final want = sign == '+';
        if (c.invisible != want) {
          c.invisible = want;
          changes.add(ModeItem(sign, 'i'));
        }
      } else {
        unknown = true;
      }
    }
    if (changes.isNotEmpty)
      send(c, ':${c.nick} MODE ${c.nick} :${changeString(changes)}');
    if (unknown) errorReply(c, 501);
  }

  void channelMode(Client c, List<String> a) {
    final ch = channel(a[0]);
    if (ch == null) {
      errorReply(c, 403, a[0]);
      return;
    }
    if (a.length == 1) {
      numeric(c, 324, '${ch.name} ${ch.mode(ch.member(c) != null)}');
      numeric(c, 329, '${ch.name} ${ch.created}');
      return;
    }
    final items = modeItems(a[1], a.sublist(2)),
        m = ch.member(c),
        op = m != null && m.op,
        changes = <ModeItem>[];
    var listed = false, denied = false;
    for (final item in items) {
      final flag = item.flag, plus = item.sign == '+';
      if (!'biklmnotv'.contains(flag)) {
        numeric(c, 472, '$flag :is unknown mode char to me for ${ch.name}');
        continue;
      }
      if (flag == 'b' && !item.has) {
        if (plus && !listed) {
          for (final b in ch.bans) {
            numeric(c, 367, '${ch.name} ${b.mask} ${b.setter} ${b.time}');
          }
          numeric(c, 368, '${ch.name} :End of channel ban list');
          listed = true;
        }
        continue;
      }
      if ((flag == 'o' || flag == 'v') && !item.has ||
          plus && (flag == 'k' || flag == 'l') && !item.has)
        continue;
      if (!op) {
        if (!denied) {
          errorReply(c, 482, ch.name);
          denied = true;
        }
        continue;
      }
      var changed = false;
      switch (flag) {
        case 'o':
        case 'v':
          {
            final u = user(item.arg);
            if (u == null) {
              errorReply(c, 401, item.arg);
              continue;
            }
            final member = ch.member(u);
            if (member == null) {
              numeric(
                c,
                441,
                '${u.nick} ${ch.name} :They aren\'t on that channel',
              );
              continue;
            }
            if (flag == 'o') {
              if (member.op != plus) {
                member.op = plus;
                changed = true;
              }
            } else if (member.voice != plus) {
              member.voice = plus;
              changed = true;
            }
            item.arg = u.nick;
            break;
          }
        case 'b':
          {
            final mask = normalizeMask(item.arg),
                index = ch.bans.indexWhere((b) => fold(b.mask) == fold(mask));
            if (plus && index < 0) {
              ch.bans.add(Ban(mask, c.nick, time));
              item.arg = mask;
              changed = true;
            } else if (!plus && index >= 0) {
              item.arg = ch.bans.removeAt(index).mask;
              changed = true;
            }
            break;
          }
        case 'k':
          {
            if (plus) {
              if (ch.key.isNotEmpty) {
                errorReply(c, 467, ch.name);
              } else {
                ch.key = item.arg;
                changed = true;
              }
            } else if (ch.key.isNotEmpty) {
              ch.key = '';
              item.arg = '*';
              changed = true;
            }
            break;
          }
        case 'l':
          {
            if (plus) {
              final v = number(item.arg);
              if (ch.limit != v) {
                ch.limit = v;
                changed = true;
              }
              item.arg = '$v';
            } else {
              if (ch.limit > 0) {
                ch.limit = 0;
                changed = true;
              }
              item.has = false;
            }
            break;
          }
        default:
          if ((ch.flags[flag] ?? false) != plus) {
            ch.flags[flag] = plus;
            changed = true;
          }
          item.has = false;
      }
      if (changed) changes.add(item);
    }
    if (changes.isNotEmpty)
      members(
        ch,
        null,
        ':${c.prefix} MODE ${ch.name} ${changeString(changes)}',
      );
  }

  void arrive(Traffic e) {
    if (e.body.startsWith('CONNECT ')) {
      connectLines++;
      final c = Client(e.id, e.body.substring(8), time, setting('BUCKET'));
      clients.add(c);
      byID[c.id] = c;
      if (clients.length > peakConnections) {
        peakConnections = clients.length;
        peakConnectionsAt = time;
      }
      return;
    }
    if (e.body == 'DISCONNECT') {
      disconnectLines++;
      final c = byID[e.id];
      if (c != null)
        disconnect(c, 'Remote host closed the connection', 'closed');
      return;
    }
    messageLines++;
    final c = byID[e.id];
    if (c == null) {
      dropped++;
      return;
    }
    c.received++;
    c.lastReceived = time;
    c.pinging = false;
    if (c.queue.isEmpty && c.tokens > 0) {
      c.use(time, setting('BUCKET'), setting('REFILL'));
      process(c, e.body);
    } else if (c.queue.length >= setting('QUEUE')) {
      discarded++;
      disconnect(c, 'Excess Flood', 'flood');
    } else {
      c.queue.add(e.body);
      queued++;
    }
  }

  void run() {
    var at = 0;
    for (time = 0; time <= end; time++) {
      for (final c in List<Client>.of(clients)) {
        c.refillTokens(time, setting('BUCKET'), setting('REFILL'));
        while (c.alive && c.queue.isNotEmpty && c.tokens > 0) {
          c.use(time, setting('BUCKET'), setting('REFILL'));
          final raw = c.queue.removeAt(0);
          process(c, raw);
        }
      }
      while (at < traffic.length && traffic[at].time == time) {
        arrive(traffic[at++]);
      }
      for (final c in List<Client>.of(clients)) {
        if (c.pinging) {
          if (time - c.pingAt >= setting('TIMEOUT'))
            disconnect(
              c,
              'Ping timeout: ${time - c.lastReceived} seconds',
              'timeout',
            );
        } else if (time - c.lastReceived >= setting('PINGFREQ')) {
          send(c, 'PING :${config['NAME']}');
          pings++;
          c.pinging = true;
          c.pingAt = time;
        }
      }
    }
  }

  List<String> channelLines() {
    final out = <String>[];
    var members = 0, bans = 0;
    for (final ch in channels) {
      out.add(
        'CHANNEL ${ch.name} created ${ch.created} members ${ch.members.length} peak ${ch.peak} messages ${ch.messages} modes ${ch.mode(true)}',
      );
      out.add(
        ch.topic.isEmpty
            ? 'TOPIC none'
            : 'TOPIC ${ch.setter} ${ch.topicTime} ${ch.topic}',
      );
      for (final b in ch.bans) {
        out.add('BAN ${b.mask} ${b.setter} ${b.time}');
      }
      out.add('MEMBERS ${ch.names(ch.members[0].client)}');
      members += ch.members.length;
      bans += ch.bans.length;
    }
    out.add('TOTAL channels ${channels.length} members $members bans $bans');
    return out;
  }

  List<String> clientLines() {
    final out = <String>[];
    var registered = 0, invisible = 0, away = 0;
    for (final c in clients) {
      final user = c.user.isEmpty ? '*' : c.user,
          signon = c.registered ? '${c.signon}' : '-';
      if (c.registered) registered++;
      if (c.invisible) invisible++;
      var joined = channelNames(c, ','),
          invites = c.invites.map((ch) => ch.name).join(',');
      if (joined.isEmpty) joined = 'none';
      if (invites.isEmpty) invites = 'none';
      out.add(
        'CLIENT ${c.id} ${c.addressee} $user ${c.host} ${c.mode} connected ${c.connected} signon $signon received ${c.received} sent ${c.sent} tokens ${c.tokens} queue ${c.queue.length} channels $joined invites $invites',
      );
      if (c.away.isNotEmpty) {
        away++;
        out.add('AWAY ${c.id} ${c.away}');
      }
    }
    out.add(
      'TOTAL clients ${clients.length} registered $registered invisible $invisible away $away',
    );
    return out;
  }

  List<String> statLines() {
    final pending = clients.fold(0, (a, c) => a + c.queue.length),
        numCount = numerics.values.fold(0, (a, b) => a + b),
        numericKeys = numerics.keys.toList()..sort();
    final out = [
      'END $end',
      'LINES total ${traffic.length} connect $connectLines disconnect $disconnectLines messages $messageLines',
      'MESSAGES dropped $dropped queued $queued processed $processed discarded $discarded pending $pending empty $empty',
      'SENT lines ${sent.length} numerics $numCount pings $pings errors $errors',
    ];
    final commandKeys = commands.keys.toList()..sort();
    for (final cmd in commandKeys) {
      out.add('COMMAND $cmd ${commands[cmd]}');
    }
    for (final n in numericKeys) {
      out.add('NUMERIC ${n.toString().padLeft(3, '0')} ${numerics[n]}');
    }
    out.addAll([
      'PEAK connections $peakConnections at $peakConnectionsAt',
      'PEAK registered $peakRegistered at $peakRegisteredAt',
      'DISCONNECTS quit ${disconnects['quit'] ?? 0} closed ${disconnects['closed'] ?? 0} flood ${disconnects['flood'] ?? 0} timeout ${disconnects['timeout'] ?? 0}',
      ...gone,
    ]);
    return out;
  }
}

void main() {
  final s = Server();
  for (final line in File('input/server.txt').readAsLinesSync()) {
    final i = line.indexOf(' '),
        key = line.substring(0, i),
        value = line.substring(i + 1);
    if (key == 'MOTD') {
      s.motd.add(value);
    } else {
      s.config[key] = value;
    }
  }
  for (final line in File('input/traffic.txt').readAsLinesSync()) {
    final i = line.indexOf(' '),
        j = line.indexOf(' ', i + 1),
        t = number(line.substring(0, i));
    s.traffic.add(Traffic(t, line.substring(i + 1, j), line.substring(j + 1)));
    s.end = t;
  }
  s.run();
  Directory('output').createSync(recursive: true);
  final reports = {
    'sent.txt': s.sent,
    'channels.txt': s.channelLines(),
    'clients.txt': s.clientLines(),
    'stats.txt': s.statLines(),
  };
  for (final e in reports.entries) {
    File(
      'output/${e.key}',
    ).writeAsStringSync(e.value.isEmpty ? '' : '${e.value.join('\n')}\n');
  }
}
