part of 'main.dart';

List<List<int>> graph(Simulation sim) {
  final out = List.generate(sim.events.length, (_) => <int>[]);
  for (final p in sim.processes) {
    for (var i = 0; i + 1 < p.events.length; i++) {
      out[p.events[i].number - 1].add(p.events[i + 1].number - 1);
    }
  }
  for (final c in sim.copies) {
    final received = c.received;
    if (received != null)
      out[c.message.event.number - 1].add(received.number - 1);
  }
  return out;
}

List<int>? path(List<List<int>> edges, int start, int end) {
  final parents = List.filled(edges.length, -1), queue = [start];
  parents[start] = start;
  for (var head = 0; head < queue.length && parents[end] < 0; head++) {
    final e = queue[head];
    for (final f in edges[e]) {
      if (parents[f] < 0) {
        parents[f] = e;
        queue.add(f);
        if (f == end) break;
      }
    }
  }
  if (parents[end] < 0) return null;
  final out = <int>[];
  for (var f = end; ; f = parents[f]) {
    out.add(f);
    if (f == start) break;
  }
  return out.reversed.toList();
}

class Concurrency {
  int pairs = 0, ordered = 0, concurrent = 0, sameLamport = 0, inversions = 0;
  final processes = <(int, int), int>{};
}

Concurrency concurrency(List<Event> events) {
  final out = Concurrency();
  for (var i = 0; i < events.length; i++) {
    final a = events[i];
    for (var j = i + 1; j < events.length; j++) {
      final b = events[j];
      out.pairs++;
      if (relation(a.v, b.v) == '||') {
        out.concurrent++;
        if (a.l == b.l) out.sameLamport++;
        final key = (min(a.process, b.process), max(a.process, b.process));
        out.processes[key] = (out.processes[key] ?? 0) + 1;
      } else {
        out.ordered++;
      }
      if ((a.time < b.time && a.l > b.l) || (a.time > b.time && a.l < b.l))
        out.inversions++;
    }
  }
  return out;
}

List<(MessageCopy, MessageCopy)> races(ProcessState p) {
  final out = <(MessageCopy, MessageCopy)>[];
  for (var i = 0; i + 1 < p.delivered.length; i++) {
    final a = p.delivered[i], b = p.delivered[i + 1];
    if (relation(a.message.event.v, b.message.event.v) == '||') out.add((a, b));
  }
  return out;
}

(List<(int, int, int)>, int) violations(Simulation sim) {
  final out = <(int, int, int)>[];
  var fifo = 0;
  for (var p = 0; p < sim.processes.length; p++) {
    final list = sim.processes[p].delivered;
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      for (var j = i + 1; j < list.length; j++) {
        final b = list[j];
        if (relation(b.message.event.v, a.message.event.v) == '->') {
          out.add((p, i, j));
          if (a.source == b.source) fifo++;
        }
      }
    }
  }
  return (out, fifo);
}

class EnumeratedCuts {
  final List<int> limits, strides;
  int product = 1, consistent = 0;
  late List<int> levels, amounts;
  late List<bool> valid;
  EnumeratedCuts(int n)
    : limits = List.filled(n, 0),
      strides = List.filled(n, 0);
  (int, bool) predicate(int threshold) {
    var count = 0;
    final safe = List.filled(product, false);
    for (var index = 0; index < product; index++) {
      if (!valid[index]) continue;
      if (amounts[index] >= threshold) {
        count++;
        continue;
      }
      if (index == 0) {
        safe[index] = true;
        continue;
      }
      for (var p = 0; p < strides.length; p++) {
        final stride = strides[p],
            component = (index ~/ stride) % (limits[p] + 1);
        if (component > 0 && safe[index - stride]) {
          safe[index] = true;
          break;
        }
      }
    }
    return (count, !safe.last);
  }
}

EnumeratedCuts enumerate(Simulation sim, int time) {
  final n = sim.processes.length, out = EnumeratedCuts(n);
  var maxLevel = 0;
  for (var p = 0; p < n; p++) {
    out.limits[p] = sim.processes[p].events.where((e) => e.time <= time).length;
    maxLevel += out.limits[p];
  }
  for (var p = n - 1; p >= 0; p--) {
    out.strides[p] = out.product;
    out.product *= out.limits[p] + 1;
  }
  out.levels = List.filled(maxLevel + 1, 0);
  out.amounts = List.filled(out.product, 0);
  out.valid = List.filled(out.product, false);
  for (var index = 0; index < out.product; index++) {
    final cut = List.generate(
      n,
      (p) => (index ~/ out.strides[p]) % (out.limits[p] + 1),
    );
    var level = 0, balance = 0, valid = true;
    for (var p = 0; p < n; p++) {
      level += cut[p];
      balance += balanceAt(sim.processes[p], cut[p]);
      if (cut[p] > 0 && !lessEqual(sim.processes[p].events[cut[p] - 1].v, cut))
        valid = false;
    }
    if (valid) {
      out.valid[index] = true;
      out.consistent++;
      out.levels[level]++;
      out.amounts[index] = sim.initial - balance;
    }
  }
  return out;
}
