import 'dart:io';
import 'dart:math';
part 'config_io.dart';
part 'cache.dart';
part 'protocol.dart';
part 'bus.dart';
part 'stats.dart';

class Event {
  final int number, line, cycle, core, address, block, word;
  final String op;
  int distance = 0;
  Event(
    this.number,
    this.line,
    this.cycle,
    this.core,
    this.address,
    this.block,
    this.word,
    this.op,
  );
}

class Rejection {
  final int line;
  final String reason;
  Rejection(this.line, this.reason);
}

class Reuse {
  int accesses = 0, distinct = 0, cold = 0, opt = 0;
  final histogram = List.filled(6, 0), lru = List.filled(5, 0);
}

class Fenwick {
  final List<int> values;
  Fenwick(int n) : values = List.filled(n + 1, 0);
  void add(int i, int amount) {
    while (i < values.length) {
      values[i] += amount;
      i += i & -i;
    }
  }

  int sum(int i) {
    var value = 0;
    while (i > 0) {
      value += values[i];
      i -= i & -i;
    }
    return value;
  }
}

class NextUse {
  final int block, next;
  NextUse(this.block, this.next);
}

class OptQueue {
  final List<NextUse> values = [];
  bool before(NextUse a, NextUse b) =>
      a.next != b.next ? a.next > b.next : a.block < b.block;
  void push(NextUse v) {
    values.add(v);
    var i = values.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (!before(v, values[parent])) break;
      values[i] = values[parent];
      i = parent;
    }
    values[i] = v;
  }

  NextUse pop() {
    final first = values[0], last = values.removeLast();
    if (values.isNotEmpty) {
      var i = 0;
      while (2 * i + 1 < values.length) {
        var child = 2 * i + 1;
        if (child + 1 < values.length &&
            before(values[child + 1], values[child]))
          child++;
        if (!before(values[child], last)) break;
        values[i] = values[child];
        i = child;
      }
      values[i] = last;
    }
    return first;
  }
}

(List<Event>, List<Rejection>) validate(Config c, List<String> lines) {
  final events = <Event>[], rejects = <Rejection>[];
  var last = 0;
  for (var i = 0; i < lines.length; i++) {
    final a = lines[i].split(' ');
    var reason = '';
    if ((a.length != 3 && a.length != 4) || a.any((field) => field.isEmpty))
      reason = 'fields';
    if (reason.isEmpty && (!decimal(a[0]) || a[0].length > 7)) reason = 'cycle';
    if (reason.isEmpty && (!decimal(a[1]) || number(a[1]) >= c.n))
      reason = 'core';
    if (reason.isEmpty &&
        (!['R', 'W', 'FENCE'].contains(a[2]) ||
            a[2] == 'FENCE' && a.length != 3 ||
            a[2] != 'FENCE' && a.length != 4))
      reason = 'op';
    var addr = 0;
    if (reason.isEmpty && a[2] != 'FENCE') {
      if (!hexDigits(a[3])) {
        reason = 'address';
      } else {
        addr = hexNumber(a[3]);
        if (addr % 4 != 0 || addr > 0x7fffffff) reason = 'address';
      }
    }
    if (reason.isEmpty && number(a[0]) < last) reason = 'order';
    if (reason.isNotEmpty) {
      rejects.add(Rejection(i + 1, reason));
      continue;
    }
    last = number(a[0]);
    events.add(
      Event(
        events.length + 1,
        i + 1,
        last,
        number(a[1]),
        addr,
        addr ~/ c.line,
        addr % c.line ~/ 4,
        a[2],
      ),
    );
  }
  return (events, rejects);
}

List<Reuse> reuseAnalysis(Config c, List<Event> events) {
  final out = List.generate(c.n, (_) => Reuse()),
      capacity = c.l1Sets * c.l1Ways,
      sizes = [
        capacity ~/ 4,
        capacity ~/ 2,
        capacity,
        2 * capacity,
        4 * capacity,
      ];
  for (var core = 0; core < c.n; core++) {
    final ordered = [
          for (final e in events)
            if (e.core == core && e.op != 'FENCE') e,
        ],
        r = out[core],
        last = <int, int>{},
        fenwick = Fenwick(ordered.length);
    r.accesses = ordered.length;
    for (var i = 0; i < ordered.length; i++) {
      final e = ordered[i], position = i + 1, previous = last[e.block] ?? 0;
      if (previous == 0) {
        r.cold++;
        e.distance = 0;
      } else {
        e.distance = last.length - fenwick.sum(previous) + 1;
        fenwick.add(previous, -1);
        final index = e.distance == 1
            ? 0
            : e.distance <= 4
            ? 1
            : e.distance <= 16
            ? 2
            : e.distance <= 64
            ? 3
            : e.distance <= 256
            ? 4
            : 5;
        r.histogram[index]++;
      }
      for (var j = 0; j < 5; j++) {
        if (previous == 0 || e.distance > sizes[j]) r.lru[j]++;
      }
      fenwick.add(position, 1);
      last[e.block] = position;
    }
    r.distinct = last.length;
    final next = List.filled(ordered.length, 0), future = <int, int>{};
    for (var i = ordered.length - 1; i >= 0; i--) {
      final block = ordered[i].block;
      next[i] = future[block] ?? ordered.length + 1;
      future[block] = i;
    }
    final resident = <int, int>{}, queue = OptQueue();
    for (var i = 0; i < ordered.length; i++) {
      final e = ordered[i];
      if (!resident.containsKey(e.block)) {
        r.opt++;
        if (resident.length == capacity) {
          while (true) {
            final victim = queue.pop();
            if (resident[victim.block] == victim.next) {
              resident.remove(victim.block);
              break;
            }
          }
        }
      }
      resident[e.block] = next[i];
      queue.push(NextUse(e.block, next[i]));
    }
  }
  return out;
}

class Access {
  final Event event;
  final int issue, latency, miss, sharing;
  final bool hit;
  final String service;
  Access(
    this.event,
    this.issue,
    this.latency,
    this.miss,
    this.sharing,
    this.hit,
    this.service,
  );
}

class DynamicWord {
  final int writer;
  int readers = 0;
  DynamicWord(this.writer);
}

class WordSharing {
  int readers = 0, writers = 0;
}

class LineSharing {
  int cores = 0, writers = 0, reads = 0, writes = 0;
  final Map<int, WordSharing> words = {};
}

class Hot {
  final bus = List.filled(5, 0);
  int misses = 0, coherence = 0, invalidations = 0, cores = 0;
  int get transactions => bus.fold(0, (a, b) => a + b);
}

class Interval {
  final List<int> accesses;
  int misses = 0, transactions = 0, busy = 0;
  Interval(int n) : accesses = List.filled(n, 0);
}

class RegionStats {
  int accesses = 0,
      reads = 0,
      writes = 0,
      hits = 0,
      transactions = 0,
      latency = 0;
  final miss = List.filled(4, 0);
}

List<int> sortedIntKeys<T>(Map<int, T> a) => a.keys.toList()..sort();
Map<int, LineSharing> staticSharing(List<Event> events) {
  final out = <int, LineSharing>{};
  for (final e in events) {
    if (e.op == 'FENCE') continue;
    final line = out.putIfAbsent(e.block, () => LineSharing()),
        word = line.words.putIfAbsent(e.word, () => WordSharing());
    line.cores |= 1 << e.core;
    if (e.op == 'W') {
      line.writes++;
      line.writers |= 1 << e.core;
      word.writers |= 1 << e.core;
    } else {
      line.reads++;
      word.readers |= 1 << e.core;
    }
  }
  return out;
}

int popcount(int n) {
  var count = 0;
  while (n != 0) {
    n &= n - 1;
    count++;
  }
  return count;
}

class Simulator {
  final Config config;
  final Scenario scenario;
  final List<Cache> l1;
  final Cache l2;
  final bus = Bus();
  final List<CoreStats> cores;
  final List<int> ready, writes;
  final List<Map<int, int>> invalid;
  final List<Access> accesses = [];
  final List<String> watch = [];
  int lookups = 0,
      l2Hits = 0,
      l2Misses = 0,
      flushes = 0,
      writebacks = 0,
      evictions = 0,
      dirtyEvictions = 0,
      snoopHits = 0,
      readLatency = 0,
      writeLatency = 0;
  final List<int> fanout, histogram = List.filled(6, 0);
  final Map<int, int> handoffs = {}, lastWriter = {};
  final List<List<int>> communication;
  final Map<(int, int), DynamicWord> words = {};
  Simulator(this.config, this.scenario)
    : l1 = List.generate(
        config.n,
        (_) => Cache(config.l1Sets, config.l1Ways, scenario.l1),
      ),
      l2 = Cache(config.l2Sets, config.l2Ways, scenario.l2),
      cores = List.generate(config.n, (_) => CoreStats()),
      ready = List.filled(config.n, 0),
      writes = List.filled(config.n, 0),
      invalid = List.generate(config.n, (_) => <int, int>{}),
      fanout = List.filled(config.n, 0),
      communication = List.generate(config.n, (_) => List.filled(config.n, 0));
  String tuple(int block) =>
      '${[for (var core = 0; core < l1.length; core++) 'c$core:${l1[core].state(block)}'].join(' ')} L2:${l2.state(block)}';
  (int, String) transact(
    int core,
    int block,
    int word,
    String kind,
    int request,
  ) {
    final c = config,
        t = bus.assign(request, c.tb, Transaction(core, block, kind));
    cores[core].bus[busTypes.indexOf(kind)]++;
    if (kind == 'WB') {
      writebacks++;
      l2.hit(block);
      l2.change(block, 'D');
      bus.transactions.add(t);
      return (t.start + c.tb, '');
    }
    var supplier = -1, flushed = false;
    final snoops = <String>[];
    for (var k = 0; k < l1.length; k++) {
      if (k == core) continue;
      final cache = l1[k], state = cache.state(block);
      if (state == 'I') continue;
      final (next, supply, flush) = snoopTransition(
        scenario.protocol,
        state,
        kind,
      );
      t.hits++;
      snoops.add('c$k:$state>$next');
      if (next == 'I') {
        cache.remove(block);
        t.invalidations++;
        cores[core].invalidationsSent++;
        cores[k].invalidationsReceived++;
        invalid[k][block] = 1 << word;
      } else {
        cache.change(block, next);
      }
      if (supply) {
        supplier = k;
        cores[k].supplied++;
      }
      if (flush) flushed = true;
    }
    t.snoop = snoops.isEmpty ? 'none' : snoops.join(' ');
    snoopHits += t.hits;
    if (['BusRdX', 'BusUpgr', 'BusWr'].contains(kind))
      fanout[t.invalidations]++;
    var end = t.start + c.tb, service = 'upgrade';
    if (kind != 'BusUpgr') {
      lookups++;
      final hit = l2.state(block) != 'I';
      if (hit) {
        l2Hits++;
        l2.hit(block);
        t.l2 = 'hit';
      } else {
        l2Misses++;
        t.l2 = 'miss';
        final evicted = l2.fill(block, 'C');
        if (evicted.state.isNotEmpty) {
          evictions++;
          var isDirty = evicted.state == 'D';
          final backs = <String>[];
          for (var k = 0; k < l1.length; k++) {
            final cache = l1[k], state = cache.state(evicted.block);
            if (state == 'I') continue;
            backs.add('c$k:$state');
            if (dirty(state)) isDirty = true;
            cache.remove(evicted.block);
            cores[k].backInvalidations++;
          }
          if (isDirty) dirtyEvictions++;
          t.eviction =
              ' evict ${address(evicted.block * c.line)} ${backs.isEmpty ? 'none' : backs.join(' ')} ${isDirty ? 'dirty' : 'clean'}';
        }
      }
      if (flushed || kind == 'BusWr') l2.change(block, 'D');
      if (flushed) flushes++;
      if (kind == 'BusWr') {
        service = 'through';
        end += c.t2;
        if (!hit) end += c.tm;
      } else if (supplier >= 0) {
        service = 'cache';
        t.source = 'c$supplier';
      } else if (hit) {
        service = 'l2';
        t.source = 'L2';
        end += c.t2;
      } else {
        service = 'memory';
        t.source = 'mem';
        end += c.t2 + c.tm;
      }
    }
    bus.transactions.add(t);
    return (end, service);
  }

  void access(Event e, int issue) {
    final c = config,
        core = e.core,
        block = e.block,
        word = e.word,
        stats = cores[core];
    stats.accesses++;
    if (e.op == 'R') {
      stats.reads++;
    } else {
      stats.writes++;
    }
    final state = l1[core].state(block), hit = state != 'I';
    final (kind, desired) = requestTransition(scenario.protocol, state, e.op);
    var next = desired, miss = -1, sharing = -1;
    if (hit) {
      stats.hits++;
      l1[core].hit(block);
    } else {
      stats.misses++;
      if (e.distance == 0) {
        miss = 0;
      } else if ((invalid[core][block] ?? 0) != 0) {
        miss = 3;
        if (((invalid[core][block] ?? 0) & (1 << word)) != 0) {
          sharing = 0;
          stats.trueSharing++;
        } else {
          sharing = 1;
          stats.falseSharing++;
        }
      } else if (e.distance > c.l1Sets * c.l1Ways) {
        miss = 1;
      } else {
        miss = 2;
      }
      stats.miss[miss]++;
    }
    final before = <String>[];
    if (scenario.name == c.primary) {
      for (final watched in c.watch) {
        before.add(tuple(watched));
      }
      final key = (block, word);
      if (e.op == 'W') {
        final previous = lastWriter[block];
        if (previous != null && previous != core)
          handoffs[block] = (handoffs[block] ?? 0) + 1;
        lastWriter[block] = core;
        words[key] = DynamicWord(core);
      } else {
        final previous = words[key];
        if (previous != null &&
            previous.writer != core &&
            ((previous.readers >> core) & 1) == 0) {
          communication[previous.writer][core]++;
          previous.readers |= 1 << core;
        }
      }
    }
    if (e.op == 'W') {
      for (var k = 0; k < c.n; k++) {
        if (k != core && invalid[k].containsKey(block))
          invalid[k][block] = invalid[k][block]! | (1 << word);
      }
    }
    var end = issue + c.t1, service = 'l1';
    if (kind.isNotEmpty) {
      if (next == 'E/S') {
        next = 'E';
        for (var k = 0; k < l1.length; k++) {
          if (k != core && l1[k].state(block) != 'I') {
            next = 'S';
            break;
          }
        }
      }
      final (done, source) = transact(core, block, word, kind, issue + c.t1);
      end = done;
      service = source;
    }
    if (state != 'I') {
      l1[core].change(block, next);
    } else if (next != 'I') {
      final evicted = l1[core].fill(block, next);
      invalid[core].remove(block);
      if (evicted.state.isNotEmpty && dirty(evicted.state))
        transact(core, evicted.block, 0, 'WB', bus.free);
    }
    final latency = end - issue;
    stats.latency += latency;
    stats.service[serviceNames.indexOf(service)]++;
    stats.finish = max(stats.finish, end);
    if (e.op == 'R') {
      ready[core] = end;
      readLatency += latency;
    } else {
      ready[core] = issue + c.t1;
      writes[core] = max(writes[core], end);
      writeLatency += latency;
    }
    final bin = latency == 1
        ? 0
        : latency <= 9
        ? 1
        : latency <= 29
        ? 2
        : latency <= 99
        ? 3
        : latency <= 299
        ? 4
        : 5;
    histogram[bin]++;
    accesses.add(Access(e, issue, latency, miss, sharing, hit, service));
    if (scenario.name == c.primary) {
      for (var j = 0; j < c.watch.length; j++) {
        final watched = c.watch[j], after = tuple(watched);
        if (block == watched || after != before[j])
          watch.add(
            '${e.number} $issue c$core ${e.op} ${address(e.address)} line ${address(watched * c.line)} $after',
          );
      }
    }
  }

  void run(List<Event> events) {
    final ordered = List.generate(config.n, (_) => <Event>[]),
        at = List.filled(config.n, 0);
    for (final e in events) {
      ordered[e.core].add(e);
    }
    while (true) {
      var chosen = -1, issue = 0;
      for (var core = 0; core < ordered.length; core++) {
        final queue = ordered[core];
        if (at[core] == queue.length) continue;
        final next = max(queue[at[core]].cycle, ready[core]);
        if (chosen < 0 || next < issue) {
          chosen = core;
          issue = next;
        }
      }
      if (chosen < 0) break;
      final e = ordered[chosen][at[chosen]++];
      if (e.op == 'FENCE') {
        final end = max(issue, writes[chosen]), stats = cores[chosen];
        stats.fences++;
        stats.fenceStall += end - issue;
        stats.finish = max(stats.finish, end);
        ready[chosen] = end;
      } else {
        access(e, issue);
      }
    }
  }

  CoreStats total() {
    final out = CoreStats();
    for (final core in cores) {
      out.add(core);
    }
    return out;
  }

  List<String> statsLines() {
    final c = config,
        out = [
          'scenario ${scenario.name} ${scenario.protocol} ${scenario.l1} ${scenario.l2}',
        ];
    for (var k = 0; k < cores.length; k++) {
      out.addAll(cores[k].lines('c$k'));
    }
    final sum = total(), transactions = bus.transactions.length;
    out.addAll(sum.lines('total'));
    out.addAll([
      'l2 lookups $lookups hits $l2Hits misses $l2Misses flushes $flushes writebacks $writebacks evictions $evictions dirty_evictions $dirtyEvictions',
      'bus transactions $transactions busy ${bus.busy} wait ${bus.wait} utilization ${decimalRatio(100 * bus.busy, sum.finish)}',
      'traffic command_bytes ${8 * transactions} data_bytes ${c.line * (sum.bus[0] + sum.bus[1] + sum.bus[4]) + 4 * sum.bus[3]} memory_bytes ${c.line * (l2Misses + dirtyEvictions)}',
      'snoops probes ${(c.n - 1) * (transactions - sum.bus[4])} hits $snoopHits fanout ${rangeCounts([for (var i = 0; i < c.n; i++) '$i'], fanout)}',
      'latencies reads $readLatency writes $writeLatency histogram ${rangeCounts(['1', '2-9', '10-29', '30-99', '100-299', '300+'], histogram)}',
    ]);
    return out;
  }

  List<String> sharingLines(List<Event> events) {
    final lines = staticSharing(events),
        trueMiss = <int, int>{},
        falseMiss = <int, int>{};
    for (final a in accesses) {
      if (a.sharing == 0) {
        trueMiss[a.event.block] = (trueMiss[a.event.block] ?? 0) + 1;
      } else if (a.sharing == 1) {
        falseMiss[a.event.block] = (falseMiss[a.event.block] ?? 0) + 1;
      }
    }
    final out = <String>[];
    var count = 0, trueLines = 0, falseLines = 0, totalTrue = 0, totalFalse = 0;
    for (final block in sortedIntKeys(lines)) {
      final line = lines[block]!;
      if (popcount(line.cores) < 2 || line.writers == 0) continue;
      count++;
      var isTrue = false;
      final words = <String>[];
      for (final word in sortedIntKeys(line.words)) {
        final v = line.words[word]!;
        if (v.writers != 0 && popcount(v.readers | v.writers) >= 2)
          isTrue = true;
        words.add('w$word=${coreString(v.readers)}/${coreString(v.writers)}');
      }
      if (isTrue) {
        trueLines++;
      } else {
        falseLines++;
      }
      final t = trueMiss[block] ?? 0, f = falseMiss[block] ?? 0;
      totalTrue += t;
      totalFalse += f;
      out.add(
        '${address(block * config.line)} ${isTrue ? 'true' : 'false'} cores ${coreString(line.cores)} writers ${coreString(line.writers)} reads ${line.reads} writes ${line.writes} handoffs ${handoffs[block] ?? 0} coherence ${t + f} true $t false $f words ${words.join(' ')}',
      );
    }
    out.add(
      'lines $count true_lines $trueLines false_lines $falseLines coherence ${totalTrue + totalFalse} true $totalTrue false $totalFalse',
    );
    out.add('communication');
    for (var core = 0; core < communication.length; core++) {
      out.add('c$core ${communication[core].join(' ')}');
    }
    return out;
  }

  List<String> finalLines() {
    final out = <String>[];
    void cacheRows(String name, Cache cache) {
      for (var set = 0; set < cache.sets.length; set++) {
        final a = cache.sets[set],
            ways = [
              for (final way in a.ways)
                way.state.isEmpty
                    ? '-'
                    : '${address(way.block * config.line)}:${way.state}',
            ];
        out.add(
          '$name $set ${ways.join(' ')} ${cache.policy.toLowerCase()} ${cache.replacement(set)} fills ${a.fills} evictions ${a.evictions}',
        );
      }
    }

    for (var core = 0; core < l1.length; core++) {
      final name = 'c$core', cache = l1[core], counts = <String, int>{};
      cacheRows(name, cache);
      var total = 0;
      for (final set in cache.sets) {
        for (final way in set.ways) {
          if (way.state.isNotEmpty) {
            total++;
            counts[way.state] = (counts[way.state] ?? 0) + 1;
          }
        }
      }
      out.add(
        '$name lines $total M ${counts['M'] ?? 0} O ${counts['O'] ?? 0} E ${counts['E'] ?? 0} S ${counts['S'] ?? 0} V ${counts['V'] ?? 0}',
      );
    }
    cacheRows('L2', l2);
    var dirtyCount = 0, clean = 0, inL1 = 0;
    for (final set in l2.sets) {
      for (final way in set.ways) {
        if (way.state.isEmpty) continue;
        if (way.state == 'D') {
          dirtyCount++;
        } else {
          clean++;
        }
        if (l1.any((cache) => cache.state(way.block) != 'I')) inL1++;
      }
    }
    out.add(
      'L2 lines ${dirtyCount + clean} dirty $dirtyCount clean $clean in_l1 $inL1',
    );
    return out;
  }

  List<List<String>> detailLines() {
    final c = config, hot = <int, Hot>{};
    for (final t in bus.transactions) {
      final v = hot.putIfAbsent(t.block, () => Hot());
      v.bus[busTypes.indexOf(t.kind)]++;
      v.invalidations += t.invalidations;
      v.cores |= 1 << t.core;
    }
    for (final a in accesses) {
      final v = hot[a.event.block];
      if (v != null) {
        if (!a.hit) v.misses++;
        if (a.miss == 3) v.coherence++;
      }
    }
    final blocks = sortedIntKeys(hot)
          ..sort((a, b) {
            final difference = hot[b]!.transactions.compareTo(
              hot[a]!.transactions,
            );
            return difference != 0 ? difference : a.compareTo(b);
          }),
        hotLines = ['hot ${c.primary}'];
    for (var rank = 0; rank < min(c.top, blocks.length); rank++) {
      final block = blocks[rank], v = hot[block]!;
      hotLines.add(
        '${rank + 1} ${address(block * c.line)} transactions ${v.transactions} ${namedCounts(busTypes, v.bus)} misses ${v.misses} coherence ${v.coherence} invalidations ${v.invalidations} cores ${coreString(v.cores)}',
      );
    }
    final count = total().finish ~/ c.interval + 1,
        intervals = List.generate(count, (_) => Interval(c.n));
    for (final a in accesses) {
      final v = intervals[a.issue ~/ c.interval];
      v.accesses[a.event.core]++;
      if (!a.hit) v.misses++;
    }
    for (final t in bus.transactions) {
      final index = t.start ~/ c.interval;
      if (index < count) intervals[index].transactions++;
      for (
        var i = index;
        i < count && i <= (t.start + c.tb - 1) ~/ c.interval;
        i++
      ) {
        final first = max(t.start, i * c.interval),
            last = min(t.start + c.tb, (i + 1) * c.interval);
        intervals[i].busy += last - first;
      }
    }
    final intervalLines = ['intervals ${c.primary} ${c.interval}'];
    for (var i = 0; i < count; i++) {
      final v = intervals[i];
      intervalLines.add(
        '$i ${i * c.interval}-${(i + 1) * c.interval - 1} accesses ${v.accesses.join(' ')} misses ${v.misses} transactions ${v.transactions} busy ${v.busy} utilization ${decimalRatio(100 * v.busy, c.interval)}',
      );
    }
    final ordered = List<Access>.of(accesses)
          ..sort((a, b) {
            final difference = b.latency.compareTo(a.latency);
            return difference != 0
                ? difference
                : a.event.number.compareTo(b.event.number);
          }),
        slow = ['slowest ${c.primary}'];
    for (var i = 0; i < min(c.top, ordered.length); i++) {
      final a = ordered[i], e = a.event;
      slow.add(
        '${i + 1} event ${e.number} cycle ${a.issue} c${e.core} ${e.op} ${address(e.address)} latency ${a.latency} service ${a.service}',
      );
    }
    final regionCounts = List.generate(
      c.regions.length + 1,
      (_) => RegionStats(),
    );
    int regionIndex(int address) {
      for (var i = 0; i < c.regions.length; i++) {
        final r = c.regions[i];
        if (r.first <= address && address <= r.last) return i;
      }
      return c.regions.length;
    }

    for (final a in accesses) {
      final v = regionCounts[regionIndex(a.event.address)];
      v.accesses++;
      if (a.event.op == 'R') {
        v.reads++;
      } else {
        v.writes++;
      }
      if (a.hit) {
        v.hits++;
      } else {
        v.miss[a.miss]++;
      }
      v.latency += a.latency;
    }
    for (final t in bus.transactions) {
      regionCounts[regionIndex(t.block * c.line)].transactions++;
    }
    final regions = ['regions ${c.primary}'];
    for (var i = 0; i < regionCounts.length; i++) {
      final v = regionCounts[i],
          name = i < c.regions.length ? c.regions[i].name : 'other',
          amat = v.accesses == 0
              ? '-'
              : '${fraction(v.latency, v.accesses)} ${decimalRatio(v.latency, v.accesses)}';
      regions.add(
        '$name accesses ${v.accesses} reads ${v.reads} writes ${v.writes} hits ${v.hits} ${namedCounts(missNames, v.miss)} transactions ${v.transactions} latency ${v.latency} amat $amat',
      );
    }
    return [hotLines, intervalLines, slow, regions];
  }
}

void main() {
  final c = readConfig(), raw = readLines('input/trace.txt');
  final (events, rejects) = validate(c, raw);
  final reuse = reuseAnalysis(c, events),
      first = [
        'trace lines ${raw.length} accepted ${events.length} rejected ${rejects.length}',
        for (final r in rejects) 'reject line ${r.line} ${r.reason}',
        'geometry cores ${c.n} line ${c.line} l1 ${c.l1Size} ${c.l1Ways} sets ${c.l1Sets} l2 ${c.l2Size} ${c.l2Ways} sets ${c.l2Sets}',
        'latency l1 ${c.t1} l2 ${c.t2} memory ${c.tm} bus ${c.tb}',
      ],
      reuseLines = <String>[],
      cap = c.l1Sets * c.l1Ways,
      sizes = [cap ~/ 4, cap ~/ 2, cap, 2 * cap, 4 * cap];
  for (var core = 0; core < reuse.length; core++) {
    final r = reuse[core];
    reuseLines.add(
      'reuse c$core accesses ${r.accesses} lines ${r.distinct} distance ${rangeCounts(['1', '2-4', '5-16', '17-64', '65-256', '257+'], r.histogram)} cold ${r.cold}',
    );
    reuseLines.add(
      'mrc c$core lru ${[for (var j = 0; j < 5; j++) '${sizes[j]}:${r.lru[j]}'].join(' ')} opt $cap:${r.opt}',
    );
  }
  final sections = [first, reuseLines], simulations = <Simulator>[];
  Simulator? primary;
  for (final scenario in c.scenarios) {
    final s = Simulator(c, scenario);
    s.run(events);
    simulations.add(s);
    sections.add(s.statsLines());
    if (scenario.name == c.primary) primary = s;
  }
  final ranking = List<Simulator>.of(simulations)
        ..sort((a, b) {
          var order = a.total().finish.compareTo(b.total().finish);
          if (order != 0) return order;
          order = a.bus.transactions.length.compareTo(
            b.bus.transactions.length,
          );
          return order != 0
              ? order
              : a.scenario.order.compareTo(b.scenario.order);
        }),
      rankLines = ['ranking'];
  for (var i = 0; i < ranking.length; i++) {
    final s = ranking[i], t = s.total();
    rankLines.add(
      '${i + 1} ${s.scenario.name} finish ${t.finish} transactions ${s.bus.transactions.length} amat ${fraction(t.latency, t.accesses)} ${decimalRatio(t.latency, t.accesses)}',
    );
  }
  final detail = primary!;
  sections.add(rankLines);
  sections.addAll(detail.detailLines());
  final stats = <String>[];
  for (var i = 0; i < sections.length; i++) {
    if (i > 0) stats.add('');
    stats.addAll(sections[i]);
  }
  Directory('output').createSync(recursive: true);
  writeLines('stats.txt', stats);
  writeLines('bus_log.txt', [
    for (final t in detail.bus.transactions) t.text(c.line),
  ]);
  writeLines('watch.txt', detail.watch);
  writeLines('sharing.txt', detail.sharingLines(events));
  writeLines('final_state.txt', detail.finalLines());
}
