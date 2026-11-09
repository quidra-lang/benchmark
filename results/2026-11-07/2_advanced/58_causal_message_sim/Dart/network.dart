part of 'main.dart';

class Channel {
  final int source, destination, a, b;
  final String kind;
  int sequence = 0,
      lastArrival = 0,
      copies = 0,
      markers = 0,
      buffered = 0,
      maxDelay = 0,
      entries = 0;
  List<int> previous;
  Channel(this.source, this.destination, this.kind, this.a, this.b, int n)
    : previous = List.filled(n, 0);
}

class Network {
  final List<String> names;
  final Map<String, int> index = {};
  final channels = <(int, int), Channel>{}, order = <(int, int)>[];
  int state, draws = 0;
  Network(this.names, this.state) {
    for (var i = 0; i < names.length; i++) {
      index[names[i]] = i;
    }
  }
  (int, int) dispatch(int src, int dst, int time, MessageCopy? copy) {
    final c = channels[(src, dst)]!;
    c.sequence++;
    var delay = c.a;
    if (c.a != c.b) {
      state = 48271 * state % 2147483647;
      draws++;
      delay += state % (c.b - c.a + 1);
    }
    var arrival = time + delay;
    if (c.kind == 'FIFO') arrival = max(arrival, c.lastArrival);
    c.lastArrival = max(c.lastArrival, arrival);
    c.maxDelay = max(c.maxDelay, arrival - time);
    if (copy == null) {
      c.markers++;
    } else {
      c.copies++;
      final v = copy.message.event.v;
      for (var i = 0; i < v.length; i++) {
        if (v[i] != c.previous[i]) c.entries++;
      }
      c.previous = List.of(v);
    }
    return (c.sequence, arrival);
  }
}

List<String> readLines(String path) => File(path).readAsLinesSync();
Network readNetwork(int seed) {
  final lines = readLines('input/topology.txt'),
      n = Network(lines.first.split(' ').sublist(1), seed);
  for (final line in lines.skip(1)) {
    final a = line.split(' '),
        src = n.index[a[1]]!,
        dst = n.index[a[2]]!,
        lo = int.parse(a[4]),
        hi = a.length == 6 ? int.parse(a[5]) : lo;
    n.channels[(src, dst)] = Channel(src, dst, a[3], lo, hi, n.names.length);
  }
  for (var src = 0; src < n.names.length; src++) {
    for (var dst = 0; dst < n.names.length; dst++) {
      if (src != dst) n.order.add((src, dst));
    }
  }
  return n;
}
