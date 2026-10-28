part of 'main.dart';

const messageTypes = ['RV', 'RVR', 'AE', 'AER', 'TN'],
    statFields = [
      'sent',
      'delivered',
      'inflight',
      'partition',
      'rule',
      'loss',
      'down',
    ];

class Counts {
  final List<int> values = List.filled(7, 0);
  String text() =>
      [for (var i = 0; i < 7; i++) '${statFields[i]} ${values[i]}'].join(' ');
}

class Drop {
  final String kind;
  final int start, end;
  Drop(this.kind, this.start, this.end);
}

class Link {
  int delay, loss = 0, passed = 0;
  final List<Drop> drops = [];
  final stats = Counts();
  Link(this.delay);
}

class Message {
  final String kind;
  int source = 0, destination = 0, term = 0, arrival = 0, serial = 0;
  final int last, lastTerm, previous, previousTerm, commit, m;
  final bool success;
  final List<Entry> entries;
  Message(
    this.kind, {
    this.last = 0,
    this.lastTerm = 0,
    this.previous = 0,
    this.previousTerm = 0,
    this.commit = 0,
    this.m = 0,
    this.success = false,
    this.entries = const [],
  });
}

int compareMessage(Message a, Message b) {
  var c = a.arrival.compareTo(b.arrival);
  if (c != 0) return c;
  c = a.source.compareTo(b.source);
  return c != 0 ? c : a.serial.compareTo(b.serial);
}

class Network {
  final List<List<Link?>> links;
  final List<int> groups;
  final total = Counts();
  final Map<String, Counts> byType = {
    for (final t in messageTypes) t: Counts(),
  };
  final List<Message> queue = [];
  int serial = 0;
  Network(int n, int delay)
    : links = List.generate(
        n + 1,
        (a) => List.generate(
          n + 1,
          (b) => a > 0 && b > 0 && a != b ? Link(delay) : null,
        ),
      ),
      groups = List.filled(n + 1, 0);
  void count(Message m, int field, int amount) {
    total.values[field] += amount;
    byType[m.kind]!.values[field] += amount;
    links[m.source][m.destination]!.stats.values[field] += amount;
  }

  bool separated(int a, int b) => groups[a] != groups[b];
  void push(Message m) {
    queue.add(m);
    var i = queue.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (compareMessage(queue[parent], m) <= 0) break;
      queue[i] = queue[parent];
      i = parent;
    }
    queue[i] = m;
  }

  Message pop() {
    final first = queue[0], last = queue.removeLast();
    if (queue.isNotEmpty) {
      var i = 0;
      while (2 * i + 1 < queue.length) {
        var child = 2 * i + 1;
        if (child + 1 < queue.length &&
            compareMessage(queue[child + 1], queue[child]) < 0)
          child++;
        if (compareMessage(last, queue[child]) <= 0) break;
        queue[i] = queue[child];
        i = child;
      }
      queue[i] = last;
    }
    return first;
  }

  void send(int t, Message m) {
    m.serial = ++serial;
    count(m, 0, 1);
    final link = links[m.source][m.destination]!;
    if (separated(m.source, m.destination)) {
      count(m, 3, 1);
      return;
    }
    for (final d in link.drops) {
      if ((d.kind == m.kind || d.kind == 'ALL') && d.start <= t && t <= d.end) {
        count(m, 4, 1);
        return;
      }
    }
    link.passed++;
    if (link.loss > 0 && link.passed % link.loss == 0) {
      count(m, 5, 1);
      return;
    }
    m.arrival = t + link.delay;
    count(m, 2, 1);
    push(m);
  }

  List<Message> arrivals(int t) {
    final out = <Message>[];
    while (queue.isNotEmpty && queue[0].arrival == t) {
      final m = pop();
      count(m, 2, -1);
      out.add(m);
    }
    return out;
  }

  bool deliver(Message m, bool up) {
    if (!up) {
      count(m, 6, 1);
      return false;
    }
    if (separated(m.source, m.destination)) {
      count(m, 3, 1);
      return false;
    }
    count(m, 1, 1);
    return true;
  }
}

Network readNetwork(int n) {
  final lines = readLines('input/network.txt'),
      w = Network(n, number(lines[0].split(' ')[1]));
  for (final line in lines.skip(1)) {
    final v = line.split(' ');
    for (var a = 1; a <= n; a++) {
      for (var b = 1; b <= n; b++) {
        if (a == b ||
            (v[1] != '*' && number(v[1]) != a) ||
            (v[2] != '*' && number(v[2]) != b))
          continue;
        final link = w.links[a][b]!;
        switch (v[0]) {
          case 'DELAY':
            link.delay = number(v[3]);
            break;
          case 'LOSS':
            link.loss = number(v[3]);
            break;
          case 'DROP':
            link.drops.add(Drop(v[3], number(v[4]), number(v[5])));
            break;
        }
      }
    }
  }
  return w;
}
