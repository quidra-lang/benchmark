part of 'main.dart';

class Session {
  final ASNode owner;
  final Link link;
  final Map<Prefix, Attribute> incoming = {}, outgoing = {};
  final Set<Prefix> pending = {};
  int timer = -1, sent = 0, received = 0;
  Session(this.owner, this.link);
}

class Message {
  final int serial, time;
  final Session source;
  final Prefix prefix;
  final Attribute? attribute;
  Message(this.serial, this.time, this.source, this.prefix, this.attribute);
  ASNode get sender => source.owner;
  ASNode get receiver => source.link.other(sender);
  Link get link => source.link;
}

int messageCompare(Message a, Message b) {
  var c = a.time.compareTo(b.time);
  if (c != 0) return c;
  c = a.receiver.number.compareTo(b.receiver.number);
  if (c != 0) return c;
  c = a.sender.number.compareTo(b.sender.number);
  return c != 0 ? c : a.serial.compareTo(b.serial);
}

class MessageQueue {
  final List<Message> heap = [];
  int serial = 0;
  void push(Message m) {
    heap.add(m);
    var i = heap.length - 1;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (messageCompare(heap[p], m) <= 0) break;
      heap[i] = heap[p];
      i = p;
    }
    heap[i] = m;
  }

  Message pop() {
    final first = heap.first, last = heap.removeLast();
    if (heap.isNotEmpty) {
      var i = 0;
      while (i * 2 + 1 < heap.length) {
        var c = i * 2 + 1;
        if (c + 1 < heap.length && messageCompare(heap[c + 1], heap[c]) < 0)
          c++;
        if (messageCompare(last, heap[c]) <= 0) break;
        heap[i] = heap[c];
        i = c;
      }
      heap[i] = last;
    }
    return first;
  }

  Message send(int time, Session s, Prefix p, Attribute? a) {
    final m = Message(++serial, time + s.link.delay, s, p, a);
    push(m);
    return m;
  }

  List<Message> arrivals(int time) {
    final out = <Message>[];
    while (heap.isNotEmpty && heap.first.time == time) {
      out.add(pop());
    }
    return out;
  }

  List<Message> ordered() => List<Message>.of(heap)..sort(messageCompare);
  List<Message> removeLink(Link link) {
    final removed = <Message>[], keep = <Message>[];
    for (final m in ordered()) {
      (m.link == link ? removed : keep).add(m);
    }
    heap.clear();
    for (final m in keep) {
      push(m);
    }
    return removed;
  }
}

class Event {
  final int number, time;
  final String kind, text;
  final List<String> args;
  Event(this.number, this.time, this.kind, this.text, this.args);
}

class Parameters {
  final int customer, peer, provider, stepcap;
  final List<(ASNode, int, String)> traces = [];
  Parameters(this.customer, this.peer, this.provider, this.stepcap);
}

List<Event> readEvents() {
  final out = [Event(0, 0, 'INITIAL', 'INITIAL', [])];
  for (final line in lines('input/events.txt')) {
    final a = line.split(' ');
    out.add(
      Event(
        out.length,
        int.parse(a[0]),
        a[1] == 'LINK' || a[1] == 'POLICY' ? '${a[1]}_${a[2]}' : a[1],
        a.skip(1).join(' '),
        a.sublist(1),
      ),
    );
  }
  return out;
}

Parameters readParameters(Topology t) {
  final a = lines('input/params.txt'), v = a[0].split(' ');
  final p = Parameters(
    int.parse(v[1]),
    int.parse(v[2]),
    int.parse(v[3]),
    int.parse(a[1].split(' ')[1]),
  );
  for (final line in a.skip(2)) {
    final v = line.split(' ');
    p.traces.add((t.byNumber[int.parse(v[1])]!, ip(v[2]), v[2]));
  }
  return p;
}
