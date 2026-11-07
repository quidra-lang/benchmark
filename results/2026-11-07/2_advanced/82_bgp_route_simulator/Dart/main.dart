import 'dart:io';
import 'dart:math';
part 'topology.dart';
part 'policy.dart';
part 'decision.dart';
part 'simulator.dart';
part 'report.dart';

List<String> lines(String path) => File(path).readAsLinesSync();
typedef Pair = (int, Prefix);

class BestChange {
  final int time, asn;
  final Prefix prefix;
  final String text;
  BestChange(this.time, this.asn, this.prefix, this.text);
}

class EventStats {
  final Event event;
  String status = '';
  int convergence = 0,
      updates = 0,
      withdrawals = 0,
      drops = 0,
      bestChanges = 0,
      routesChanged = 0,
      maxExploration = 0,
      first = -1,
      repeat = -1;
  final Map<Pair, int> exploration = {};
  final List<BestChange> changes = [], cycle = [];
  EventStats(this.event);
}

class Forwarding {
  String result = '';
  final List<int> visits;
  final List<(ASNode, Prefix, Link?)> hops = [];
  int count = 0;
  Forwarding(ASNode s) : visits = [s.number];
}

class TraceRecord {
  final int trace, start;
  int end = -1;
  final String result;
  final List<int> visits;
  TraceRecord(this.trace, this.start, this.result, List<int> v)
    : visits = List.unmodifiable(v);
}

class RingRecord {
  final Prefix prefix;
  final int start;
  int end = -1;
  final List<int> path;
  RingRecord(this.prefix, this.start, List<int> p)
    : path = List.unmodifiable(p);
}

List<int> mergePath(List<int> a) {
  final out = <int>[];
  for (final n in a) {
    if (out.isEmpty || out.last != n) out.add(n);
  }
  return out;
}

int valleyPosition(String p) {
  var i = 0;
  while (i < p.length && p[i] == 'U') {
    i++;
  }
  if (i < p.length && p[i] == 'P') i++;
  while (i < p.length && p[i] == 'D') {
    i++;
  }
  return i;
}

String endText(int n) => n < 0 ? 'END' : '$n';

class Simulator {
  final Topology topology;
  final Policies policies;
  final Parameters parameters;
  final List<Event> events;
  final messages = MessageQueue();
  int time = 0, end = 0;
  final List<String> updates = [];
  final List<EventStats> stats = [];
  late EventStats current;
  final Set<Prefix> changed = {};
  final List<TraceRecord> traceRecords = [];
  final List<TraceRecord?> ongoingTraces;
  final List<RingRecord> ringRecords = [];
  final Map<Prefix, Map<String, RingRecord>> ongoingRings = {};
  Simulator(this.topology, this.policies, this.parameters, this.events)
    : ongoingTraces = List.filled(parameters.traces.length, null);
  void log(String s) => updates.add('$time $s');
  (Route?, Rule?) importRoute(Session s, Prefix p, Attribute a) {
    final rule = policies.applied('IMPORT', s, p, a);
    if (rule != null && rule.deny) return (null, rule);
    final lp =
        rule?.lp ??
        switch (s.link.role(s.owner)) {
          'customer' => parameters.customer,
          'peer' => parameters.peer,
          _ => parameters.provider,
        };
    return (
      Route(
        Attribute(
          a.path,
          a.origin,
          rule?.med ?? a.med,
          rule == null ? a.communities : rule.edit(a.communities),
        ),
        lp: lp,
        link: s.link,
      ),
      rule,
    );
  }

  List<Route> candidates(ASNode node, Prefix p) {
    final out = <Route>[];
    for (final s in node.sessions) {
      final a = s.incoming[p];
      if (a != null) {
        final r = importRoute(s, p, a).$1;
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  void redecide(ASNode node, Prefix p) {
    Route? route;
    final a = node.origins[p];
    if (a != null) {
      route = Route(a, local: true);
    } else {
      final choices = candidates(node, p);
      if (choices.isNotEmpty) route = bestRoute(choices, topology).$1;
    }
    if (sameRoute(route, node.rib[p])) return;
    if (route == null) {
      node.rib.remove(p);
    } else {
      node.rib[p] = route;
    }
    final text = routeText(route);
    log('BEST ${node.number} ${prefixText(p)} $text');
    node.changes++;
    current.bestChanges++;
    final key = (node.number, p),
        n = (current.exploration[(node.number, p)] ?? 0) + 1;
    current.exploration[key] = n;
    current.maxExploration = max(current.maxExploration, n);
    current.changes.add(BestChange(time, node.number, p, text));
    changed.add(p);
    for (final s in node.sessions) {
      if (!s.link.up) continue;
      s.pending.add(p);
      if (s.timer < 0) pending(s);
    }
  }

  (Attribute?, Rule?) advertised(Session s, Prefix p) {
    final r = s.owner.rib[p];
    if (r == null) return (null, null);
    final a = r.attribute;
    if (!r.local && a.path.first == s.link.other(s.owner).number)
      return (null, null);
    if (a.communities.contains(noExport)) return (null, null);
    final rule = policies.applied('EXPORT', s, p, a);
    if (rule != null && rule.deny) return (null, rule);
    if (!(rule?.allow ?? false) &&
        !r.local &&
        r.link!.role(s.owner) != 'customer' &&
        s.link.role(s.owner) != 'customer')
      return (null, rule);
    return (
      Attribute(
        [...List.filled(1 + (rule?.prepend ?? 0), s.owner.number), ...a.path],
        a.origin,
        rule?.med ?? 0,
        rule == null ? a.communities : rule.edit(a.communities),
      ),
      rule,
    );
  }

  void pending(Session s) {
    var sent = 0;
    for (final p in orderedPrefixes(s.pending)) {
      final (a, r) = advertised(s, p);
      if (sameAttribute(a, s.outgoing[p])) continue;
      if (a == null) {
        s.outgoing.remove(p);
      } else {
        s.outgoing[p] = a;
      }
      final m = messages.send(time, s, p, a);
      sent++;
      s.sent++;
      current.updates++;
      final text =
          'SEND #${m.serial} ${m.sender.number}->${m.receiver.number} ${m.link.name} ${prefixText(p)}';
      if (a == null) {
        current.withdrawals++;
        log('$text WITHDRAW');
      } else {
        log('$text ANNOUNCE ${attributeText(a)}');
      }
      if (r != null) r.hits++;
    }
    s.pending.clear();
    s.timer = sent > 0 && s.link.mrai > 0 ? time + s.link.mrai : -1;
  }

  void receive(Message m) {
    final s = m.link.session(m.receiver), a = m.attribute;
    var result = 'WITHDRAW';
    s.received++;
    if (a == null) {
      s.incoming.remove(m.prefix);
    } else if (a.path.contains(m.receiver.number)) {
      s.incoming.remove(m.prefix);
      result = 'ANNOUNCE loop';
    } else {
      s.incoming[m.prefix] = a;
      final (route, rule) = importRoute(s, m.prefix, a);
      result = 'ANNOUNCE accept';
      if (rule != null) {
        rule.hits++;
        result = route == null
            ? 'ANNOUNCE deny ${rule.name}'
            : '$result ${rule.name}';
      }
    }
    log(
      'RECV #${m.serial} ${m.sender.number}->${m.receiver.number} ${m.link.name} ${prefixText(m.prefix)} $result',
    );
    redecide(m.receiver, m.prefix);
  }

  void execute(Event event) {
    log('EVENT ${event.number} ${event.text}');
    final a = event.args;
    switch (event.kind) {
      case 'INITIAL':
        for (final x in topology.initial) {
          x.$1.origins[x.$2] = x.$3;
          redecide(x.$1, x.$2);
        }
        break;
      case 'ANNOUNCE':
        {
          final node = topology.byNumber[int.parse(a[1])]!, p = prefix(a[2]);
          node.origins[p] = Attribute([], a[3], 0, communities(a.skip(4)));
          redecide(node, p);
          break;
        }
      case 'WITHDRAW':
        {
          final node = topology.byNumber[int.parse(a[1])]!, p = prefix(a[2]);
          node.origins.remove(p);
          redecide(node, p);
          break;
        }
      case 'LINK_DOWN':
        {
          final link = topology.byName[a[2]]!;
          link.up = false;
          link.downs++;
          for (final m in messages.removeLink(link)) {
            current.drops++;
            log(
              'DROP #${m.serial} ${m.sender.number}->${m.receiver.number} ${link.name} ${prefixText(m.prefix)}',
            );
          }
          final endpoints = [link.a, link.b]
            ..sort((a, b) => a.number.compareTo(b.number));
          final remembered = <List<Prefix>>[];
          for (final node in endpoints) {
            final s = link.session(node);
            remembered.add(orderedPrefixes(s.incoming.keys));
            s.incoming.clear();
            s.outgoing.clear();
            s.pending.clear();
            s.timer = -1;
          }
          for (var i = 0; i < 2; i++) {
            for (final p in remembered[i]) {
              redecide(endpoints[i], p);
            }
          }
          break;
        }
      case 'LINK_UP':
        {
          final link = topology.byName[a[2]]!;
          link.up = true;
          final endpoints = [link.a, link.b]
            ..sort((a, b) => a.number.compareTo(b.number));
          for (final node in endpoints) {
            final s = link.session(node);
            s.pending.clear();
            s.pending.addAll(node.rib.keys);
            pending(s);
          }
          break;
        }
      case 'POLICY_ON':
      case 'POLICY_OFF':
        final rule = policies.byName[a[2]]!;
        rule.active = event.kind == 'POLICY_ON';
        final node = topology.byNumber[rule.owner]!;
        if (rule.direction == 'IMPORT') {
          for (final p in orderedPrefixes(
            node.sessions.expand((s) => s.incoming.keys),
          )) {
            redecide(node, p);
          }
        } else {
          for (final s in node.sessions) {
            if (!s.link.up) continue;
            s.pending.addAll([...node.rib.keys, ...s.outgoing.keys]);
            if (s.timer < 0) pending(s);
          }
        }
        break;
    }
  }

  bool quiet() =>
      messages.heap.isEmpty &&
      topology.sessions.every((s) => s.pending.isEmpty);
  String state() {
    final out = StringBuffer();
    void table(String tag, Map<Prefix, Attribute> a) {
      out.write('$tag{');
      for (final p in orderedPrefixes(a.keys)) {
        out.write('${prefixText(p)}=${attributeText(a[p]!)};');
      }
      out.write('}');
    }

    for (final s in topology.sessions) {
      out.write('S${s.owner.number}:${s.link.number}');
      table('I', s.incoming);
      table('O', s.outgoing);
      out.write('P{');
      for (final p in orderedPrefixes(s.pending)) {
        out.write('${prefixText(p)};');
      }
      out.write('}T${s.timer < 0 ? -1 : s.timer - time};');
    }
    out.write('Q{');
    for (final m in messages.ordered()) {
      out.write(
        '${m.time - time}:${m.receiver.number}:${m.sender.number}:${m.link.number}:${prefixText(m.prefix)}:',
      );
      final a = m.attribute;
      out.write(a == null ? 'W;' : 'A${attributeText(a)};');
    }
    out.write('}');
    return out.toString();
  }

  Map<Pair, Route> snapshot() => {
    for (final n in topology.nodes)
      for (final e in n.rib.entries) (n.number, e.key): e.value,
  };
  void run() {
    for (var k = 0; k < events.length; k++) {
      final event = events[k];
      current = EventStats(event);
      final before = snapshot(), seen = <String, int>{};
      var deliveries = 0;
      time = event.time;
      changed.clear();
      execute(event);
      for (var t = event.time; ; t++) {
        time = t;
        if (t > event.time) changed.clear();
        final arrived = messages.arrivals(t);
        for (final m in arrived) {
          receive(m);
        }
        if (arrived.isNotEmpty) current.convergence = t - event.time;
        for (final s in topology.sessions) {
          if (s.timer == t) {
            s.timer = -1;
            if (s.pending.isNotEmpty) pending(s);
          }
        }
        if (changed.isNotEmpty) forwardingCheck();
        if (arrived.isNotEmpty) {
          deliveries++;
          if (current.first < 0 && deliveries <= parameters.stepcap) {
            final key = state(), first = seen[key];
            if (first != null) {
              current.first = first;
              current.repeat = t;
              current.cycle.addAll(
                current.changes.where((c) => c.time > first && c.time <= t),
              );
            } else {
              seen[key] = t;
            }
          }
        }
        final last = k == events.length - 1;
        if (last
            ? (quiet() ||
                  current.first >= 0 ||
                  deliveries >= parameters.stepcap)
            : t == events[k + 1].time - 1) {
          end = t;
          break;
        }
      }
      current.status = current.first >= 0
          ? 'DIVERGENT'
          : quiet()
          ? 'CONVERGED'
          : k == events.length - 1
          ? 'CAPPED'
          : 'UNSETTLED';
      final after = snapshot();
      for (final p in {...before.keys, ...after.keys}) {
        if (!sameRoute(before[p], after[p])) current.routesChanged++;
      }
      stats.add(current);
    }
  }

  Forwarding forward(ASNode source, int address) {
    final out = Forwarding(source), visited = {source.number};
    var node = source;
    while (true) {
      Route? route;
      Prefix? p;
      for (final e in node.rib.entries) {
        if (contains(e.key, address) && (p == null || e.key.$2 > p.$2)) {
          route = e.value;
          p = e.key;
        }
      }
      if (route == null) {
        out.result = out.hops.isEmpty ? 'UNREACHABLE' : 'BLACKHOLE';
        return out;
      }
      if (route.local) {
        out.hops.add((node, p!, null));
        out.result = 'DELIVERED';
        return out;
      }
      final link = route.link!;
      out.hops.add((node, p!, link));
      out.count++;
      node = link.other(node);
      out.visits.add(node.number);
      if (!visited.add(node.number)) {
        out.result = 'LOOP';
        return out;
      }
    }
  }

  String pattern(List<int> path) => [
    for (var i = 0; i < path.length - 1; i++)
      symbol(
        topology
            .between(path[i], path[i + 1])
            .role(topology.byNumber[path[i]]!),
      ),
  ].join();
  List<List<int>> loops(Prefix p) {
    final done = <int>{}, out = <List<int>>[];
    for (final source in topology.nodes) {
      if (done.contains(source.number)) continue;
      final positions = <int, int>{}, path = <int>[];
      var node = source;
      while (true) {
        if (done.contains(node.number)) break;
        final at = positions[node.number];
        if (at != null) {
          final cycle = path.sublist(at);
          var first = 0;
          for (var i = 1; i < cycle.length; i++) {
            if (cycle[i] < cycle[first]) first = i;
          }
          out.add([...cycle.skip(first), ...cycle.take(first)]);
          break;
        }
        positions[node.number] = path.length;
        path.add(node.number);
        final route = node.rib[p];
        if (route == null || route.local) break;
        node = route.link!.other(node);
      }
      done.addAll(path);
    }
    out.sort((a, b) => a.first.compareTo(b.first));
    return out;
  }

  void forwardingCheck() {
    for (final p in orderedPrefixes(changed)) {
      final paths = loops(p),
          found = {for (final path in paths) pathText(path): path},
          ongoing = ongoingRings.putIfAbsent(p, () => {});
      for (final key
          in ongoing.keys.where((k) => !found.containsKey(k)).toList()) {
        ongoing.remove(key)!.end = time;
      }
      for (final path in paths) {
        final key = pathText(path);
        if (!ongoing.containsKey(key)) {
          final r = RingRecord(p, time, path);
          ongoing[key] = r;
          ringRecords.add(r);
        }
      }
    }
    for (var i = 0; i < parameters.traces.length; i++) {
      final trace = parameters.traces[i],
          path = forward(parameters.traces[i].$1, trace.$2),
          status = path.result == 'LOOP' || path.result == 'BLACKHOLE'
              ? path.result
              : '',
          old = ongoingTraces[i];
      if (old != null &&
          (old.result != status || !sameInts(old.visits, path.visits))) {
        old.end = time;
        ongoingTraces[i] = null;
      }
      if (status.isNotEmpty && ongoingTraces[i] == null) {
        final r = TraceRecord(i, time, status, path.visits);
        ongoingTraces[i] = r;
        traceRecords.add(r);
      }
    }
  }

  List<String> convergenceLines() => [
    'event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration',
    for (final s in stats)
      '${s.event.number},${s.event.time},${s.event.kind},${s.status},${s.convergence},${s.updates},${s.withdrawals},${s.drops},${s.bestChanges},${s.routesChanged},${s.maxExploration}',
  ];
  List<String> ribLines() {
    final out = <String>[];
    for (final node in topology.nodes) {
      final sent = node.sessions.fold(0, (n, s) => n + s.sent),
          received = node.sessions.fold(0, (n, s) => n + s.received),
          local = node.rib.values.where((r) => r.local).length;
      out.add(
        'AS ${node.number} routes ${node.rib.length} local $local sent $sent received $received changes ${node.changes}',
      );
      for (final s in node.sessions) {
        var accepted = 0;
        for (final e in s.incoming.entries) {
          if (importRoute(s, e.key, e.value).$1 != null) accepted++;
        }
        out.add(
          'SESSION ${s.link.name} ${s.link.other(node).number} ${s.link.role(node)} ${s.link.up ? 'UP' : 'DOWN'} in ${s.incoming.length} accepted $accepted out ${s.outgoing.length} sent ${s.sent} received ${s.received} flaps ${s.link.downs}',
        );
      }
      for (final p in orderedPrefixes(node.rib.keys)) {
        final r = node.rib[p]!, choices = candidates(node, p);
        var text =
            '${prefixText(p)} ${routeText(r)} candidates ${choices.length}';
        if (!r.local) text += ' reason ${bestRoute(choices, topology).$2}';
        out.add(text);
        final remaining = choices.where((c) => !sameRoute(c, r)).toList();
        while (remaining.isNotEmpty) {
          final best = bestRoute(remaining, topology).$1;
          out.add('ALT ${routeText(best)}');
          remaining.remove(best);
        }
      }
    }
    return out;
  }

  List<String> pathLines() {
    final out = <String>[];
    for (final trace in parameters.traces) {
      final path = forward(trace.$1, trace.$2), directions = StringBuffer();
      out.add(
        'TRACE ${trace.$1.number} ${trace.$3} ${path.result} hops ${path.count}',
      );
      for (final hop in path.hops) {
        final link = hop.$3;
        if (link == null) {
          out.add('HOP ${hop.$1.number} ${prefixText(hop.$2)} LOCAL');
        } else {
          out.add(
            'HOP ${hop.$1.number} ${prefixText(hop.$2)} next ${link.other(hop.$1).number} link ${link.name}',
          );
          directions.write(symbol(link.role(hop.$1)));
        }
      }
      if (path.result == 'LOOP') {
        out.add('HOP ${path.visits.last} REVISIT');
      } else if (path.result == 'BLACKHOLE' || path.result == 'UNREACHABLE') {
        out.add('HOP ${path.visits.last} NOROUTE');
      }
      if (path.hops.isEmpty) {
        out.add('CONTROL NONE');
      } else {
        final r = trace.$1.rib[path.hops.first.$2]!,
            notation = r.local ? 'LOCAL' : pathText(r.attribute.path),
            match =
                path.result == 'DELIVERED' &&
                    sameInts(
                      mergePath(r.attribute.path),
                      path.visits.sublist(1),
                    )
                ? 'MATCH'
                : 'MISMATCH';
        out.add('CONTROL $notation $match');
      }
      if (path.count > 0) {
        final p = directions.toString();
        out.add(
          'PATTERN $p ${valleyPosition(p) == p.length ? 'VALLEYFREE' : 'VALLEY'}',
        );
      }
    }
    final prefixes = orderedPrefixes(
      topology.nodes.expand((n) => n.origins.keys),
    );
    out.add(
      prefixes.isEmpty
          ? 'PREFIXES'
          : 'PREFIXES ${prefixes.map(prefixText).join(',')}',
    );
    for (final node in topology.nodes) {
      var symbols = '';
      for (final p in prefixes) {
        final path = forward(node, p.$1);
        symbols += switch (path.result) {
          'LOOP' => 'L',
          'BLACKHOLE' => 'B',
          'DELIVERED' =>
            path.count == 0
                ? '*'
                : path.hops.last.$1.origins.containsKey(p)
                ? '+'
                : 'X',
          _ => 'U',
        };
      }
      out.add(
        symbols.isEmpty
            ? 'REACH ${node.number}'
            : 'REACH ${node.number} $symbols',
      );
    }
    return out;
  }

  List<String> auditLines() {
    final out = <String>[];
    var loopCount = 0, blackholes = 0, valleys = 0, learned = 0, divergent = 0;
    final traces = List<TraceRecord>.of(traceRecords)
      ..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.trace.compareTo(b.trace);
      });
    for (final r in traces) {
      final t = parameters.traces[r.trace];
      var text =
          '${r.result} ${t.$1.number} ${t.$3} from ${r.start} to ${endText(r.end)}';
      if (r.result == 'BLACKHOLE') {
        blackholes++;
        text += ' at ${r.visits.last}';
      } else {
        loopCount++;
      }
      out.add('$text path ${pathText(r.visits)}');
    }
    final rings = List<RingRecord>.of(ringRecords)
      ..sort((a, b) {
        var c = a.start.compareTo(b.start);
        if (c != 0) return c;
        c = prefixCompare(a.prefix, b.prefix);
        return c != 0 ? c : a.path.first.compareTo(b.path.first);
      });
    for (final r in rings) {
      out.add(
        'RING ${prefixText(r.prefix)} from ${r.start} to ${endText(r.end)} path ${pathText(r.path)}',
      );
    }
    for (final node in topology.nodes) {
      for (final p in orderedPrefixes(node.rib.keys)) {
        final r = node.rib[p]!;
        if (r.local) continue;
        learned++;
        final h = mergePath([node.number, ...r.attribute.path]),
            w = pattern(h),
            g = valleyPosition(w);
        if (g < w.length) {
          valleys++;
          out.add(
            'VALLEY ${node.number} ${prefixText(p)} path ${pathText(r.attribute.path)} pattern $w leaker ${h[g]}',
          );
        }
      }
    }
    for (final rule in policies.rules) {
      out.add(
        'RULE ${rule.name} ${rule.direction} ${rule.active ? 'ON' : 'OFF'} hits ${rule.hits}',
      );
    }
    for (final s in stats) {
      if (s.first < 0) continue;
      divergent++;
      out.add(
        'DIVERGENT event ${s.event.number} first ${s.first} repeat ${s.repeat} period ${s.repeat - s.first}',
      );
      final counts = <Pair, int>{};
      for (final c in s.cycle) {
        out.add('CYCLE ${c.time} ${c.asn} ${prefixText(c.prefix)} ${c.text}');
        final p = (c.asn, c.prefix);
        counts[p] = (counts[p] ?? 0) + 1;
      }
      final pairs = counts.keys.toList()
        ..sort((a, b) {
          final c = a.$1.compareTo(b.$1);
          return c != 0 ? c : prefixCompare(a.$2, b.$2);
        });
      for (final p in pairs) {
        out.add('OSCILLATE ${p.$1} ${prefixText(p.$2)} changes ${counts[p]}');
      }
    }
    out.add(
      'SUMMARY loops $loopCount blackholes $blackholes rings ${rings.length} routes $learned valleys $valleys divergent $divergent end $end',
    );
    return out;
  }
}

void main() {
  final t = readTopology(),
      p = readParameters(t),
      s = Simulator(t, readPolicies(), p, readEvents());
  s.run();
  Directory('output').createSync(recursive: true);
  writeLines('updates.txt', s.updates);
  writeLines('convergence.csv', s.convergenceLines());
  writeLines('ribs.txt', s.ribLines());
  writeLines('paths.txt', s.pathLines());
  writeLines('audit.txt', s.auditLines());
}
