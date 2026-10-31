import 'dart:io';
import 'dart:collection';

class Process {
  final int id, created;
  List<int> maximum, allocation;
  Process(this.id, this.maximum, this.created, this.allocation);
  List<int> need() => sub(maximum, allocation);
  Process copy() => Process(id, List.of(maximum), created, List.of(allocation));
}
class Waiting {
  final int id, since;
  final List<int> vector;
  Waiting(this.id, this.vector, this.since);
}
class Event {
  final int command, id, waited;
  final String kind;
  final List<int> vector;
  Event(this.command, this.kind, this.id, this.vector, this.waited);
}
class State {
  List<int> total, available;
  final SplayTreeMap<int, Process> processes = SplayTreeMap();
  List<Waiting> queue = [];
  final List<Event> history = [];
  State(List<int> values) : total = List.of(values), available = List.of(values);
  State copy() {
    final result = State(total);
    result.available = List.of(available);
    for (final p in processes.values) { result.processes[p.id] = p.copy(); }
    result.queue = queue.map((w) => Waiting(w.id, List.of(w.vector), w.since)).toList();
    result.history.addAll(history.map((e) => Event(e.command, e.kind, e.id, List.of(e.vector), e.waited)));
    return result;
  }
}
class Check {
  final List<int> sequence, remaining;
  Check(this.sequence, this.remaining);
}
class Decision {
  final String? reason;
  final List<int> sequence;
  Decision(this.reason, [this.sequence = const []]);
}
class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}
State state = State([]);
final Map<String, State> snapshots = {};
String mode = 'AVOID', policy = 'ALLOC';
bool tracing = false, autodetect = false;
int command = 0;
final StringBuffer output = StringBuffer();
const kinds = ['granted', 'blocked', 'unblocked', 'released', 'finished', 'aborted', 'cancelled'];
void emit(String line) => output.writeln(line.trimRight());
String pn(int id) => 'P$id';
String pl(List<int> ids) => ids.map(pn).join(' ');
String vl(List<int> values) => '(${values.join(',')})';
String type(int i) => String.fromCharCode(65 + i);
List<int> add(List<int> a, List<int> b) => List.generate(a.length, (i) => a[i] + b[i]);
List<int> sub(List<int> a, List<int> b) => List.generate(a.length, (i) => a[i] - b[i]);
int sum(List<int> v) => v.fold(0, (a, b) => a + b);
bool fits(List<int> a, List<int> b) {
  for (int i = 0; i < a.length; i++) { if (a[i] > b[i]) return false; }
  return true;
}
Never fail(String message) => throw CommandError(message);
Waiting? waiting(int id) {
  for (final w in state.queue) { if (w.id == id) return w; }
  return null;
}
List<int> requestOf(int id) => waiting(id)?.vector ?? List.filled(state.total.length, 0);
Process requireProcess(int id, [bool unblocked = false]) {
  final p = state.processes[id];
  if (p == null) fail('unknown process ${pn(id)}');
  if (unblocked && waiting(id) != null) fail('process ${pn(id)} is blocked');
  return p;
}
List<int> vector(List<String> words, int start) {
  if (words.length - start != state.total.length) fail('wrong vector length');
  return words.skip(start).map(int.parse).toList();
}
Check check(List<int> available, bool detecting, bool traced, [Set<int> excluded = const {}]) {
  List<int> work = List.of(available);
  final List<int> remaining = [], idle = [], sequence = [];
  for (final p in state.processes.values) {
    if (excluded.contains(p.id)) { work = add(work, p.allocation); }
    else if (detecting && sum(p.allocation) == 0) { idle.add(p.id); }
    else { remaining.add(p.id); }
  }
  final prefix = detecting ? '[detect]' : '[safety]';
  if (traced) emit('$prefix start work=${vl(work)}${idle.isEmpty ? '' : ' idle ${pl(idle)}'}');
  while (true) {
    int? chosen;
    for (final id in remaining) {
      if (fits(detecting ? requestOf(id) : state.processes[id]!.need(), work)) { chosen = id; break; }
    }
    if (chosen == null) break;
    work = add(work, state.processes[chosen]!.allocation);
    remaining.remove(chosen);
    sequence.add(chosen);
    if (traced) emit('$prefix ${pn(chosen)} can finish, work=${vl(work)}');
  }
  if (traced && remaining.isNotEmpty) emit('$prefix stuck work=${vl(work)} remaining ${pl(remaining)}');
  return Check(sequence, remaining);
}
List<int> detect(bool traced) => check(state.available, true, traced).remaining;
String? rejection(Process p, List<int> v) {
  if (waiting(p.id) != null) return 'process ${pn(p.id)} is blocked';
  if (sum(v) == 0) return 'zero vector';
  if (!fits(v, p.need())) return 'request exceeds need';
  if (mode == 'ORDER') {
    int last = -1;
    for (int i = 0; i < v.length; i++) { if (p.allocation[i] > 0) last = i; }
    for (int i = 0; i <= last; i++) { if (v[i] > 0) return 'resource order violation'; }
  }
  return null;
}
Decision decision(Process p, List<int> v, bool traced) {
  if (!fits(v, state.available)) return Decision('insufficient resources');
  if (mode != 'AVOID') return Decision(null);
  final old = p.allocation;
  p.allocation = add(old, v);
  final result = check(sub(state.available, v), false, traced);
  p.allocation = old;
  return Decision(result.remaining.isEmpty ? null : 'unsafe state', result.sequence);
}
void allocate(Process p, List<int> v) {
  p.allocation = add(p.allocation, v);
  state.available = sub(state.available, v);
}
void record(String kind, int id, List<int> v, [int waited = 0]) {
  state.history.add(Event(command, kind, id, List.of(v), waited));
}
void retry() {
  final List<Waiting> kept = [];
  for (final w in state.queue) {
    final p = state.processes[w.id]!;
    if (decision(p, w.vector, tracing).reason == null) {
      allocate(p, w.vector);
      emit('unblocked ${pn(w.id)} ${vl(w.vector)}');
      record('unblocked', w.id, w.vector, command - w.since);
    } else { kept.add(w); }
  }
  state.queue = kept;
}
void terminate(int id, String kind) {
  final p = state.processes.remove(id)!;
  state.queue.removeWhere((w) => w.id == id);
  state.available = add(state.available, p.allocation);
  emit('$kind ${pn(id)} released ${vl(p.allocation)}');
  record(kind, id, p.allocation);
}
int compareLists(List<int> a, List<int> b) {
  for (int i = 0; i < a.length && i < b.length; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}
class Edge {
  final int destination, resource;
  Edge(this.destination, this.resource);
}
void graph(bool resources) {
  final m = state.total.length;
  if (resources && state.total.any((x) => x != 1)) fail('not single-instance');
  final Map<int, List<Edge>> edges = {for (final id in state.processes.keys) id: []};
  bool any = false;
  if (!resources) {
    for (final p in state.processes.values) {
      final req = requestOf(p.id);
      for (final q in state.processes.values) {
        if (p.id == q.id) continue;
        final List<String> labels = [];
        for (int i = 0; i < m; i++) { if (req[i] > state.available[i] && q.allocation[i] > 0) labels.add(type(i)); }
        if (labels.isNotEmpty) {
          edges[p.id]!.add(Edge(q.id, -1));
          emit('${pn(p.id)} -> ${pn(q.id)} on ${labels.join(',')}');
          any = true;
        }
      }
    }
    if (!any) emit('no wait edges');
  } else {
    final holders = List.filled(m, -1);
    for (final p in state.processes.values) {
      for (int i = 0; i < m; i++) { if (p.allocation[i] > 0) holders[i] = p.id; }
    }
    for (int i = 0; i < m; i++) { if (holders[i] >= 0) emit('assign ${type(i)} -> ${pn(holders[i])}'); }
    for (final p in state.processes.values) {
      final req = requestOf(p.id);
      for (int i = 0; i < m; i++) {
        if (req[i] > 0) {
          emit('request ${pn(p.id)} -> ${type(i)}');
          if (holders[i] >= 0) edges[p.id]!.add(Edge(holders[i], i));
        }
      }
    }
    for (final p in state.processes.values) {
      final req = requestOf(p.id), need = p.need();
      for (int i = 0; i < m; i++) { if (need[i] > 0 && req[i] == 0) emit('claim ${pn(p.id)} -> ${type(i)}'); }
    }
  }
  final List<(List<int>, String)> cycles = [];
  for (final start in state.processes.keys) {
    final Set<int> visited = {start};
    void search(int current, List<int> key, List<String> labels) {
      for (final edge in edges[current]!) {
        final next = edge.destination;
        if (next < start) continue;
        final nextKey = [...key, if (resources) edge.resource, next];
        final nextLabels = [...labels, if (resources) type(edge.resource), pn(next)];
        if (next == start) {
          if (resources || visited.length > 1) cycles.add((nextKey, 'cycle: ${nextLabels.join(' -> ')}'));
        } else if (!visited.contains(next)) {
          visited.add(next);
          search(next, nextKey, nextLabels);
          visited.remove(next);
        }
      }
    }
    search(start, [start], [pn(start)]);
  }
  cycles.sort((a, b) => compareLists(a.$1, b.$1));
  for (final cycle in cycles) { emit(cycle.$2); }
  if (cycles.isEmpty) emit('no cycles');
}
String table(List<int> v) => List.generate(v.length, (i) => v[i].toString().padLeft(state.total[i].toString().length)).join(' ');
void showState() {
  final names = List.generate(state.total.length, (i) => type(i).padLeft(state.total[i].toString().length)).join(' ');
  const headings = ['Allocation', 'Max', 'Need', 'Request'];
  final widths = headings.map((h) => h.length > names.length ? h.length : names.length).toList();
  void row(String heading, List<String> fields) {
    emit(heading.padRight(9) + List.generate(4, (i) => '  ${fields[i].padRight(widths[i])}').join());
  }
  row('Process', headings);
  row('', List.filled(4, names));
  for (final p in state.processes.values) { row(pn(p.id), [table(p.allocation), table(p.maximum), table(p.need()), table(requestOf(p.id))]); }
  row('Available', [table(state.available), '', '', '']);
  row('Total', [table(state.total), '', '', '']);
  emit('blocked queue: ${state.queue.isEmpty ? 'empty' : state.queue.map((w) => '${pn(w.id)} ${vl(w.vector)} since t=${w.since}').join(', ')}');
}
void stats() {
  for (int i = 0; i < state.total.length; i++) {
    final total = state.total[i], used = state.total[i] - state.available[i];
    int requested = 0;
    for (final w in state.queue) { requested += w.vector[i]; }
    final percent = used * 1000 ~/ total;
    emit('${type(i)}: allocated $used/$total (${percent ~/ 10}.${percent % 10}%), requested $requested');
  }
  emit('events: ${kinds.map((kind) => '$kind ${state.history.where((e) => e.kind == kind).length}').join(', ')}');
  final waits = state.history.where((e) => e.kind == 'unblocked').toList();
  if (waits.isEmpty) { emit('waits: none'); }
  else {
    int total = 0;
    for (final e in waits) { total += e.waited; }
    final average = total * 100 ~/ waits.length;
    emit('waits: ${waits.length} unblocked, total $total, average ${average ~/ 100}.${(average % 100).toString().padLeft(2, '0')}');
  }
}
void execute(List<String> w) {
  final c = w[0];
  if (['MODE', 'POLICY', 'TRACE', 'AUTODETECT'].contains(c)) {
    if (c == 'MODE') mode = w[1];
    if (c == 'POLICY') policy = w[1];
    if (c == 'TRACE') tracing = w[1] == 'ON';
    if (c == 'AUTODETECT') autodetect = w[1] == 'ON';
    emit('${c.toLowerCase()} ${w[1]}');
    return;
  }
  if (c == 'RESOURCES') { state = State(w.skip(1).map(int.parse).toList()); emit('resources ${vl(state.total)}'); return; }
  if (['PROCESS', 'CLAIM', 'REQUEST', 'WHATIF', 'RELEASE'].contains(c)) {
    final id = int.parse(w[1]), v = vector(w, 2), name = pn(int.parse(w[1]));
    if (c == 'PROCESS') {
      if (state.processes.containsKey(id)) fail('duplicate process $name');
      if (!fits(v, state.total)) fail('max exceeds total');
      state.processes[id] = Process(id, v, command, List.filled(v.length, 0));
      emit('process $name max ${vl(v)}');
      return;
    }
    final p = requireProcess(id, c == 'CLAIM' || c == 'RELEASE');
    if (c == 'CLAIM') {
      if (!fits(p.allocation, v)) fail('claim below allocation');
      if (!fits(v, state.total)) fail('max exceeds total');
      final old = p.maximum;
      p.maximum = v;
      final unsafe = mode == 'AVOID' && check(state.available, false, tracing).remaining.isNotEmpty;
      p.maximum = old;
      if (unsafe) fail('claim makes state unsafe');
      p.maximum = v;
      emit('claim $name max ${vl(v)}');
      retry();
      return;
    }
    if (c == 'RELEASE') {
      if (sum(v) == 0) fail('zero vector');
      if (!fits(v, p.allocation)) fail('release exceeds allocation');
      p.allocation = sub(p.allocation, v);
      state.available = add(state.available, v);
      emit('released $name ${vl(v)}');
      record('released', id, v);
      retry();
      return;
    }
    final reject = rejection(p, v), prefix = 'whatif $name ${vl(v)}';
    if (reject != null) {
      if (c == 'REQUEST') fail(reject);
      emit('$prefix: rejected ($reject)');
      return;
    }
    final d = decision(p, v, tracing);
    if (c == 'WHATIF') {
      if (d.reason != null) { emit('$prefix: blocked (${d.reason})'); }
      else { emit('$prefix: granted${mode == 'AVOID' ? ', safe sequence ${pl(d.sequence)}' : ''}'); }
    } else if (d.reason == null) {
      allocate(p, v);
      emit('granted $name ${vl(v)}');
      record('granted', id, v);
    } else {
      state.queue.add(Waiting(id, v, command));
      emit('blocked $name ${vl(v)}: ${d.reason}');
      record('blocked', id, v);
      if (autodetect) { final dead = detect(tracing); if (dead.isNotEmpty) emit('deadlock detected: ${pl(dead)}'); }
    }
    return;
  }
  if (c == 'ADD' || c == 'REMOVE') {
    final v = vector(w, 1);
    if (sum(v) == 0) fail('zero vector');
    if (c == 'ADD') {
      state.total = add(state.total, v);
      state.available = add(state.available, v);
      emit('added ${vl(v)} total ${vl(state.total)}');
      retry();
    } else {
      if (!fits(v, state.available)) fail('remove exceeds available');
      final total = sub(state.total, v), available = sub(state.available, v);
      if (total.contains(0)) fail('total must stay positive');
      if (state.processes.values.any((p) => !fits(p.maximum, total))) fail('max exceeds total');
      if (mode == 'AVOID' && check(available, false, tracing).remaining.isNotEmpty) fail('removal makes state unsafe');
      state.total = total;
      state.available = available;
      emit('removed ${vl(v)} total ${vl(total)}');
    }
    return;
  }
  switch (c) {
    case 'FINISH':
    case 'ABORT': {
      final id = int.parse(w[1]);
      requireProcess(id, c == 'FINISH');
      terminate(id, c == 'FINISH' ? 'finished' : 'aborted');
      retry();
    }
    case 'CANCEL': {
      final id = int.parse(w[1]);
      requireProcess(id);
      final entry = waiting(id);
      if (entry == null) fail('process ${pn(id)} is not blocked');
      state.queue.remove(entry);
      emit('cancelled ${pn(id)} ${vl(entry.vector)}');
      record('cancelled', id, entry.vector);
    }
    case 'MAXGRANT': {
      final id = int.parse(w[1]);
      final p = requireProcess(id, true);
      final result = List.filled(state.total.length, 0);
      for (int i = 0; i < result.length; i++) {
        final v = List.filled(result.length, 0);
        for (int amount = p.need()[i]; amount > 0; amount--) {
          v[i] = amount;
          if (rejection(p, v) == null && decision(p, v, false).reason == null) { result[i] = amount; break; }
        }
      }
      emit('maxgrant ${pn(id)}: ${vl(result)}');
    }
    case 'SAFE': {
      if (state.processes.isEmpty) { emit('safe: no processes'); }
      else { final r = check(state.available, false, tracing); emit(r.remaining.isEmpty ? 'safe: ${pl(r.sequence)}' : 'unsafe: ${pl(r.remaining)} cannot finish'); }
    }
    case 'SEQUENCES': {
      if (state.processes.isEmpty) { emit('safe sequences: no processes'); return; }
      final limit = int.parse(w[1]);
      int count = 0;
      final List<int> path = [];
      final List<String> found = [];
      void search(List<int> work) {
        if (path.length == state.processes.length) { count++; if (found.length < limit) found.add(pl(path)); return; }
        for (final p in state.processes.values) {
          if (!path.contains(p.id) && fits(p.need(), work)) {
            path.add(p.id);
            search(add(work, p.allocation));
            path.removeLast();
          }
        }
      }
      search(state.available);
      emit('safe sequences: $count');
      for (final line in found) { emit(line); }
    }
    case 'DEFICIT': {
      final List<String> results = [];
      for (int i = 0; i < state.total.length; i++) {
        int limit = 0;
        for (final p in state.processes.values) { limit += p.need()[i]; }
        String result = '-';
        for (int x = 0; x <= limit; x++) {
          final work = List.of(state.available);
          work[i] += x;
          if (check(work, false, false).remaining.isEmpty) { result = x.toString(); break; }
        }
        results.add(result);
      }
      emit('deficit: (${results.join(',')})');
    }
    case 'STATE': {
      showState();
    }
    case 'STATS': {
      stats();
    }
    case 'DETECT': {
      final dead = detect(tracing);
      emit(dead.isEmpty ? 'no deadlock' : 'deadlocked: ${pl(dead)}');
    }
    case 'VICTIMS': {
      final dead = detect(false);
      if (dead.isEmpty) { emit('no deadlock'); return; }
      final List<List<int>> groups = [];
      for (int mask = 1; mask < (1 << dead.length); mask++) {
        groups.add([for (int i = 0; i < dead.length; i++) if ((mask & (1 << i)) != 0) dead[i]]);
      }
      int held(List<int> ids) => ids.fold(0, (total, id) => total + sum(state.processes[id]!.allocation));
      groups.sort((a, b) {
        int result = a.length.compareTo(b.length);
        if (result == 0) result = held(a).compareTo(held(b));
        return result == 0 ? compareLists(a, b) : result;
      });
      for (final group in groups) {
        if (check(state.available, true, false, group.toSet()).remaining.isEmpty) { emit('victims: ${pl(group)}'); break; }
      }
    }
    case 'RECOVER': {
      List<int> dead = detect(tracing);
      int count = 0;
      if (w.length > 1) {
        for (final id in dead) { terminate(id, 'aborted'); count++; }
        if (count > 0) retry();
      } else {
        while (dead.isNotEmpty) {
          int victim = dead.first;
          for (final id in dead) {
            final a = state.processes[id]!, b = state.processes[victim]!;
            final better = policy == 'ALLOC'
                ? sum(a.allocation) < sum(b.allocation) || (sum(a.allocation) == sum(b.allocation) && id > victim)
                : policy == 'NEED'
                    ? sum(a.need()) > sum(b.need()) || (sum(a.need()) == sum(b.need()) && id > victim)
                    : a.created > b.created;
            if (better) victim = id;
          }
          terminate(victim, 'aborted');
          retry();
          count++;
          dead = detect(tracing);
        }
      }
      emit(count == 0 ? 'no deadlock' : 'recovered: $count aborted');
    }
    case 'WAITGRAPH': {
      graph(false);
    }
    case 'GRAPH': {
      graph(true);
    }
    case 'HISTORY': {
      bool any = false;
      for (final e in state.history) {
        if (w.length > 1 && !(int.tryParse(w[1]) != null ? e.id == int.parse(w[1]) : e.kind == w[1])) continue;
        emit('t=${e.command} ${e.kind} ${pn(e.id)} ${vl(e.vector)}${e.kind == 'unblocked' ? ' waited ${e.waited}' : ''}');
        any = true;
      }
      if (!any) emit('no events');
    }
    case 'SNAPSHOT': {
      snapshots[w[1]] = state.copy();
      emit('saved ${w[1]}');
    }
    case 'RESTORE': {
      final saved = snapshots[w[1]];
      if (saved == null) fail('unknown snapshot ${w[1]}');
      state = saved.copy();
      emit('restored ${w[1]}');
    }
  }
}
void main() {
  final n = int.parse(stdin.readLineSync()!);
  for (command = 1; command <= n; command++) {
    try { execute(stdin.readLineSync()!.split(' ')); }
    on CommandError catch (error) { emit('error: ${error.message}'); }
  }
  stdout.write(output);
}
