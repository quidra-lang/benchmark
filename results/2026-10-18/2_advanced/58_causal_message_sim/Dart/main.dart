import 'dart:io';
import 'dart:math';
part 'network.dart';
part 'clocks.dart';
part 'processes.dart';
part 'snapshot.dart';
part 'analysis.dart';

class Params {
  int seed = 0, end = 0, cutTime = 0;
  final compares = <(String, String)>[],
      cuts = <List<int>>[],
      predicates = <int>[];
}

Params readParams() {
  final p = Params();
  for (final line in readLines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'SEED':
        p.seed = int.parse(a[1]);
      case 'END':
        p.end = int.parse(a[1]);
      case 'CUTCOUNT':
        p.cutTime = int.parse(a[1]);
      case 'COMPARE':
        p.compares.add((a[1], a[2]));
      case 'CUT':
        p.cuts.add(a.sublist(1).map(int.parse).toList());
      case 'PREDICATE':
        p.predicates.add(int.parse(a[1]));
    }
  }
  return p;
}

class Event {
  final int number, process, local, time, l, balance;
  final List<int> v;
  final String kind, details;
  final Message? message;
  final MessageCopy? copy;
  Event(
    this.number,
    this.process,
    this.local,
    this.time,
    this.l,
    this.balance,
    this.v,
    this.kind,
    this.details,
    this.message,
    this.copy,
  );
}

class Message {
  final int id, source, destination, amount;
  final String kind, tag;
  final List<int> stamp;
  late Event event;
  final copies = <MessageCopy>[];
  Message(
    this.id,
    this.source,
    this.destination,
    this.amount,
    this.kind,
    this.tag,
    this.stamp,
  );
}

class MessageCopy {
  final Message message;
  final int source, destination;
  int arrival = 0, delivery = -1;
  bool fifo = false, causal = false;
  List<int> missingProcesses = [];
  Event? received;
  MessageCopy(this.message, this.source, this.destination);
}

class Packet {
  final int source, destination, sequence, arrival;
  final MessageCopy? copy;
  final Snapshot? snapshot;
  Packet(
    this.source,
    this.destination,
    this.sequence,
    this.arrival,
    this.copy,
    this.snapshot,
  );
}

class Item {
  final int time, process, creation;
  final Action? action;
  final Packet? packet;
  Item(this.time, this.process, this.creation, this.action, this.packet);
}

class EventQueue {
  final items = <Item>[];
  bool less(Item a, Item b) => a.time != b.time
      ? a.time < b.time
      : a.process != b.process
      ? a.process < b.process
      : a.creation < b.creation;
  void add(Item item) {
    items.add(item);
    var k = items.length - 1;
    while (k > 0) {
      final p = (k - 1) ~/ 2;
      if (!less(items[k], items[p])) break;
      final temp = items[k];
      items[k] = items[p];
      items[p] = temp;
      k = p;
    }
  }

  Item remove() {
    final out = items.first, last = items.removeLast();
    if (items.isNotEmpty) {
      items[0] = last;
      var k = 0;
      while (2 * k + 1 < items.length) {
        var child = 2 * k + 1;
        if (child + 1 < items.length && less(items[child + 1], items[child]))
          child++;
        if (!less(items[child], items[k])) break;
        final temp = items[k];
        items[k] = items[child];
        items[child] = temp;
        k = child;
      }
    }
    return out;
  }
}

class Display {
  final Event? event;
  final SnapshotRecord? record;
  final String snapshot;
  Display.event(this.event) : record = null, snapshot = '';
  Display.record(this.record, this.snapshot) : event = null;
}

class Simulation {
  final Network network;
  final bool raw;
  final processes = <ProcessState>[],
      events = <Event>[],
      messages = <Message>[],
      copies = <MessageCopy>[],
      snapshots = <Snapshot>[],
      snapshotIndex = <String, Snapshot>{},
      display = <Display>[];
  final queue = EventQueue();
  int creation = 0, time = 0, initial = 0;
  Simulation(this.network, this.raw);
  void schedule(int t, int p, {Action? action, Packet? packet}) =>
      queue.add(Item(t, p, ++creation, action, packet));
  void dispatch(
    int source,
    int destination,
    MessageCopy? copy,
    Snapshot? snapshot,
  ) {
    final (sequence, arrival) = network.dispatch(
      source,
      destination,
      time,
      copy,
    );
    final packet = Packet(
      source,
      destination,
      sequence,
      arrival,
      copy,
      snapshot,
    );
    if (copy != null) copy.arrival = arrival;
    schedule(arrival, destination, packet: packet);
  }

  Event recordEvent(
    ProcessState p,
    String kind,
    String details, [
    Message? message,
    MessageCopy? copy,
  ]) {
    tick(p, copy?.message.event);
    final e = Event(
      events.length + 1,
      p.index,
      p.events.length + 1,
      time,
      p.l,
      p.balance,
      List.of(p.v),
      kind,
      details,
      message,
      copy,
    );
    events.add(e);
    p.events.add(e);
    p.counts[kind] = (p.counts[kind] ?? 0) + 1;
    p.minimum = min(p.minimum, p.balance);
    display.add(Display.event(e));
    return e;
  }

  void action(ProcessState p, Action a, int sender) {
    switch (a.kind) {
      case 'LOCAL':
        recordEvent(p, 'LOCAL', a.argument);
      case 'SNAPSHOT':
        var snapshot = snapshotIndex[a.argument];
        if (snapshot == null) {
          snapshot = Snapshot(a.argument, time, processes.length);
          for (final key in network.order) {
            snapshot.channels[key] = SnapshotChannel();
          }
          snapshotIndex[a.argument] = snapshot;
          snapshots.add(snapshot);
        }
        if (snapshot.records[p.index] != null) {
          snapshot.ignored.add((p.index, time));
        } else {
          record(snapshot, p, 'initiate');
        }
      default:
        var destination = -1, amount = 0, kind = 'P2P', tag = a.value;
        if (a.kind == 'BROADCAST') {
          kind = 'BCAST';
          tag = a.argument;
          p.b[p.index]++;
        } else {
          destination = a.argument == 'SENDER'
              ? sender
              : network.index[a.argument]!;
          if (a.kind == 'TRANSFER') {
            amount = int.parse(a.value);
            tag = 'transfer';
            if (amount > p.balance) {
              p.refused++;
              recordEvent(
                p,
                'NOFUNDS',
                'to ${network.names[destination]} amount $amount balance ${p.balance}',
              );
              return;
            }
            p.balance -= amount;
            p.outgoing += amount;
          }
        }
        final message = Message(
          messages.length + 1,
          p.index,
          destination,
          amount,
          kind,
          tag,
          kind == 'BCAST' ? List.of(p.b) : [],
        );
        messages.add(message);
        var eventKind = 'SEND',
            details =
                'm${message.id} to ${destination < 0 ? '' : network.names[destination]} tag $tag';
        if (kind == 'BCAST') {
          eventKind = 'BCAST';
          details = 'm${message.id} tag $tag';
        } else if (tag == 'transfer') {
          details += ' amount $amount balance ${p.balance}';
        }
        message.event = recordEvent(p, eventKind, details, message);
        for (var q = 0; q < processes.length; q++) {
          if (q == p.index || (kind == 'P2P' && q != destination)) continue;
          final copy = MessageCopy(message, p.index, q);
          message.copies.add(copy);
          copies.add(copy);
          dispatch(p.index, q, copy, null);
        }
    }
  }

  void record(Snapshot snapshot, ProcessState p, String reason) {
    final record = SnapshotRecord(
      p.index,
      time,
      p.balance,
      p.l,
      reason,
      List.of(p.v),
      List.of(p.hold),
    );
    snapshot.records[p.index] = record;
    display.add(Display.record(record, snapshot.name));
    for (var q = 0; q < processes.length; q++) {
      if (q == p.index) continue;
      snapshot.channels[(p.index, q)]!.dispatched = time;
      dispatch(p.index, q, null, snapshot);
    }
  }

  void marker(Packet packet) {
    final snapshot = packet.snapshot!, p = processes[packet.destination];
    if (snapshot.records[p.index] == null)
      record(snapshot, p, 'marker ${network.names[packet.source]}');
    snapshot.channels[(packet.source, packet.destination)]!.accepted = time;
    snapshot.markers++;
    if (snapshot.markers == network.order.length) snapshot.completed = time;
  }

  void deliver(MessageCopy copy) {
    final p = processes[copy.destination], message = copy.message;
    if (message.kind == 'BCAST') p.b[copy.source]++;
    p.balance += message.amount;
    p.incoming += message.amount;
    var details =
        'm${message.id} from ${network.names[copy.source]} tag ${message.tag}';
    if (message.tag == 'transfer')
      details += ' amount ${message.amount} balance ${p.balance}';
    copy.delivery = time;
    copy.received = recordEvent(p, 'RECV', details, message, copy);
    p.delivered.add(copy);
    for (final rule in p.rules) {
      if (rule.tag == message.tag) action(p, rule.action, copy.source);
    }
  }

  void accept(Packet packet) {
    final p = processes[packet.destination];
    p.next[packet.source]++;
    final c = packet.copy;
    if (c == null) {
      marker(packet);
      return;
    }
    for (final snapshot in snapshots) {
      final channel = snapshot.channels[(c.source, c.destination)]!;
      if (snapshot.records[c.destination] != null && channel.accepted < 0)
        channel.state.add(c);
    }
    if (raw || c.message.kind == 'P2P') {
      deliver(c);
      return;
    }
    if (!deliverable(c, p.b)) {
      c.causal = true;
      c.missingProcesses = missing(c, p.b);
      p.hold.add(c);
      return;
    }
    deliver(c);
    while (true) {
      final chosen = p.hold.indexWhere((c) => deliverable(c, p.b));
      if (chosen < 0) break;
      deliver(p.hold.removeAt(chosen));
    }
  }

  void arrival(Packet packet) {
    final p = processes[packet.destination];
    if (raw) {
      accept(packet);
    } else if (packet.sequence != p.next[packet.source]) {
      p.buffers[packet.source][packet.sequence] = packet;
      network.channels[(packet.source, packet.destination)]!.buffered++;
      packet.copy?.fifo = true;
    } else {
      accept(packet);
      while (true) {
        final buffered = p.buffers[packet.source].remove(p.next[packet.source]);
        if (buffered == null) break;
        accept(buffered);
      }
    }
    var held = p.hold.length;
    for (final buffer in p.buffers) {
      held += buffer.length;
    }
    p.maxHeld = max(p.maxHeld, held);
  }
}

Simulation simulate(Params params, bool raw) {
  final network = readNetwork(params.seed),
      programs = readPrograms(network),
      s = Simulation(network, raw);
  for (var i = 0; i < programs.length; i++) {
    s.processes.add(ProcessState(i, programs[i], programs.length));
    s.initial += programs[i].initial;
  }
  for (var p = 0; p < programs.length; p++) {
    for (final line in programs[p].scheduled) {
      for (var time = line.time; time <= params.end; time += line.period) {
        s.schedule(time, p, action: line.action);
        if (line.period == 0) break;
      }
    }
  }
  while (s.queue.items.isNotEmpty) {
    final item = s.queue.remove();
    if (item.time > params.end) break;
    s.time = item.time;
    if (item.action != null) {
      s.action(s.processes[item.process], item.action!, -1);
    } else {
      s.arrival(item.packet!);
    }
  }
  return s;
}

String eventName(Simulation s, Event e) =>
    '${s.network.names[e.process]}.${e.local}';
String copyName(Simulation s, MessageCopy c) =>
    'm${c.message.id}->${s.network.names[c.destination]}';
String names(Simulation s, List<int> indices) =>
    indices.map((p) => s.network.names[p]).join(',');
String yes(bool b) => b ? 'yes' : 'no';
String ids(List<MessageCopy> copies, bool amount, String empty) =>
    copies.isEmpty
    ? empty
    : copies
          .map(
            (c) =>
                'm${c.message.id}${amount && c.message.amount != 0 ? ':${c.message.amount}' : ''}',
          )
          .join(' ');
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}

void traceOutput(Simulation s) {
  final out = <String>[],
      delivered = s.copies.where((c) => c.received != null).length;
  for (final e in s.events) {
    out.add(
      '${e.number} t=${e.time} ${eventName(s, e)} ${e.kind} ${e.details} L=${e.l} V=${vectorText(e.v)}',
    );
  }
  out.add(
    'SUMMARY events ${s.events.length} messages ${s.messages.length} copies ${s.copies.length} delivered $delivered undelivered ${s.copies.length - delivered} draws ${s.network.draws}',
  );
  for (var p = 0; p < s.processes.length; p++) {
    final state = s.processes[p];
    out.add(
      'FINAL ${s.network.names[p]} events ${state.events.length} L=${state.l} V=${vectorText(state.v)} B=${vectorText(state.b)} balance ${state.balance} in ${state.incoming} out ${state.outgoing} refused ${state.refused} min ${state.minimum}',
    );
  }
  for (var p = 0; p < s.processes.length; p++) {
    final counts = s.processes[p].counts;
    out.add(
      'COUNTS ${s.network.names[p]} local ${counts['LOCAL'] ?? 0} nofunds ${counts['NOFUNDS'] ?? 0} send ${counts['SEND'] ?? 0} bcast ${counts['BCAST'] ?? 0} recv ${counts['RECV'] ?? 0}',
    );
  }
  writeLines('trace.txt', out);
}

void deliveryOutput(Simulation s, int end) {
  final out = <String>[],
      broadcastLists = List.generate(s.processes.length, (_) => <int>[]);
  for (var p = 0; p < s.processes.length; p++) {
    final state = s.processes[p];
    out.add('PROCESS ${s.network.names[p]}');
    final counts = List.filled(4, 0);
    var totalWait = 0, maxWait = 0;
    for (var rank = 0; rank < state.delivered.length; rank++) {
      final c = state.delivered[rank];
      var mode = 'direct', index = 0;
      if (c.fifo && c.causal) {
        mode = 'fifo+causal ${names(s, c.missingProcesses)}';
        index = 3;
      } else if (c.fifo) {
        mode = 'fifo';
        index = 1;
      } else if (c.causal) {
        mode = 'causal ${names(s, c.missingProcesses)}';
        index = 2;
      }
      counts[index]++;
      final wait = c.delivery - c.arrival;
      totalWait += wait;
      maxWait = max(maxWait, wait);
      out.add(
        '${rank + 1} m${c.message.id} from ${s.network.names[c.source]} ${c.message.kind} tag ${c.message.tag} sent ${c.message.event.time} arrived ${c.arrival} delivered ${c.delivery} wait $wait $mode',
      );
    }
    for (final c in s.copies) {
      if (c.destination != p || c.received != null || c.arrival > end) continue;
      final place = c.causal
          ? 'causal ${names(s, c.missingProcesses)}'
          : 'fifo';
      out.add(
        'HELD m${c.message.id} from ${s.network.names[c.source]} ${c.message.kind} tag ${c.message.tag} sent ${c.message.event.time} arrived ${c.arrival} $place',
      );
    }
    for (final c in s.copies) {
      if (c.destination == p && c.arrival > end)
        out.add(
          'TRANSIT m${c.message.id} from ${s.network.names[c.source]} ${c.message.kind} tag ${c.message.tag} sent ${c.message.event.time} arrival ${c.arrival}',
        );
    }
    out.add(
      'TOTAL delivered ${state.delivered.length} direct ${counts[0]} fifo ${counts[1]} causal ${counts[2]} both ${counts[3]} wait $totalWait max_wait $maxWait max_held ${state.maxHeld}',
    );
    for (final e in state.events) {
      if (e.message?.kind == 'BCAST') broadcastLists[p].add(e.message!.id);
    }
    out.add(
      'BCASTS ${broadcastLists[p].isEmpty ? 'none' : broadcastLists[p].map((id) => 'm$id').join(' ')}',
    );
  }
  for (final key in s.network.order) {
    final c = s.network.channels[key]!,
        delay = c.a == c.b ? '${c.a}' : '${c.a}-${c.b}';
    out.add(
      'CHANNEL ${s.network.names[key.$1]}->${s.network.names[key.$2]} ${c.kind} $delay messages ${c.copies} markers ${c.markers} buffered ${c.buffered} max_delay ${c.maxDelay} entries ${c.entries}',
    );
  }
  final tags = <String, List<int>>{};
  for (final c in s.copies) {
    final v = tags.putIfAbsent(c.message.tag, () => List.filled(4, 0));
    v[0]++;
    if (c.received != null) {
      final latency = c.delivery - c.message.event.time;
      v[1]++;
      v[2] += latency;
      v[3] = max(v[3], latency);
    }
  }
  final ordered = tags.keys.toList()..sort();
  for (final tag in ordered) {
    final v = tags[tag]!;
    out.add(
      'TAG $tag copies ${v[0]} delivered ${v[1]} latency ${v[2]} max ${v[3]}',
    );
  }
  final broadcasts = s.messages.where((m) => m.kind == 'BCAST').toList();
  for (final m in broadcasts) {
    var time = 0, all = true;
    for (final c in m.copies) {
      if (c.received == null) all = false;
      time = max(time, c.delivery);
    }
    out.add(
      'STABLE m${m.id} ${s.network.names[m.source]} tag ${m.tag} sent ${m.event.time} stable ${all ? time : 'none'}',
    );
  }
  var disagreements = 0;
  for (var i = 0; i < broadcasts.length; i++) {
    final b1 = broadcasts[i];
    for (var j = i + 1; j < broadcasts.length; j++) {
      final b2 = broadcasts[j], early = <int>[], late = <int>[];
      for (var p = 0; p < broadcastLists.length; p++) {
        final a = broadcastLists[p].indexOf(b1.id),
            b = broadcastLists[p].indexOf(b2.id);
        if (a >= 0 && b >= 0) (a < b ? early : late).add(p);
      }
      if (early.isNotEmpty && late.isNotEmpty) {
        disagreements++;
        out.add(
          'DISAGREE m${b1.id} m${b2.id} ${names(s, early)} ${names(s, late)}',
        );
      }
    }
  }
  out.add('DISAGREEMENTS $disagreements');
  writeLines('deliveries.txt', out);
}

String verdict(Simulation s, CutResult cut) => cut.orphans.isEmpty
    ? 'yes'
    : 'no ${cut.orphans.map((c) => copyName(s, c)).join(' ')}';
(int, int) snapshotMoney(Snapshot snapshot) {
  var balances = 0, channels = 0;
  for (final r in snapshot.records) {
    balances += r!.balance;
  }
  for (final c in snapshot.channels.values) {
    for (final copy in c.state) {
      channels += copy.message.amount;
    }
  }
  return (balances, channels);
}

void snapshotOutput(Simulation s, Simulation raw) {
  final out = <String>[];
  for (final snapshot in s.snapshots) {
    out.add(
      'SNAPSHOT ${snapshot.name} started ${snapshot.start} completed ${snapshot.completed}',
    );
    var pendingCount = 0, channelCount = 0;
    final collection = <MessageCopy, int>{};
    for (var p = 0; p < snapshot.records.length; p++) {
      final r = snapshot.records[p]!;
      out.add(
        'RECORD ${s.network.names[p]} t=${r.time} ${r.reason} balance ${r.balance} L=${r.l} V=${vectorText(r.v)} pending ${ids(r.pending, false, 'none')}',
      );
      pendingCount += r.pending.length;
      for (final c in r.pending) {
        collection[c] = (collection[c] ?? 0) + 1;
      }
    }
    for (final key in s.network.order) {
      final channel = snapshot.channels[key]!;
      channelCount += channel.state.length;
      for (final c in channel.state) {
        collection[c] = (collection[c] ?? 0) + 1;
      }
      out.add(
        'CHANNEL ${s.network.names[key.$1]}->${s.network.names[key.$2]} marker ${channel.dispatched} ${channel.accepted} state ${ids(channel.state, true, 'empty')}',
      );
    }
    for (final (p, time) in snapshot.ignored) {
      out.add('IGNORED ${s.network.names[p]} t=$time');
    }
    final cut = snapshotCut(snapshot), result = analyzeCut(s, cut);
    out.add(
      'CUT ${vectorText(cut)} consistent ${verdict(s, result)} vector ${yes(result.vector)}',
    );
    var match = channelCount + pendingCount == result.transit.length;
    for (final c in result.transit) {
      collection[c] = (collection[c] ?? 0) - 1;
    }
    if (collection.values.any((v) => v != 0)) match = false;
    out.add(
      'TRANSIT channels $channelCount pending $pendingCount cut ${result.transit.length} match ${yes(match)}',
    );
    final (balances, channels) = snapshotMoney(snapshot);
    out.add(
      'MONEY balances $balances channels $channels total ${balances + channels} initial ${s.initial} conserved ${yes(balances + channels == s.initial)}',
    );
  }
  for (final snapshot in raw.snapshots) {
    final cut = snapshotCut(snapshot), result = analyzeCut(raw, cut);
    final (balances, channels) = snapshotMoney(snapshot);
    final money = balances + channels;
    out.add(
      'RAW ${snapshot.name} completed ${snapshot.completed} cut ${vectorText(cut)} consistent ${verdict(raw, result)} money $money conserved ${yes(money == raw.initial)}',
    );
  }
  writeLines('snapshots.txt', out);
}

String rangeText(Simulation s, List<Event> events) {
  final out = <String>[];
  for (var i = 0; i < events.length;) {
    var j = i + 1;
    while (j < events.length && events[j].process == events[i].process) {
      j++;
    }
    var text = eventName(s, events[i]);
    if (j - i > 1) text += '-${events[j - 1].local}';
    out.add(text);
    i = j;
  }
  return out.join(' ');
}

List<Event> longestChain(Simulation s) {
  if (s.events.isEmpty) return [];
  var e = s.events.first;
  for (final f in s.events.skip(1)) {
    if (f.l > e.l) e = f;
  }
  final out = [e];
  while (e.l > 1) {
    final copy = e.copy;
    if (copy != null && copy.message.event.l == e.l - 1) {
      e = copy.message.event;
    } else {
      e = s.processes[e.process].events[e.local - 2];
    }
    out.add(e);
  }
  return out.reversed.toList();
}

void analysisOutput(Simulation s, Simulation raw, Params params) {
  final out = <String>[],
      byName = {for (final e in s.events) eventName(s, e): e},
      edges = graph(s);
  for (final (an, bn) in params.compares) {
    final a = byName[an]!, b = byName[bn]!, rel = relation(a.v, b.v);
    var gr = '||', route = path(edges, a.number - 1, b.number - 1);
    if (route != null) {
      gr = '->';
    } else {
      route = path(edges, b.number - 1, a.number - 1);
      if (route != null) gr = '<-';
    }
    out.add(
      'COMPARE $an $rel $bn L=${a.l},${b.l} graph $gr agree ${yes(rel == gr)}',
    );
    if (route != null) {
      final events = route.map((i) => s.events[i]).toList();
      var messages = 0;
      for (var i = 1; i < events.length; i++) {
        if (events[i].process != events[i - 1].process) messages++;
      }
      out.add(
        'PATH length ${route.length} messages $messages ${rangeText(s, events)}',
      );
    }
    for (final e in [a, b]) {
      final future = [
        for (final state in s.processes)
          state.events.where((f) => f.v[e.process] < e.local).length,
      ];
      out.add(
        'WINDOW ${eventName(s, e)} past ${vectorText(e.v)} future ${vectorText(future)}',
      );
    }
  }
  final c = concurrency(s.events);
  out.add(
    'CONCURRENCY events ${s.events.length} pairs ${c.pairs} ordered ${c.ordered} concurrent ${c.concurrent} same_lamport ${c.sameLamport} inversions ${c.inversions}',
  );
  for (var p = 0; p < s.processes.length; p++) {
    for (var q = p + 1; q < s.processes.length; q++) {
      out.add(
        'PAIR ${s.network.names[p]} ${s.network.names[q]} ${c.processes[(p, q)] ?? 0}',
      );
    }
  }
  final chain = longestChain(s);
  out.add('CHAIN length ${chain.length} ${rangeText(s, chain)}');
  var raceCount = 0;
  for (var p = 0; p < s.processes.length; p++) {
    for (final (a, b) in races(s.processes[p])) {
      raceCount++;
      out.add(
        'RACE ${s.network.names[p]} m${a.message.id} ${s.network.names[a.source]} m${b.message.id} ${s.network.names[b.source]}',
      );
    }
  }
  out.add('RACES $raceCount');
  final (violationList, fifo) = violations(s);
  for (final (p, i, j) in violationList) {
    final a = s.processes[p].delivered[i], b = s.processes[p].delivered[j];
    out.add(
      'VIOLATION ${s.network.names[p]} m${a.message.id} ${s.network.names[a.source]} overtook m${b.message.id} ${s.network.names[b.source]}',
    );
  }
  out.add('VIOLATIONS causal ${violationList.length} fifo $fifo');
  final (rawViolations, rawFIFO) = violations(raw);
  final rawDelivered = raw.processes.fold(
    0,
    (sum, p) => sum + p.delivered.length,
  );
  out.add(
    'RAW events ${raw.events.length} delivered $rawDelivered causal ${rawViolations.length} fifo $rawFIFO',
  );
  for (final cut in params.cuts) {
    final result = analyzeCut(s, cut),
        status = result.orphans.isEmpty
            ? 'consistent'
            : 'inconsistent orphans ${result.orphans.map((c) => copyName(s, c)).join(' ')}';
    out.add(
      'CUT ${vectorText(cut)} $status transit ${result.transit.length} money ${result.money} initial ${s.initial}',
    );
  }
  final enumerated = enumerate(s, params.cutTime);
  out.add(
    'CUTCOUNT t=${params.cutTime} events ${vectorText(enumerated.limits)} product ${enumerated.product} consistent ${enumerated.consistent}',
  );
  out.add('LEVELS ${enumerated.levels.join(' ')}');
  for (final threshold in params.predicates) {
    final (count, definitely) = enumerated.predicate(threshold);
    out.add(
      'PREDICATE transit>=$threshold cuts $count possibly ${yes(count > 0)} definitely ${yes(definitely)}',
    );
  }
  writeLines('analysis.txt', out);
}

void put(List<String> canvas, int position, String text) {
  while (canvas.length < position + text.length) {
    canvas.add(' ');
  }
  for (var i = 0; i < text.length; i++) {
    canvas[position + i] = text[i];
  }
}

String diagramHeader(Simulation s, String kind) {
  final canvas = List.filled(6, ' ', growable: true);
  put(canvas, 4, kind);
  for (var p = 0; p < s.network.names.length; p++) {
    put(canvas, 6 + 8 * p, s.network.names[p]);
  }
  return canvas.join().trimRight();
}

String diagramLine(Simulation s, Display display, bool lamport) {
  final n = s.processes.length,
      canvas = List.filled(6 + 8 * (n - 1) + 1, ' ', growable: true);
  for (var p = 0; p < n; p++) {
    canvas[6 + 8 * p] = '|';
  }
  var time = 0;
  final e = display.event;
  if (e != null) {
    time = lamport ? e.l : e.time;
    final column = 6 + 8 * e.process,
        symbol = switch (e.kind) {
          'NOFUNDS' => 'x',
          'SEND' => 'S',
          'BCAST' => 'B',
          'RECV' => 'R',
          _ => '*',
        };
    canvas[column] = symbol;
    if (e.kind == 'SEND' || e.kind == 'BCAST')
      put(canvas, column + 1, 'm${e.message!.id}');
    if (e.kind == 'RECV') {
      final source = 6 + 8 * e.copy!.source,
          a = min(source, column),
          z = max(source, column);
      for (var pos = a + 1; pos < z; pos++) {
        canvas[pos] = (pos - 6) % 8 == 0 ? '+' : '-';
      }
      canvas[source < column ? z - 1 : a + 1] = source < column ? '>' : '<';
      put(canvas, a + 2, 'm${e.message!.id}');
    }
  } else {
    final r = display.record!;
    time = r.time;
    final column = 6 + 8 * r.process;
    canvas[column] = '#';
    put(canvas, column + 1, display.snapshot);
  }
  put(canvas, 0, time.toString().padLeft(5));
  return canvas.join().trimRight();
}

void diagramOutput(Simulation s) {
  final out = [diagramHeader(s, 't')];
  for (final d in s.display) {
    out.add(diagramLine(s, d, false));
  }
  out.add(diagramHeader(s, 'L'));
  final events = List<Event>.of(s.events)
    ..sort((a, b) {
      final c = a.l.compareTo(b.l);
      return c != 0 ? c : a.process.compareTo(b.process);
    });
  for (final e in events) {
    out.add(diagramLine(s, Display.event(e), true));
  }
  writeLines('diagram.txt', out);
}

void main() {
  final params = readParams(),
      mainRun = simulate(params, false),
      raw = simulate(params, true);
  traceOutput(mainRun);
  deliveryOutput(mainRun, params.end);
  snapshotOutput(mainRun, raw);
  analysisOutput(mainRun, raw, params);
  diagramOutput(mainRun);
}
