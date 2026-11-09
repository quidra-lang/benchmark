import 'dart:io';
import 'dart:math';
const algorithms = ['FCFS', 'SJF', 'SRTF', 'RR', 'PRIORITY', 'HRRN', 'EDF', 'LOTTERY', 'MLFQ'];
const keys = ['cs', 'q', 'k', 's', 'seed'];
const metrics = ['turnaround', 'waiting', 'response'];
const eventKinds = ['PREEMPT', 'EXPIRE', 'DEMOTE', 'BOOST', 'AGE'];
const ranges = {
  'cs': (0, 5), 'q': (1, 20), 'k': (1, 50), 's': (0, 500), 'seed': (1, 2147483646)
};
class Failure implements Exception {
  final String message;
  Failure(this.message);
}
void check(bool bad, String message) {
  if (bad) throw Failure(message);
}
String ratio(int u, int v) {
  final n = u * 100 ~/ v;
  return '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
}
List<String> allowed(String a) => switch (a) {
  'RR' => ['cs', 'q'], 'PRIORITY' => ['cs', 'k'], 'MLFQ' => ['cs', 's'], 'LOTTERY' => ['cs', 'q', 'seed'], _ => ['cs']
};
bool valid(String k, int v) {
  final r = ranges[k]!;
  return v >= r.$1 && v <= r.$2;
}
Map<String, int> parameters(List<String> words, String? algo, [String? preset]) {
  final p = {
    'cs': 0, 'q': 4, 'k': 5, 's': 0, 'seed': 1
  }, seen = <String>{
  };
  if (preset != null) seen.add(preset);
  for (final word in words) {
    final parts = word.split('=');
    final k = parts[0], v = int.parse(parts[1]);
    check(!keys.contains(k), 'unknown key $k');
    check(algo != null && !allowed(algo).contains(k), 'key $k not allowed for $algo');
    check(seen.contains(k), 'duplicate key $k');
    check(!valid(k, v), 'invalid $k');
    seen.add(k);
    p[k] = v;
  }
  return p;
}
String notation(Map<String, int> p, [String? algo]) => (algo == null ? keys : allowed(algo)).map((k) => '$k=${p[k]}').join(' ');
class RandomState {
  int x;
  RandomState(this.x);
  int draw(int n) {
    x = 48271 * x % 2147483647;
    return x % n;
  }
}
class Process {
  final String id;
  final int arrival;
  int priority, deadline = 0;
  final List<int> bursts;
  Process(this.id, this.arrival, this.priority, this.bursts);
  int get absolute => deadline == 0 ? 2147483647 : arrival + deadline;
  String get describe {
    final bs = <String>[];
    for (int i = 0; i < bursts.length; i++) {
      bs.add('${i % 2 == 0 ? 'C' : 'I'}${bursts[i]}');
    }
    return '$id arrival=$arrival priority=$priority deadline=${deadline == 0 ? 'none' : deadline} bursts=${bs.join(',')}';
  }
}
class Burst {
  final int length, ready;
  int start = -1, end = 0, slices = 0;
  Burst(this.length, this.ready);
}
class Job {
  final Process p;
  String state = 'FUTURE';
  int burst = 0, left, effective, wait = 0, level = 0, used = 0, enqueued = 0, start = -1, finish = 0;
  final List<Burst> records = [];
  final StringBuffer timeline = StringBuffer();
  Job(this.p) : left = p.bursts[0], effective = p.priority;
  String get id => p.id;
  void advance() {
    left = p.bursts[++burst];
  }
  int get slices => records.fold(0, (n, b) => n + b.slices);
  List<int> get values {
    final turn = finish - p.arrival;
    return [turn, turn - p.bursts.fold<int>(0, (n, b) => n + b), start - p.arrival];
  }
  bool get missed => p.deadline > 0 && finish > p.absolute;
}
class Simulation {
  final String algo;
  final Map<String, int> p;
  final int snapshotTime;
  late final List<Job> jobs;
  final List<List<Job>> queues = [[], [], []];
  String cpu = 'IDLE';
  Job? current, previous;
  int time = 0, switchLeft = 0, runLength = 0, switches = 0;
  late final RandomState random;
  final List<String> events = [], labels = [], cpuStates = [];
  List<String>? snapshot;
  final Map<String, int> counts = {};
  final List<int> lengths = [];
  Simulation(Iterable<Process> processes, this.algo, this.p, [this.snapshotTime = -1]) {
    final sorted = processes.toList()..sort((a, b) => a.id.compareTo(b.id));
    jobs = sorted.map(Job.new).toList();
    random = RandomState(p['seed']!);
    run();
  }
  void event(String kind, [List<Object> details = const []]) {
    events.add([time, kind, ...details].join(' '));
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  void enqueue(Job j) {
    j.state = 'READY';
    j.enqueued = time;
    queues[algo == 'MLFQ' ? j.level : 0].add(j);
  }
  void release() {
    cpu = 'IDLE';
    current = null;
  }
  void start(Job j) {
    current = j;
    cpu = j.state = 'RUN';
    runLength = 0;
    if (j.start < 0) j.start = time;
    if (j.records.last.start < 0) j.records.last.start = time;
  }
  bool preempts(Job j) => switch (algo) {
    'SRTF' => queues[0].any((o) => o.left < j.left),
    'PRIORITY' => queues[0].any((o) => o.effective < j.effective),
    'EDF' => queues[0].any((o) => o.p.absolute < j.p.absolute),
    'MLFQ' => queues.take(j.level).any((q) => q.isNotEmpty),
    _ => false,
  };
  Job choose(List<Job> q) {
    Job best = q.first;
    if (algo == 'LOTTERY') {
      int r = random.draw(q.fold<int>(0, (n, j) => n + 10 - j.p.priority));
      for (final j in q) {
        r -= 10 - j.p.priority;
        if (r < 0) return j;
      }
    }
    for (final j in q) {
      final better = switch (algo) {
        'SJF' || 'SRTF' => j.left < best.left,
        'PRIORITY' => j.effective < best.effective,
        'EDF' => j.p.absolute < best.p.absolute,
        'HRRN' => (time - j.enqueued + j.left) * best.left > (time - best.enqueued + best.left) * j.left,
        _ => false,
      };
      if (better) best = j;
    }
    return best;
  }
  void run() {
    while (true) {
      if (algo == 'PRIORITY') {
        for (final j in queues[0]) {
          j.wait++;
          if (j.wait == p['k']) {
            j.wait = 0;
            if (j.effective > 0) {
              j.effective--;
              event('AGE', [j.id, j.effective]);
            }
          }
        }
      }
      for (final j in jobs) {
        if (j.state == 'IO' && j.left == 0) {
          j.advance();
          j.records.add(Burst(j.left, time));
          enqueue(j);
          event('IODONE', [j.id]);
        }
      }
      for (final j in jobs) {
        if (j.state == 'FUTURE' && j.p.arrival == time) {
          j.records.add(Burst(j.left, time));
          enqueue(j);
          event('ARRIVE', [j.id]);
        }
      }
      if (cpu == 'SWITCH' && switchLeft == 0) {
        start(current!);
        event('START', [current!.id]);
      }
      else if (cpu == 'RUN') {
        final j = current!;
        if (j.left == 0 && j.burst == j.p.bursts.length - 1) {
          j.state = 'DONE';
          j.finish = time;
          event('DONE', [j.id]);
          release();
        }
        else {
          final demoted = algo == 'MLFQ' && j.level < 2 && j.used == (j.level == 0 ? 4 : 8);
          if (demoted) {
            j.level++;
            j.used = 0;
            event('DEMOTE', [j.id, j.level]);
          }
          if (j.left == 0) {
            j.advance();
            j.state = 'IO';
            event('IO', [j.id, j.left]);
            release();
          }
          else if (demoted) {
            enqueue(j);
            release();
          }
          else if ((algo == 'RR' || algo == 'LOTTERY') && runLength == p['q']) {
            enqueue(j);
            event('EXPIRE', [j.id]);
            release();
          }
          else if (preempts(j)) {
            enqueue(j);
            event('PREEMPT', [j.id]);
            release();
          }
        }
      }
      if (jobs.every((j) => j.state == 'DONE')) break;
      if (algo == 'MLFQ' && p['s']! > 0 && time > 0 && time % p['s']! == 0) {
        queues[0].addAll(queues[1]);
        queues[0].addAll(queues[2]);
        queues[1].clear();
        queues[2].clear();
        for (final j in jobs) {
          j.level = 0;
          j.used = 0;
        }
        event('BOOST');
      }
      if (cpu == 'IDLE') {
        List<Job>? q;
        for (final candidate in queues) {
          if (candidate.isNotEmpty) {
            q = candidate;
            break;
          }
        }
        if (q != null) {
          final j = algo == 'MLFQ' ? q.first : choose(q);
          q.remove(j);
          j.effective = j.p.priority;
          j.wait = 0;
          j.records.last.slices++;
          final switched = j != previous;
          if (switched) switches++;
          if (switched && p['cs']! > 0) {
            current = j;
            cpu = j.state = 'SWITCH';
            switchLeft = p['cs']!;
            event('SWITCH', [j.id]);
          }
          else {
            start(j);
            event('DISPATCH', [j.id]);
          }
        }
      }
      if (time == snapshotTime) capture();
      for (final j in jobs) {
        j.timeline.write(switch (j.state) {
          'READY' => '.', 'SWITCH' => 's', 'RUN' => '#', 'IO' => 'i', _ => '-'
        });
      }
      lengths.add(queues.fold(0, (n, q) => n + q.length));
      cpuStates.add(cpu);
      if (cpu == 'RUN') {
        final j = current!;
        j.left--;
        j.used++;
        runLength++;
        previous = j;
        labels.add(j.id);
        if (j.left == 0) j.records.last.end = time + 1;
      }
      else if (cpu == 'SWITCH') {
        switchLeft--;
        labels.add('CS');
      } else {
        labels.add('IDLE');
      }
      for (final j in jobs) {
        if (j.state == 'IO') j.left--;
      }
      time++;
    }
    if (snapshot == null) capture();
  }
  void capture() {
    final lines = <String>['CPU $cpu${current == null ? '' : ' ${current!.id}'}'];
    for (int i = 0; i < (algo == 'MLFQ' ? 3 : 1); i++) {
      final q = queues[i];
      lines.add('QUEUE${algo == 'MLFQ' ? i : ''} ${q.isEmpty ? 'none' : q.map((j) => j.id).join(' ')}');
    }
    for (final j in jobs) {
      String s = '${j.id} ${j.state}';
      if (j.state == 'FUTURE') {
        s += ' at=${j.p.arrival}';
      }
      else if (j.state == 'DONE') {
        s += ' at=${j.finish}';
      }
      else {
        s += ' burst=${j.burst + 1} left=${j.left}';
        if (algo == 'PRIORITY') s += ' prio=${j.effective}';
        if (algo == 'MLFQ') s += ' level=${j.level} used=${j.used}';
      }
      lines.add(s);
    }
    snapshot = lines;
  }
  List<int> get totals => List.generate(3, (i) => jobs.fold<int>(0, (n, j) => n + j.values[i]));
  String get averages {
    final t = totals;
    return 'turnaround=${ratio(t[0], jobs.length)} waiting=${ratio(t[1], jobs.length)} response=${ratio(t[2], jobs.length)}';
  }
  List<int> ticks(int a, int b) => ['RUN', 'SWITCH', 'IDLE'].map((state) => cpuStates.sublist(a, b).where((s) => s == state).length).toList();
  String get util => ratio(ticks(0, time)[0] * 100, time);
  int get missed => jobs.where((j) => j.missed).length;
  int get met => jobs.where((j) => j.p.deadline > 0 && !j.missed).length;
}
class Scheduler {
  final Map<String, Process> registry = {};
  final StringBuffer output = StringBuffer();
  void emit(String s) => output.writeln(s);
  Process process(String id) {
    check(!registry.containsKey(id), 'unknown process $id');
    return registry[id]!;
  }
  void algorithm(String algo) => check(!algorithms.contains(algo), 'unknown algorithm $algo');
  Map<String, int> prepare(List<String> words, [String? algo, String? preset]) {
    final p = parameters(words, algo, preset);
    check(registry.isEmpty, 'no processes');
    return p;
  }
  Simulation sim(String algo, Map<String, int> p) => Simulation(registry.values, algo, p);
  String table(List<String> cells) => cells.first.padRight(8) + cells.skip(1).map((s) => ' ${s.padLeft(8)}').join();
  void execute(String line) {
    final a = line.split(' '), c = line.split(' ')[0];
    try {
      switch (c) {
        case 'PROC': {
          final id = a[1];
          check(registry.containsKey(id), 'duplicate process $id');
          check(registry.length == 10, 'too many processes');
          final arrival = int.parse(a[2]), priority = int.parse(a[3]);
          check(arrival > 200, 'invalid arrival $id');
          check(priority > 9, 'invalid priority $id');
          final words = a.sublist(4), bursts = <int>[];
          check(words.length % 2 == 0, 'invalid bursts $id');
          int cpu = 0, io = 0;
          for (int i = 0; i < words.length; i++) {
            final word = words[i], n = int.parse(words[i].substring(1));
            check(word[0] != (i % 2 == 0 ? 'C' : 'I') || n < 1 || n > 30, 'invalid bursts $id');
            bursts.add(n);
            if (i % 2 == 0) {
              cpu += n;
            } else {
              io += n;
            }
          }
          registry[id] = Process(id, arrival, priority, bursts);
          emit('PROC $id cpu=$cpu io=$io');
        }
        case 'GEN': {
          final n = int.parse(a[2]);
          for (int i = 1; i <= n; i++) {
            check(registry.containsKey('${a[1]}$i'), 'duplicate process ${a[1]}$i');
          }
          check(registry.length + n > 10, 'too many processes');
          emit('GEN count=$n');
          final random = RandomState(int.parse(a[3]));
          for (int i = 1; i <= n; i++) {
            final arrival = random.draw(21), priority = random.draw(10), m = 1 + random.draw(3), bursts = <int>[];
            for (int j = 0; j < m; j++) {
              if (j > 0) bursts.add(1 + random.draw(8));
              bursts.add(1 + random.draw(9));
            }
            final p = Process('${a[1]}$i', arrival, priority, bursts);
            registry[p.id] = p;
            emit(p.describe);
          }
        }
        case 'SETPRIO': {
          final p = process(a[1]), v = int.parse(a[2]);
          check(v > 9, 'invalid priority ${p.id}');
          p.priority = v;
          emit('SETPRIO ${p.id} priority=$v');
        }
        case 'DEADLINE': {
          final p = process(a[1]), v = int.parse(a[2]);
          check(v > 1000, 'invalid deadline ${p.id}');
          p.deadline = v;
          emit('DEADLINE ${p.id} ${v == 0 ? 'none' : v}');
        }
        case 'DROP': {
          final p = process(a[1]);
          registry.remove(p.id);
          emit('DROP ${p.id}');
        }
        case 'CLEAR': {
          final n = registry.length;
          registry.clear();
          emit('CLEAR count=$n');
        }
        case 'LIST': {
          emit('LIST count=${registry.length}');
          final ids = registry.keys.toList()..sort();
          for (final id in ids) {
            emit(registry[id]!.describe);
          }
        }
        default: {
          simulationCommand(c, a);
        }
      }
    }
    on Failure catch (e) {
      emit('ERROR ${e.message}');
    }
  }
  void simulationCommand(String c, List<String> a) {
    if (c == 'COMPARE' || c == 'RANK') {
      final metric = c == 'RANK' ? a[1] : null;
      if (metric != null) check(![...metrics, 'end', 'switches', 'missed'].contains(metric), 'unknown metric $metric');
      final p = prepare(a.sublist(metric == null ? 1 : 2)), sims = <Simulation>[];
      for (final algo in algorithms) {
        sims.add(sim(algo, p));
      }
      if (metric == null) {
        emit('COMPARE ${notation(p)}');
        emit(table(['ALGO', 'TURN', 'WAIT', 'RESP', 'UTIL', 'END', 'SWITCH', 'MISS']));
        for (final s in sims) {
          emit(table([s.algo, ...s.totals.map((v) => ratio(v, s.jobs.length)), s.util, '${s.time}', '${s.switches}', '${s.missed}']));
        }
        final best = <String>[];
        for (int i = 0; i < 3; i++) {
          int winner = 0;
          for (int j = 1; j < sims.length; j++) {
            if (sims[j].totals[i] < sims[winner].totals[i]) winner = j;
          }
          best.add('${metrics[i]}=${algorithms[winner]}');
        }
        emit('BEST ${best.join(' ')}');
      } else {
        emit('RANK $metric ${notation(p)}');
        final index = metrics.indexOf(metric);
        final values = sims.map((s) => index >= 0 ? s.totals[index] : metric == 'end' ? s.time : metric == 'switches' ? s.switches : s.missed).toList();
        final indices = List.generate(9, (i) => i)..sort((a, b) {
          final r = values[a].compareTo(values[b]);
          return r == 0 ? a.compareTo(b) : r;
        });
        for (final i in indices) {
          final value = values[i], rank = 1 + values.where((v) => v < values[i]).length;
          emit('$rank ${algorithms[i]} ${index >= 0 ? ratio(value, registry.length) : value}');
        }
      }
      return;
    }
    final algo = a[1];
    algorithm(algo);
    if (c == 'DIFF') {
      final second = a[2];
      algorithm(second);
      final p = prepare(a.sublist(3));
      final one = sim(algo, p);
      final two = sim(second, p);
      emit('DIFF $algo $second ${notation(p)}');
      int win = 0, loss = 0, ties = 0;
      for (int i = 0; i < one.jobs.length; i++) {
        final j = one.jobs[i], x = one.jobs[i].values, y = two.jobs[i].values;
        emit('${j.id} turnaround=${x[0]}/${y[0]} waiting=${x[1]}/${y[1]} response=${x[2]}/${y[2]}');
        if (x[0] < y[0]) {
          win++;
        } else if (x[0] > y[0]) {
          loss++;
        } else {
          ties++;
        }
      }
      emit('WINS $algo=$win $second=$loss ties=$ties');
      return;
    }
    if (c == 'SWEEP') {
      final key = a[2];
      check(!keys.contains(key), 'unknown key $key');
      check(!allowed(algo).contains(key), 'key $key not allowed for $algo');
      final lo = int.parse(a[3]), hi = int.parse(a[4]);
      check(lo > hi || !valid(key, lo) || !valid(key, hi) || hi - lo > 20, 'invalid range');
      final p = prepare(a.sublist(5), algo, key);
      emit('SWEEP $algo $key $lo $hi');
      int best = lo;
      int? total;
      for (int v = lo; v <= hi; v++) {
        p[key] = v;
        final s = sim(algo, p);
        emit('${notation(p, algo)} ${s.averages} util=${s.util} end=${s.time} switches=${s.switches}');
        if (total == null || s.totals[1] < total) {
          total = s.totals[1];
          best = v;
        }
      }
      emit('BEST $key=$best');
      return;
    }
    final extra = c == 'WINDOW' || c == 'SNAPSHOT' ? int.parse(a[2]) : 0;
    if (c == 'WINDOW') check(extra < 1 || extra > 1000, 'invalid window');
    final p = prepare(a.sublist(c == 'WINDOW' || c == 'SNAPSHOT' ? 3 : 2), algo);
    final s = Simulation(registry.values, algo, p, c == 'SNAPSHOT' ? extra : -1), header = '$c $algo ${notation(p, algo)}';
    switch (c) {
      case 'TRACE': {
        emit(header);
        for (final event in s.events) {
          emit(event);
        }
        emit('END ${s.time}');
      }
      case 'TIMELINE': {
        check(s.time > 100, 'too long ${s.time}');
        emit('$header end=${s.time}');
        for (final j in s.jobs) {
          emit('${j.id.padRight(8)} ${j.timeline}');
        }
      }
      case 'SNAPSHOT': {
        emit('$header t=$extra');
        for (final row in s.snapshot!) {
          emit(row);
        }
      }
      case 'BURSTS': {
        emit(header);
        for (final j in s.jobs) {
          for (int i = 0; i < j.records.length; i++) {
            final b = j.records[i];
            emit('${j.id} #${i + 1} len=${b.length} ready=${b.ready} start=${b.start} end=${b.end} wait=${b.end - b.ready - b.length} slices=${b.slices}');
          }
        }
      }
      case 'WINDOW': {
        emit('$header width=$extra');
        for (int start = 0; start < s.time; start += extra) {
          final end = min(start + extra, s.time), t = s.ticks(start, min(start + extra, s.time)), counts = <String, int>{
          };
          for (int i = start; i < end; i++) {
            if (s.cpuStates[i] == 'RUN') counts[s.labels[i]] = (counts[s.labels[i]] ?? 0) + 1;
          }
          final ids = counts.keys.toList()..sort();
          String top = 'none';
          int best = 0;
          for (final id in ids) {
            if (counts[id]! > best) {
              top = id;
              best = counts[id]!;
            }
          }
          emit('$start-$end busy=${t[0]} switch=${t[1]} idle=${t[2]} util=${ratio(t[0] * 100, end - start)} top=$top');
        }
      }
      case 'STATS': {
        emit(header);
        for (int i = 0; i < 3; i++) {
          final values = s.jobs.map((j) => j.values[i]).toList(), sorted = s.jobs.map((j) => j.values[i]).toList()..sort();
          final low = sorted.first, high = sorted.last, n = sorted.length;
          final doubled = sorted[n ~/ 2] + sorted[(n - 1) ~/ 2];
          emit('${metrics[i]} min=$low (${s.jobs[values.indexOf(low)].id}) max=$high (${s.jobs[values.indexOf(high)].id}) median=${doubled ~/ 2}.${doubled % 2 == 0 ? 0 : 5} total=${s.totals[i]}');
        }
      }
      case 'RUN': {
        emit(header);
        final segments = <String>[];
        int start = 0;
        for (int t = 1; t <= s.time; t++) {
          if (t == s.time || s.labels[t] != s.labels[start]) {
            segments.add('[$start-$t ${s.labels[start]}]');
            start = t;
          }
        }
        for (int i = 0; i < segments.length; i += 8) {
          emit('GANTT ${segments.sublist(i, min(i + 8, segments.length)).join()}');
        }
        for (final j in s.jobs) {
          final m = j.values;
          emit('${j.id} arrival=${j.p.arrival} done=${j.finish} turnaround=${m[0]} waiting=${m[1]} response=${m[2]} slices=${j.slices}${j.p.deadline == 0 ? '' : ' deadline=${j.p.absolute} late=${max(0, j.finish - j.p.absolute)}'}');
        }
        emit('AVERAGE ${s.averages}');
        final t = s.ticks(0, s.time);
        emit('CPU end=${s.time} busy=${t[0]} switch=${t[1]} idle=${t[2]} switches=${s.switches} util=${s.util}');
        emit('QUEUE max=${s.lengths.reduce(max)} avg=${ratio(s.lengths.fold<int>(0, (n, x) => n + x), s.time)}');
        emit('EVENTS ${eventKinds.map((e) => '${e.toLowerCase()}=${s.counts[e] ?? 0}').join(' ')}');
        emit('DEADLINE met=${s.met} missed=${s.missed}');
      }
    }
  }
}
void main() {
  final s = Scheduler(), n = int.parse(stdin.readLineSync()!);
  for (int i = 0; i < n; i++) {
    s.execute(stdin.readLineSync()!);
  }
  stdout.write(s.output);
}
