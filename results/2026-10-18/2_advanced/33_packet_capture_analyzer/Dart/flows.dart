part of 'main.dart';

const marks = [
  'retransmission',
  'out_of_order',
  'lost_segment',
  'duplicate_ack',
];
const sequenceModulus = 4294967296;
typedef Endpoint = (int, int);

bool endpointLess(Endpoint a, Endpoint b) =>
    a.$1 != b.$1 ? a.$1 < b.$1 : a.$2 < b.$2;
(Endpoint, Endpoint) endpointPair(Endpoint a, Endpoint b) =>
    endpointLess(b, a) ? (b, a) : (a, b);

class PreviousAck {
  final int ack, window, number;
  int count = 0;
  PreviousAck(this.ack, this.window, this.number);
}

class Side {
  final String name;
  int? isn, mss, wscale, base, expected;
  int advancedAt = 0, packets = 0, payload = 0;
  final intervals = <(int, int)>{};
  PreviousAck? previousAck;
  final counts = <String, int>{};
  Side(this.name);
}

class Stream {
  final int number, start;
  Endpoint client, server;
  String state = 'ESTABLISHED';
  final history = <(String, int)>[];
  int end, packets = 0, bytes = 0;
  int? syn, synAck, handshakeAck, finalAck;
  Side? closer;
  final clientSide = Side('client'), serverSide = Side('server');
  final events = <(int, String, String, int, int)>[];
  Stream(this.number, this.client, this.server, this.start) : end = start;
  void changeState(String next, int number) {
    state = next;
    history.add((next, number));
  }

  void recordSyn(Side side, Packet p) {
    side.isn = p.numberValue('tcp.seq_raw');
    side.mss = p.value('tcp.options.mss') as int?;
    side.wscale = p.value('tcp.options.wscale') as int?;
    if (identical(side, clientSide)) {
      syn = p.number;
    } else {
      synAck = p.number;
    }
  }
}

class StreamTracker {
  final streams = <Stream>[];
  final latest = <(Endpoint, Endpoint), Stream>{};
  final duplicateAcks = <int, (int, int)>{};
  void track(Packet p) {
    final source = (p.numberValue('ip.src'), p.numberValue('tcp.srcport'));
    final destination = (p.numberValue('ip.dst'), p.numberValue('tcp.dstport'));
    final seq = p.numberValue('tcp.seq_raw'),
        ack = p.numberValue('tcp.ack_raw');
    final syn = p.numberValue('tcp.flags.syn') == 1,
        fin = p.numberValue('tcp.flags.fin') == 1;
    final rst = p.numberValue('tcp.flags.rst') == 1,
        hasAck = p.numberValue('tcp.flags.ack') == 1;
    final key = endpointPair(source, destination);
    var stream = latest[key];
    if (stream == null ||
        ((stream.state == 'CLOSED' || stream.state == 'RESET') &&
            syn &&
            !hasAck)) {
      stream = Stream(streams.length, source, destination, p.time);
      if (syn && hasAck) {
        stream.client = destination;
        stream.server = source;
        stream.state = 'SYN_RECEIVED';
        stream.recordSyn(stream.serverSide, p);
      } else if (syn) {
        stream.state = 'SYN_SENT';
        stream.recordSyn(stream.clientSide, p);
      }
      stream.history.add((stream.state, p.number));
      streams.add(stream);
      latest[key] = stream;
    }
    p.set('tcp.stream', stream.number);
    final side = source == stream.client
        ? stream.clientSide
        : stream.serverSide;
    final other = source == stream.client
        ? stream.serverSide
        : stream.clientSide;
    side.base ??= seq;
    if (hasAck) other.base ??= ack;
    final relative = (seq - side.base!) % sequenceModulus;
    p.set('tcp.seq', relative);
    if (hasAck) p.set('tcp.ack', (ack - other.base!) % sequenceModulus);
    final size =
        p.numberValue('tcp.len') +
        p.numberValue('tcp.flags.syn') +
        p.numberValue('tcp.flags.fin');
    String? mark;
    if (size > 0) {
      if (side.expected != null && relative != side.expected) {
        if (relative > side.expected!) {
          mark = 'lost_segment';
        } else if (side.intervals.contains((relative, size))) {
          mark = 'retransmission';
        } else if (p.time - side.advancedAt < 3000) {
          mark = 'out_of_order';
        } else {
          mark = 'retransmission';
        }
      }
      side.intervals.add((relative, size));
      if (side.expected == null || relative + size > side.expected!) {
        side.expected = relative + size;
        side.advancedAt = p.time;
      }
    } else if (hasAck && !rst) {
      final previous = side.previousAck;
      if (previous != null &&
          ack == previous.ack &&
          p.numberValue('tcp.window') == previous.window) {
        mark = 'duplicate_ack';
        previous.count++;
        duplicateAcks[p.number] = (previous.number, previous.count);
      }
    }
    if (hasAck && mark != 'duplicate_ack')
      side.previousAck = PreviousAck(
        ack,
        p.numberValue('tcp.window'),
        p.number,
      );
    if (mark != null) {
      p.set('tcp.analysis.$mark', 1);
      side.counts[mark] = (side.counts[mark] ?? 0) + 1;
      stream.events.add((p.number, side.name, mark, relative, size));
    }
    var window = p.numberValue('tcp.window');
    if (stream.clientSide.wscale != null &&
        stream.serverSide.wscale != null &&
        !syn)
      window *= 1 << side.wscale!;
    p.set('tcp.window.calc', window);
    final state = stream.state;
    if (rst) {
      if (state != 'CLOSED' && state != 'RESET')
        stream.changeState('RESET', p.number);
    } else if (state == 'SYN_SENT' &&
        syn &&
        hasAck &&
        identical(side, stream.serverSide) &&
        ack == (stream.clientSide.isn! + 1) % sequenceModulus) {
      stream.changeState('SYN_RECEIVED', p.number);
      stream.recordSyn(stream.serverSide, p);
    } else if (state == 'SYN_RECEIVED' &&
        identical(side, stream.clientSide) &&
        hasAck &&
        !syn &&
        ack == (stream.serverSide.isn! + 1) % sequenceModulus) {
      stream.changeState('ESTABLISHED', p.number);
      stream.handshakeAck = p.number;
    } else if (state == 'ESTABLISHED' && fin) {
      stream.changeState('FIN_WAIT', p.number);
      stream.closer = side;
    } else if (state == 'FIN_WAIT' && fin && !identical(side, stream.closer)) {
      stream.changeState('CLOSING', p.number);
      stream.finalAck = (seq + p.numberValue('tcp.len') + 1) % sequenceModulus;
    } else if (state == 'CLOSING' &&
        identical(side, stream.closer) &&
        hasAck &&
        ack == stream.finalAck) {
      stream.changeState('CLOSED', p.number);
    }
    side.packets++;
    side.payload += p.numberValue('tcp.len');
    stream.packets++;
    stream.bytes += p.length;
    stream.end = p.time;
  }
}

class Conversation {
  final int kind, firstNumber, firstTime;
  final Endpoint a, b;
  int lastTime, packetsAB = 0, packetsBA = 0, bytesAB = 0, bytesBA = 0;
  Conversation(this.kind, this.a, this.b, this.firstNumber, this.firstTime)
    : lastTime = firstTime;
  int get packets => packetsAB + packetsBA;
  int get bytes => bytesAB + bytesBA;
}

List<Conversation> buildConversations(List<Packet> packets) {
  final table = <Object, Conversation>{};
  for (final p in packets) {
    if (!p.exists('ip.src')) continue;
    final source = (p.numberValue('ip.src'), -1),
        destination = (p.numberValue('ip.dst'), -1);
    final views = <(Object, int, Endpoint, Endpoint)>[
      ((0, endpointPair(source, destination)), 0, source, destination),
    ];
    if (p.exists('tcp.stream'))
      views.add((
        (1, p.numberValue('tcp.stream')),
        1,
        (source.$1, p.numberValue('tcp.srcport')),
        (destination.$1, p.numberValue('tcp.dstport')),
      ));
    if (p.exists('udp.srcport')) {
      final src = (source.$1, p.numberValue('udp.srcport')),
          dst = (destination.$1, p.numberValue('udp.dstport'));
      views.add(((2, endpointPair(src, dst)), 2, src, dst));
    }
    for (final v in views) {
      final c = table.putIfAbsent(
        v.$1,
        () => Conversation(v.$2, v.$3, v.$4, p.number, p.time),
      );
      if (v.$3 == c.a) {
        c.packetsAB++;
        c.bytesAB += p.length;
      } else {
        c.packetsBA++;
        c.bytesBA += p.length;
      }
      c.lastTime = p.time;
    }
  }
  return table.values.toList()..sort((a, b) {
    if (a.bytes != b.bytes) return b.bytes.compareTo(a.bytes);
    if (a.packets != b.packets) return b.packets.compareTo(a.packets);
    if (a.kind != b.kind) return a.kind.compareTo(b.kind);
    return a.firstNumber.compareTo(b.firstNumber);
  });
}

class EndpointTotals {
  final int address;
  int txPackets = 0, txBytes = 0, rxPackets = 0, rxBytes = 0;
  EndpointTotals(this.address);
  int get packets => txPackets + rxPackets;
  int get bytes => txBytes + rxBytes;
}

List<EndpointTotals> buildEndpoints(List<Packet> packets) {
  final table = <int, EndpointTotals>{};
  for (final p in packets) {
    if (!p.exists('ip.src')) continue;
    final source = p.numberValue('ip.src'),
        destination = p.numberValue('ip.dst');
    final sender = table.putIfAbsent(source, () => EndpointTotals(source));
    final receiver = table.putIfAbsent(
      destination,
      () => EndpointTotals(destination),
    );
    sender.txPackets++;
    sender.txBytes += p.length;
    receiver.rxPackets++;
    receiver.rxBytes += p.length;
  }
  return table.values.toList()..sort((a, b) {
    if (a.bytes != b.bytes) return b.bytes.compareTo(a.bytes);
    if (a.packets != b.packets) return b.packets.compareTo(a.packets);
    return a.address.compareTo(b.address);
  });
}
