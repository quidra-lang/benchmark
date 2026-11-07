import 'dart:io';
import 'dart:math';

part 'eventlog.dart';
part 'dfg.dart';
part 'alpha_miner.dart';
part 'heuristic_miner.dart';
part 'conformance.dart';
part 'report.dart';

class Variant {
  final List<String> trace;
  final List<Case> cases = [];
  bool keep = true;
  Variant(this.trace);
}

class Discovery {
  late Net net;
  final List<String> names;
  final String Function(String, String) relation;
  final List<Masks> pairs = [];
  int candidates = 0, causal = 0;
  final Map<String, List<String>> loopBefore = {}, loopAfter = {};
  final Map<String, String> loopPlace = {};
  Discovery(this.names, this.relation);
}

class Reachability {
  int markings = 0, edges = 0, unsafe = 0, deadlocks = 0, stuck = 0;
  bool finalReached = false, sound = false;
  final List<String> dead = [];
  final Map<Pair, int> follows = {};
}

class Prefix {
  final List<String> trace;
  int weight = 0;
  final Set<String> followers = {};
  Prefix(this.trace);
}

class Precision {
  int prefixes = 0, allowed = 0, escaping = 0;
  final Map<String, int> escapes = {};
}

int comparePairs(Pair a, Pair b) {
  final d = a.$1.compareTo(b.$1);
  return d != 0 ? d : a.$2.compareTo(b.$2);
}

List<Pair> pairs(Map<Pair, int> d) => d.keys.toList()..sort(comparePairs);
List<Pair> rankedPairs(Map<Pair, int> d) => d.keys.toList()
  ..sort((a, b) {
    final c = d[b]!.compareTo(d[a]!);
    return c != 0 ? c : comparePairs(a, b);
  });
int sum(List<int> a) {
  var s = 0;
  for (final v in a) {
    s += v;
  }
  return s;
}

String average(List<int> a) =>
    a.isEmpty ? '-' : Ratio(sum(a), a.length).toString();
List<String> traceActivities(List<Trace> log) =>
    names(log.expand((v) => v.activities));
Discovery discover(
  List<Trace> log,
  List<String> activities,
  String Function(String, String) rel,
) {
  final d = Discovery(activities, rel), queue = <Masks>[], seen = <Masks>{};
  void add(Masks m) {
    if (!seen.contains(m) && candidate(m, activities, rel)) {
      seen.add(m);
      queue.add(m);
    }
  }

  for (var i = 0; i < activities.length; i++) {
    for (var j = 0; j < activities.length; j++) {
      if (rel(activities[i], activities[j]) == '->') {
        d.causal++;
        add((1 << i, 1 << j));
      }
    }
  }
  for (var pos = 0; pos < queue.length; pos++) {
    final m = queue[pos];
    var maximal = true;
    for (var i = 0; i < activities.length; i++) {
      final bit = 1 << i;
      if ((m.$1 & bit) == 0) {
        final v = (m.$1 | bit, m.$2);
        if (candidate(v, activities, rel)) {
          maximal = false;
          add(v);
        }
      }
      if ((m.$2 & bit) == 0) {
        final v = (m.$1, m.$2 | bit);
        if (candidate(v, activities, rel)) {
          maximal = false;
          add(v);
        }
      }
    }
    if (maximal) d.pairs.add(m);
  }
  d.candidates = queue.length;
  d.pairs.sort((a, b) => compareMasks(a, b, activities));
  final places = [
        'start',
        for (var i = 0; i < d.pairs.length; i++) 'p${i + 1}',
        'end',
      ],
      start = <String>{},
      end = <String>{};
  for (final v in log) {
    start.add(v.activities.first);
    end.add(v.activities.last);
  }
  final n = Net(places, List.of(activities), 0, places.length - 1);
  for (final t in activities) {
    if (start.contains(t)) {
      n.input[t]!.add(0);
      n.arcs++;
    }
    for (var i = 0; i < d.pairs.length; i++) {
      final pair = d.pairs[i];
      if (maskMembers(pair.$2, activities).contains(t)) {
        n.input[t]!.add(i + 1);
        n.arcs++;
      }
      if (maskMembers(pair.$1, activities).contains(t)) {
        n.output[t]!.add(i + 1);
        n.arcs++;
      }
    }
    if (end.contains(t)) {
      n.output[t]!.add(places.length - 1);
      n.arcs++;
    }
  }
  d.net = n;
  return d;
}

(Discovery, Map<Pair, int>) discoverPlus(
  List<Trace> w,
  List<String> tw,
  List<String> loops,
  Map<Pair, int> dw,
) {
  final loopSet = loops.toSet(),
      v = [
        for (final tr in w)
          Trace(
            tr.activities.where((a) => !loopSet.contains(a)).toList(),
            tr.weight,
          ),
      ];
  final tv = traceActivities(v), dv = follows(v), tri = triangles(v);
  final d = discover(v, tv, (a, b) => alphaRelation(dv, tri, a, b));
  d.net.transitions
    ..clear()
    ..addAll(tw);
  for (final t in loops) {
    d.net.input[t] = [];
    d.net.output[t] = [];
    final before = [
          for (final a in tv)
            if (count(dw, a, t) > 0) a,
        ],
        after = [
          for (final a in tv)
            if (count(dw, t, a) > 0) a,
        ];
    d.loopBefore[t] = before;
    d.loopAfter[t] = after;
    for (var i = 0; i < d.pairs.length; i++) {
      final pair = d.pairs[i];
      if (compareSequence(before, maskMembers(pair.$1, tv)) == 0 &&
          compareSequence(after, maskMembers(pair.$2, tv)) == 0) {
        final place = i + 1;
        d.net.input[t] = [place];
        d.net.output[t] = [place];
        d.net.arcs += 2;
        d.loopPlace[t] = d.net.places[place];
        break;
      }
    }
  }
  return (d, tri);
}

void reportDiscovery(StringBuffer s, Discovery d) {
  final n = d.net;
  for (var pi = 0; pi < n.places.length; pi++) {
    var input = <String>[], output = <String>[];
    for (final t in n.transitions) {
      if (n.output[t]!.contains(pi)) input.add(t);
      if (n.input[t]!.contains(pi)) output.add(t);
    }
    if (pi > 0 && pi < n.places.length - 1) {
      input = maskMembers(d.pairs[pi - 1].$1, d.names);
      output = maskMembers(d.pairs[pi - 1].$2, d.names);
    }
    s.writeln('PLACE ${n.places[pi]} ${list(input)} ${list(output)}');
  }
  for (final t in n.transitions) {
    s.writeln(
      'TRANSITION $t in ${list(n.input[t]!.map((i) => n.places[i]))} out ${list(n.output[t]!.map((i) => n.places[i]))}',
    );
  }
  s.writeln(
    'NET places ${n.places.length} transitions ${n.transitions.length} arcs ${n.arcs}',
  );
}

String markingKey(List<int> a) => a.join(',');
List<int> initialMarking(Net n) {
  final a = List.filled(n.places.length, 0);
  a[n.initial] = 1;
  return a;
}

Reachability reachability(Net n) {
  final r = Reachability(), initial = initialMarking(n);
  final states = [initial],
      index = {markingKey(initial): 0},
      reverse = <List<int>>[[]],
      enabledEver = <String>{};
  for (var pos = 0; pos < states.length; pos++) {
    final m = states[pos];
    var enabled = 0;
    for (final t in n.transitions) {
      if (!n.enabled(m, t)) continue;
      enabled++;
      enabledEver.add(t);
      final next = n.fire(m, t);
      if (next.any((v) => v > 1)) {
        r.unsafe++;
        continue;
      }
      r.edges++;
      final key = markingKey(next);
      var j = index[key];
      if (j == null) {
        j = states.length;
        index[key] = j;
        states.add(next);
        reverse.add([]);
      }
      reverse[j].add(pos);
      for (final u in n.transitions) {
        if (n.enabled(next, u)) r.follows[(t, u)] = 1;
      }
    }
    if (enabled == 0) {
      var finalMark = true;
      for (var i = 0; i < m.length; i++) {
        if (m[i] != (i == n.finalPlace ? 1 : 0)) finalMark = false;
      }
      if (!finalMark) r.deadlocks++;
    }
  }
  r.markings = states.length;
  final finalMark = List.filled(n.places.length, 0);
  finalMark[n.finalPlace] = 1;
  final fi = index[markingKey(finalMark)];
  r.finalReached = fi != null;
  final can = <int>{};
  if (fi != null) {
    final queue = [fi];
    can.add(fi);
    for (var pos = 0; pos < queue.length; pos++) {
      for (final parent in reverse[queue[pos]]) {
        if (can.add(parent)) queue.add(parent);
      }
    }
  }
  r.stuck = states.length - can.length;
  r.dead.addAll(n.transitions.where((t) => !enabledEver.contains(t)));
  r.sound = r.unsafe == 0 && r.stuck == 0 && r.dead.isEmpty;
  return r;
}

List<Prefix> prefixes(List<Case> cases) {
  final m = <String, Prefix>{};
  for (final c in cases) {
    for (var k = 0; k <= c.trace.length; k++) {
      final key = c.trace.take(k).join('\x00'),
          p = m[key] ??= Prefix(c.trace.take(k).toList());
      p.weight++;
      if (k < c.trace.length) p.followers.add(c.trace[k]);
    }
  }
  return m.values.toList();
}

Precision precision(Net n, List<Prefix> prefixes) {
  final r = Precision();
  for (final p in prefixes) {
    var m = initialMarking(n), fits = true;
    for (final t in p.trace) {
      if (!n.input.containsKey(t) || !n.enabled(m, t)) {
        fits = false;
        break;
      }
      m = n.fire(m, t);
    }
    if (!fits) continue;
    r.prefixes++;
    for (final t in n.transitions) {
      if (n.enabled(m, t)) {
        r.allowed += p.weight;
        if (!p.followers.contains(t)) {
          r.escaping += p.weight;
          r.escapes[t] = (r.escapes[t] ?? 0) + p.weight;
        }
      }
    }
  }
  return r;
}

Replay tokenReplay(Net n, Case c) {
  final r = Replay(n), tokens = List.generate(n.places.length, (_) => <int>[]);
  tokens[n.initial].add(c.events.first.time);
  r.produced = 1;
  for (final e in c.events) {
    final input = n.input[e.activity];
    if (input == null) {
      r.skipped++;
      continue;
    }
    for (final p in input) {
      r.consumed++;
      if (tokens[p].isNotEmpty) {
        final produced = tokens[p].removeAt(0);
        r.places[p].waits.add(e.time - produced);
        r.places[p].routes[e.activity] =
            (r.places[p].routes[e.activity] ?? 0) + 1;
      } else {
        r.missing++;
        r.places[p].missing++;
      }
    }
    for (final p in n.output[e.activity]!) {
      tokens[p].add(e.time);
      r.produced++;
    }
  }
  r.consumed++;
  if (tokens[n.finalPlace].isNotEmpty) {
    tokens[n.finalPlace].removeAt(0);
  } else {
    r.missing++;
    r.places[n.finalPlace].missing++;
  }
  for (var p = 0; p < tokens.length; p++) {
    r.places[p].remaining = tokens[p].length;
    r.remaining += tokens[p].length;
    if (r.places[p].missing > 0 || r.places[p].remaining > 0)
      r.places[p].deviating = 1;
  }
  if (r.missing == 0 && r.remaining == 0) r.fitting = 1;
  return r;
}

void aggregateReplay(Replay total, Replay r) {
  total.missing += r.missing;
  total.remaining += r.remaining;
  total.consumed += r.consumed;
  total.produced += r.produced;
  total.skipped += r.skipped;
  total.fitting += r.fitting;
  for (var i = 0; i < r.places.length; i++) {
    final p = r.places[i], v = total.places[i];
    v.missing += p.missing;
    v.remaining += p.remaining;
    v.deviating += p.deviating;
    v.waits.addAll(p.waits);
    for (final entry in p.routes.entries) {
      v.routes[entry.key] = (v.routes[entry.key] ?? 0) + entry.value;
    }
  }
}

void reportLog(
  StringBuffer out,
  List<Case> cases,
  List<Event> events,
  List<String> activities,
  List<String> resources,
  Net model,
  int sla,
  int rows,
  List<String> errors,
) {
  for (final e in errors) {
    out.writeln('ERROR $e');
  }
  var first = events.first, last = events.first;
  for (final e in events) {
    if (e.time < first.time) first = e;
    if (e.time > last.time) last = e;
  }
  out.writeln(
    'LOG rows $rows adopted ${events.length} rejected ${errors.length} cases ${cases.length} activities ${activities.length} resources ${resources.length} first ${first.timestamp} last ${last.timestamp}',
  );
  for (final a in activities) {
    var eventCount = 0, caseCount = 0, start = 0, end = 0, rework = 0;
    final waits = <int>[], rs = <String>{};
    for (final c in cases) {
      var count = 0;
      for (var i = 0; i < c.events.length; i++) {
        final e = c.events[i];
        if (e.activity == a) {
          count++;
          rs.add(e.resource);
          if (i > 0) waits.add(e.time - c.events[i - 1].time);
        }
      }
      eventCount += count;
      if (count > 0) caseCount++;
      if (count > 1) rework++;
      if (c.trace.first == a) start++;
      if (c.trace.last == a) end++;
    }
    out.writeln(
      'ACTIVITY $a events $eventCount cases $caseCount start $start end $end rework $rework wait ${average(waits)} resources ${rs.length} model ${yes(model.input.containsKey(a))}',
    );
  }
  final lengths = <int>[],
      durations = <int>[],
      days = <int, int>{},
      weekdayEvents = List.filled(7, 0),
      weekdayStarts = List.filled(7, 0),
      weekdayEnds = List.filled(7, 0);
  var late = 0, maxDays = 0;
  for (final e in events) {
    weekdayEvents[(e.time ~/ 1440 + 3) % 7]++;
  }
  for (final c in cases) {
    lengths.add(c.events.length);
    durations.add(c.duration);
    final d = c.duration ~/ 1440;
    days[d] = (days[d] ?? 0) + 1;
    maxDays = max(maxDays, d);
    if (c.duration > sla) late++;
    weekdayStarts[(c.events.first.time ~/ 1440 + 3) % 7]++;
    weekdayEnds[(c.events.last.time ~/ 1440 + 3) % 7]++;
  }
  for (final (name, a) in [('LENGTH', lengths), ('DURATION', durations)]) {
    a.sort();
    out.writeln(
      '$name min ${a.first} max ${a.last} mean ${average(a)} median ${median(a)}',
    );
  }
  for (var d = 0; d <= maxDays; d++) {
    out.writeln(
      'DAYS $d cases ${days[d] ?? 0} share ${percent(days[d] ?? 0, cases.length)}',
    );
  }
  out.writeln('SLA limit $sla late $late share ${percent(late, cases.length)}');
  final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  for (var i = 0; i < 7; i++) {
    out.writeln(
      'WEEKDAY ${weekdays[i]} events ${weekdayEvents[i]} starts ${weekdayStarts[i]} ends ${weekdayEnds[i]}',
    );
  }
}

void reportDFG(
  StringBuffer out,
  List<Case> cases,
  List<String> activities,
  Map<Pair, int> d,
) {
  final start = <String, int>{},
      end = <String, int>{},
      durations = <String, List<int>>{},
      waits = <Pair, List<int>>{},
      caseCounts = <Pair, int>{};
  for (final c in cases) {
    start[c.trace.first] = (start[c.trace.first] ?? 0) + 1;
    end[c.trace.last] = (end[c.trace.last] ?? 0) + 1;
    (durations[c.trace.last] ??= []).add(c.duration);
    final seen = <Pair>{};
    for (var i = 1; i < c.events.length; i++) {
      final a = c.events[i - 1],
          b = c.events[i],
          pair = (c.events[i - 1].activity, c.events[i].activity);
      (waits[pair] ??= []).add(b.time - a.time);
      seen.add(pair);
    }
    for (final pair in seen) {
      caseCounts[pair] = (caseCounts[pair] ?? 0) + 1;
    }
  }
  for (var k = 0; k < 2; k++) {
    final counts = k == 0 ? start : end;
    final a = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final name in a) {
      out.writeln(
        k == 0
            ? 'START $name count ${counts[name]}'
            : 'END $name count ${counts[name]} duration ${average(durations[name]!)}',
      );
    }
  }
  for (final pair in rankedPairs(d)) {
    final a = waits[pair]!..sort();
    out.writeln(
      'EDGE ${pair.$1} ${pair.$2} count ${d[pair]} cases ${caseCounts[pair]} mean ${average(a)} min ${a.first} max ${a.last}',
    );
  }
  footprint(out, activities, (a, b) => relation(d, a, b));
}

void reportHeuristic(
  StringBuffer out,
  List<String> activities,
  Map<Pair, int> d,
  Map<Pair, int> tri,
  Map<String, String> params,
) {
  final sigma = int.parse(params['positive_observations']!),
      td = parseRatio(params['dependency_threshold']!),
      rho = parseRatio(params['relative_to_best']!),
      t1 = parseRatio(params['loop1_threshold']!),
      t2 = parseRatio(params['loop2_threshold']!),
      ta = parseRatio(params['and_threshold']!),
      l1 = <String>{},
      l2 = <Pair>{},
      graph = <Pair, int>{};
  for (final a in activities) {
    final n = count(d, a, a);
    if (n == 0) continue;
    final measure = loopMeasure(n);
    var verdict = 'REJECT';
    if (n >= sigma && measure.compareTo(t1) >= 0) {
      l1.add(a);
      graph[(a, a)] = 1;
      verdict = 'ACCEPT';
    }
    out.writeln('L1 $a count $n measure $measure $verdict');
  }
  for (var i = 0; i < activities.length; i++) {
    final a = activities[i];
    for (final b in activities.skip(i + 1)) {
      if (l1.contains(a) || l1.contains(b)) continue;
      final n = count(tri, a, b) + count(tri, b, a);
      if (n == 0) continue;
      final measure = loopMeasure(n);
      var verdict = 'REJECT';
      if (n >= sigma && measure.compareTo(t2) >= 0) {
        l2
          ..add((a, b))
          ..add((b, a));
        verdict = 'ACCEPT';
      }
      out.writeln('L2 $a $b count $n measure $measure $verdict');
    }
  }
  final bestOut = <String, Ratio>{}, bestIn = <String, Ratio>{};
  for (final (a, b) in pairs(d)) {
    if (a == b) continue;
    final measure = dependency(d, a, b);
    if (bestOut[a] == null || measure.compareTo(bestOut[a]!) > 0)
      bestOut[a] = measure;
    if (bestIn[b] == null || measure.compareTo(bestIn[b]!) > 0)
      bestIn[b] = measure;
  }
  for (final pair in pairs(d)) {
    final (a, b) = pair;
    if (a == b) continue;
    final measure = dependency(d, a, b);
    var verdict = 'ACCEPT';
    if (l2.contains(pair)) {
      verdict = 'LOOP2';
    } else if (d[pair]! < sigma) {
      verdict = 'REJECT_COUNT';
    } else if (measure.compareTo(td) < 0) {
      verdict = 'REJECT_MEASURE';
    } else if (bestOut[a]!.subtract(measure).compareTo(rho) > 0 &&
        bestIn[b]!.subtract(measure).compareTo(rho) > 0) {
      verdict = 'REJECT_BEST';
    }
    if (verdict == 'ACCEPT' || verdict == 'LOOP2') graph[pair] = 1;
    out.writeln(
      'DEP $a $b count ${d[pair]} reverse ${count(d, b, a)} measure $measure $verdict',
    );
  }
  final inputs = <String, List<String>>{}, outputs = <String, List<String>>{};
  for (final a in activities) {
    inputs[a] = [
      for (final b in activities)
        if (count(graph, b, a) > 0) b,
    ];
    outputs[a] = [
      for (final b in activities)
        if (count(graph, a, b) > 0) b,
    ];
    out.writeln('NODE $a in ${list(inputs[a]!)} out ${list(outputs[a]!)}');
  }
  for (final a in activities) {
    for (var k = 0; k < 2; k++) {
      final others = (k == 0 ? outputs[a]! : inputs[a]!)
          .where((b) => b != a)
          .toList();
      for (var i = 0; i < others.length; i++) {
        final b = others[i];
        for (final c in others.skip(i + 1)) {
          final measure = splitMeasure(d, a, b, c, k == 1),
              kind = measure.compareTo(ta) >= 0 ? 'AND' : 'XOR';
          out.writeln(
            '${k == 0 ? 'SPLIT' : 'JOIN'} $a $b $c measure $measure $kind',
          );
        }
      }
    }
  }
  out.writeln(
    'GRAPH activities ${activities.length} edges ${graph.length} loops1 ${l1.length} loops2 ${l2.length ~/ 2}',
  );
}

void reportResources(
  StringBuffer out,
  List<Case> cases,
  List<String> activities,
  List<String> resources,
) {
  for (var i = 0; i < resources.length; i++) {
    final r = resources[i], work = <String, int>{};
    var count = 0, casesCount = 0;
    for (final c in cases) {
      var seen = false;
      for (final e in c.events) {
        if (e.resource == r) {
          work[e.activity] = (work[e.activity] ?? 0) + 1;
          count++;
          seen = true;
        }
      }
      if (seen) casesCount++;
    }
    final items = [
      for (final a in activities)
        if ((work[a] ?? 0) > 0) '$a=${work[a]}',
    ];
    out.writeln(
      'RESOURCE ${i + 1} $r events $count cases $casesCount work ${items.join(',')}',
    );
  }
  final handover = <Pair, int>{},
      handCases = <Pair, int>{},
      subcontract = <Pair, int>{},
      together = <Pair, int>{};
  var total = 0, self = 0;
  for (final c in cases) {
    final seen = <Pair>{}, rs = <String>{};
    for (var i = 0; i < c.events.length; i++) {
      final e = c.events[i];
      rs.add(e.resource);
      if (i > 0) {
        final pair = (c.events[i - 1].resource, e.resource);
        handover[pair] = (handover[pair] ?? 0) + 1;
        seen.add(pair);
        total++;
        if (pair.$1 == pair.$2) self++;
      }
      if (i >= 2) {
        final a = c.events[i - 2].resource, b = c.events[i - 1].resource;
        if (a == e.resource && a != b)
          subcontract[(a, b)] = (subcontract[(a, b)] ?? 0) + 1;
      }
    }
    for (final pair in seen) {
      handCases[pair] = (handCases[pair] ?? 0) + 1;
    }
    final a = names(rs);
    for (var i = 0; i < a.length; i++) {
      for (final b in a.skip(i + 1)) {
        final pair = (a[i], b);
        together[pair] = (together[pair] ?? 0) + 1;
      }
    }
  }
  for (final pair in rankedPairs(handover)) {
    if (pair.$1 != pair.$2)
      out.writeln(
        'HANDOVER ${pair.$1} ${pair.$2} count ${handover[pair]} cases ${handCases[pair]}',
      );
  }
  table(
    out,
    resources.length,
    5,
    (i, j) => count(handover, resources[i], resources[j]).toString(),
  );
  for (final pair in rankedPairs(subcontract)) {
    out.writeln('SUBCONTRACT ${pair.$1} ${pair.$2} count ${subcontract[pair]}');
  }
  for (final pair in rankedPairs(together)) {
    out.writeln('TOGETHER ${pair.$1} ${pair.$2} cases ${together[pair]}');
  }
  out.writeln('TOTAL handovers $total self $self other ${total - self}');
}

void reportConformance(
  StringBuffer out,
  StringBuffer csv,
  List<Net> nets,
  List<String> netNames,
  List<String> activities,
  List<Case> cases,
  Map<Pair, int> d,
  List<Replay> referenceReplays,
) {
  out.writeln(
    'MODEL places ${nets[0].places.length} transitions ${nets[0].transitions.length} arcs ${nets[0].arcs}',
  );
  final reach = <Reachability>[];
  for (var i = 0; i < nets.length; i++) {
    final r = reachability(nets[i]);
    reach.add(r);
    out.writeln(
      'REACHABILITY ${netNames[i]} markings ${r.markings} edges ${r.edges} unsafe ${r.unsafe} deadlocks ${r.deadlocks} stuck ${r.stuck} final ${yes(r.finalReached)} dead ${list(r.dead)} sound ${yes(r.sound)}',
    );
  }
  for (var i = 0; i < nets.length; i++) {
    final u = names([...activities, ...nets[i].transitions]),
        differences = <Pair>[];
    var different = 0;
    for (final a in u) {
      for (final b in u) {
        if (relation(d, a, b) != relation(reach[i].follows, a, b)) {
          different++;
          if (a.compareTo(b) <= 0) differences.add((a, b));
        }
      }
    }
    final cells = u.length * u.length;
    out.writeln(
      'FOOTPRINT ${netNames[i]} activities ${u.length} cells $cells differing $different fitness ${Ratio(cells - different, cells)}',
    );
    if (i == 0) {
      for (final (a, b) in differences) {
        out.writeln(
          'DIFF $a $b log ${relation(d, a, b)} model ${relation(reach[i].follows, a, b)}',
        );
      }
    }
  }
  final allPrefixes = prefixes(cases);
  for (var i = 0; i < nets.length; i++) {
    final r = precision(nets[i], allPrefixes),
        value = r.allowed == 0
            ? Ratio(1, 1)
            : Ratio(r.allowed - r.escaping, r.allowed);
    out.writeln(
      'PRECISION ${netNames[i]} prefixes ${r.prefixes} allowed ${r.allowed} escaping ${r.escaping} precision $value',
    );
    final escapes = r.escapes.keys.where((a) => r.escapes[a]! > 0).toList()
      ..sort((a, b) {
        final c = r.escapes[b]!.compareTo(r.escapes[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final a in escapes) {
      out.writeln('ESCAPE ${netNames[i]} $a weight ${r.escapes[a]}');
    }
  }
  csv.writeln(
    'case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness',
  );
  for (var i = 0; i < nets.length; i++) {
    final n = nets[i], total = Replay(nets[i]);
    for (var ci = 0; ci < cases.length; ci++) {
      final c = cases[ci],
          r = i == 0 ? referenceReplays[ci] : tokenReplay(n, cases[ci]);
      if (i == 0)
        csv.writeln(
          '${c.id},${c.variant},${c.events.length},${r.skipped},${r.missing},${r.remaining},${r.consumed},${r.produced},${r.fitness}',
        );
      aggregateReplay(total, r);
    }
    out.writeln(
      'REPLAY ${netNames[i]} cases ${cases.length} fitting ${total.fitting} skipped ${total.skipped} missing ${total.missing} remaining ${total.remaining} consumed ${total.consumed} produced ${total.produced} fitness ${total.fitness}',
    );
    for (var pi = 0; pi < n.places.length; pi++) {
      final v = total.places[pi];
      out.writeln(
        'PLACE ${netNames[i]} ${n.places[pi]} missing ${v.missing} remaining ${v.remaining} deviating ${v.deviating} tokens ${v.waits.length} mean ${average(v.waits)} max ${v.waits.isEmpty ? '-' : v.waits.reduce(max)}',
      );
    }
    for (var pi = 0; pi < n.places.length; pi++) {
      final routes = [
        for (final t in n.transitions)
          if (n.input[t]!.contains(pi)) '$t=${total.places[pi].routes[t] ?? 0}',
      ];
      if (routes.length >= 2)
        out.writeln('ROUTE ${netNames[i]} ${n.places[pi]} ${routes.join(',')}');
    }
  }
}

void main() {
  final (rows, params) = inputRows();
  final events = <Event>[],
      errors = <String>[],
      adopted = <String>{},
      activitySet = <String>{},
      resourceSet = <String>{};
  for (var i = 0; i < rows.length; i++) {
    final a = rows[i].split(','), time = timestamp(a[2]);
    if (time == null) {
      errors.add('line ${i + 2}: bad timestamp ${a[2]}');
      continue;
    }
    final key = '${a[0]}\x00${a[1]}\x00${a[2]}';
    if (!adopted.add(key)) {
      errors.add('line ${i + 2}: duplicate event ${a[0]} ${a[1]} ${a[2]}');
      continue;
    }
    events.add(Event(a[0], a[1], a[2], a[3], time, i + 2));
    activitySet.add(a[1]);
    resourceSet.add(a[3]);
  }
  final activities = names(activitySet),
      resources = names(resourceSet),
      cases = groupCases(events),
      model = readModel();
  final log = [for (final c in cases) Trace(c.trace, 1)], d = follows(log);
  final sla = int.parse(params['sla_minutes']!),
      filter = int.parse(params['filter_min_follows']!),
      byTrace = <String, Variant>{};
  for (final c in cases) {
    final key = c.trace.join('\x00');
    var v = byTrace[key];
    if (v == null) {
      v = Variant(c.trace);
      byTrace[key] = v;
      for (var i = 1; i < c.trace.length; i++) {
        if (count(d, c.trace[i - 1], c.trace[i]) < filter) v.keep = false;
      }
    }
    v.cases.add(c);
  }
  final variants = byTrace.values.toList()
    ..sort((a, b) {
      final c = b.cases.length.compareTo(a.cases.length);
      return c != 0 ? c : compareSequence(a.trace, b.trace);
    });
  final w = <Trace>[];
  var keptVariants = 0, keptCases = 0, keptEvents = 0;
  for (var i = 0; i < variants.length; i++) {
    final v = variants[i];
    for (final c in v.cases) {
      c.variant = i + 1;
    }
    if (v.keep) {
      w.add(Trace(v.trace, v.cases.length));
      keptVariants++;
      keptCases += v.cases.length;
      keptEvents += v.cases.length * v.trace.length;
    }
  }
  final referenceReplays = [for (final c in cases) tokenReplay(model, c)],
      replayByCase = <String, Replay>{};
  for (var i = 0; i < cases.length; i++) {
    replayByCase[cases[i].id] = referenceReplays[i];
  }
  final logOut = StringBuffer(),
      variantsOut = StringBuffer(),
      dfgOut = StringBuffer(),
      alphaOut = StringBuffer(),
      heuristicOut = StringBuffer(),
      conformanceCSV = StringBuffer(),
      conformanceOut = StringBuffer(),
      resourcesOut = StringBuffer();
  reportLog(
    logOut,
    cases,
    events,
    activities,
    resources,
    model,
    sla,
    rows.length,
    errors,
  );
  for (var i = 0; i < variants.length; i++) {
    final v = variants[i];
    var duration = 0, late = 0;
    for (final c in v.cases) {
      duration += c.duration;
      if (c.duration > sla) late++;
    }
    variantsOut.writeln(
      'VARIANT ${i + 1} count ${v.cases.length} share ${percent(v.cases.length, cases.length)} length ${v.trace.length} first ${v.cases.first.id} duration ${Ratio(duration, v.cases.length)} late $late fitness ${replayByCase[v.cases.first.id]!.fitness} ${v.keep ? 'KEEP' : 'DROP'} ${v.trace.join(',')}',
    );
  }
  variantsOut.writeln(
    'FILTER min_follows $filter variants $keptVariants of ${variants.length} cases $keptCases of ${cases.length} events $keptEvents of ${events.length}',
  );
  reportDFG(dfgOut, cases, activities, d);
  final tw = traceActivities(w),
      dw = follows(w),
      loops = [
        for (final a in tw)
          if (count(dw, a, a) > 0) a,
      ];
  final alpha = discover(w, tw, (a, b) => relation(dw, a, b));
  final (plus, tri) = discoverPlus(w, tw, loops, dw);
  alphaOut.writeln(
    'LOG variants $keptVariants cases $keptCases activities ${list(tw)}',
  );
  alphaOut.writeln('LOOPS ${list(loops)}');
  alphaOut.writeln('MINER alpha');
  footprint(alphaOut, alpha.names, alpha.relation);
  alphaOut.writeln(
    'PAIRS causal ${alpha.causal} candidates ${alpha.candidates} maximal ${alpha.pairs.length}',
  );
  reportDiscovery(alphaOut, alpha);
  alphaOut.writeln('MINER alpha_plus');
  for (final (a, b) in pairs(tri)) {
    alphaOut.writeln('TRIANGLE $a $b count ${count(tri, a, b)}');
  }
  footprint(alphaOut, plus.names, plus.relation);
  alphaOut.writeln(
    'PAIRS causal ${plus.causal} candidates ${plus.candidates} maximal ${plus.pairs.length}',
  );
  for (final t in loops) {
    alphaOut.writeln(
      'LOOP $t before ${list(plus.loopBefore[t]!)} after ${list(plus.loopAfter[t]!)} place ${plus.loopPlace[t] ?? '-'}',
    );
  }
  reportDiscovery(alphaOut, plus);
  reportHeuristic(heuristicOut, activities, d, triangles(log), params);
  reportConformance(
    conformanceOut,
    conformanceCSV,
    [model, alpha.net, plus.net],
    ['reference', 'alpha', 'alpha_plus'],
    activities,
    cases,
    d,
    referenceReplays,
  );
  reportResources(resourcesOut, cases, activities, resources);
  Directory('output').createSync(recursive: true);
  final outputs = {
    'log_summary.txt': logOut,
    'variants.txt': variantsOut,
    'dfg.txt': dfgOut,
    'alpha_net.txt': alphaOut,
    'heuristic_net.txt': heuristicOut,
    'conformance.csv': conformanceCSV,
    'conformance.txt': conformanceOut,
    'resources.txt': resourcesOut,
  };
  for (final entry in outputs.entries) {
    write('output/${entry.key}', entry.value);
  }
}
