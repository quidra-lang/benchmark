import 'dart:io';
import 'dart:math' as math;

class Point {
  final int x, y;
  Point(this.x, this.y);
}
class DeliveryStop extends Point {
  final int demand, service;
  final int? open, close;
  DeliveryStop(int x, int y, this.demand, this.service, this.open, this.close) : super(x, y);
}
class Plan {
  final int capacity;
  List<List<int>> routes;
  Plan(this.capacity, this.routes);
}
class Run {
  final int time, violations, lateness;
  Run(this.time, this.violations, this.lateness);
}
class Saving {
  final int i, j, saving;
  Saving(this.i, this.j, this.saving);
}
class RouteError implements Exception {
  final String message;
  RouteError(this.message);
}
final stops = <int, DeliveryStop>{}, output = <String>[];
Point? depot;
var departure = 480;
List<int>? tour;
Plan? plan;
Never fail(String message) => throw RouteError('error: $message');
List<int> ids() => stops.keys.toList()..sort();
Point point(int id) => id == 0 ? depot! : stops[id]!;
int distance(int a, int b) {
  final x = point(a), y = point(b);
  return (x.x - y.x).abs() + (x.y - y.y).abs();
}
int length(List<int> route) {
  final path = [0, ...route, 0];
  var total = 0;
  for (var i = 1; i < path.length; i++) { total += distance(path[i - 1], path[i]); }
  return total;
}
int load(List<int> route) => route.fold<int>(0, (sum, id) => sum + stops[id]!.demand);
String notation(List<int> route) => ['D', ...route, 'D'].join('-');
String location(int id) => id == 0 ? 'D' : '$id';
int minute(String text) => int.parse(text.substring(0, 2)) * 60 + int.parse(text.substring(3));
String clock(int time) => '${(time ~/ 60).toString().padLeft(2, '0')}:${(time % 60).toString().padLeft(2, '0')}';
String decimal(int tenths) => '${tenths ~/ 10}.${tenths % 10}';
void requireStops() {
  if (depot == null) fail('no depot');
  if (stops.isEmpty) fail('no stops');
}
List<int> requireTour() {
  if (tour == null) fail('no tour');
  return tour!;
}
Plan requirePlan() {
  if (plan == null) fail('no plan');
  return plan!;
}
void checkCapacity(int capacity) {
  for (final id in ids()) {
    if (stops[id]!.demand > capacity) fail('stop $id demand ${stops[id]!.demand} exceeds capacity $capacity');
  }
}
List<List<int>> normalize(List<List<int>> routes) => routes.where((route) => route.isNotEmpty)
    .map((route) => route.first > route.last ? route.reversed.toList() : route).toList()
    ..sort((a, b) => a.reduce(math.min).compareTo(b.reduce(math.min)));
int planLength(Plan value) => value.routes.fold<int>(0, (sum, route) => sum + length(route));
void routeLines(Plan value) {
  for (var i = 0; i < value.routes.length; i++) {
    final route = value.routes[i];
    output.add('route ${i + 1}: ${notation(route)} load ${load(route)} length ${length(route)}');
  }
}
Run simulate(List<int> route, [bool print = false]) {
  var time = departure, previous = 0, waiting = 0, service = 0, violations = 0, lateness = 0;
  for (final id in route) {
    final stop = stops[id]!, arrival = time + distance(previous, id);
    final wait = stop.open == null ? 0 : math.max(0, stop.open! - arrival), begin = arrival + wait;
    final late = stop.close == null ? 0 : math.max(0, arrival - stop.close!);
    time = begin + stop.service;
    waiting += wait;
    service += stop.service;
    if (late > 0) violations++;
    lateness += late;
    if (print) output.add('$id arrive ${clock(arrival)} wait $wait begin ${clock(begin)} leave ${clock(time)} ${late > 0 ? 'late $late' : 'ok'}');
    previous = id;
  }
  time += distance(previous, 0);
  if (print) output.add('return ${clock(time)}, travel ${length(route)}, wait $waiting, service $service, violations $violations, lateness $lateness');
  return Run(time, violations, lateness);
}
int twoOpt(List<int> route, bool announce) {
  var moves = 0;
  while (true) {
    var changed = false;
    scan: for (var i = 0; i + 1 < route.length; i++) {
      for (var j = i + 1; j < route.length; j++) {
        final before = i == 0 ? 0 : route[i - 1], after = j + 1 == route.length ? 0 : route[j + 1];
        final gain = distance(before, route[i]) + distance(route[j], after) - distance(before, route[j]) - distance(route[i], after);
        if (gain > 0) {
          if (announce) output.add('reverse ${route[i]}..${route[j]} gain $gain');
          final segment = route.sublist(i, j + 1).reversed.toList();
          route.replaceRange(i, j + 1, segment);
          moves++;
          changed = true;
          break scan;
        }
      }
    }
    if (!changed) return moves;
  }
}
List<int> exact() {
  final names = ids(), memo = <(int, int), int>{};
  int best(int previous, int mask) {
    if (mask == 0) return distance(previous, 0);
    final cached = memo[(previous, mask)];
    if (cached != null) return cached;
    int? value;
    for (var i = 0; i < names.length; i++) {
      if ((mask & (1 << i)) != 0) {
        final candidate = distance(previous, names[i]) + best(names[i], mask ^ (1 << i));
        value = value == null ? candidate : math.min(value, candidate);
      }
    }
    return memo[(previous, mask)] = value!;
  }
  final result = <int>[];
  var previous = 0, mask = (1 << names.length) - 1;
  while (mask != 0) {
    final target = best(previous, mask);
    for (var i = 0; i < names.length; i++) {
      if ((mask & (1 << i)) != 0 && distance(previous, names[i]) + best(names[i], mask ^ (1 << i)) == target) {
        result.add(names[i]);
        previous = names[i];
        mask ^= 1 << i;
        break;
      }
    }
  }
  return result;
}
(int, List<String>) spanning(List<int> names, int first) {
  final tree = <int>[first], remaining = names.where((id) => id != first).toList(), edges = <String>[];
  var total = 0;
  while (remaining.isNotEmpty) {
    var chosen = -1, parent = -1;
    int? weight;
    for (final id in remaining) {
      for (final from in tree) {
        final candidate = distance(from, id);
        if (weight == null || candidate < weight) { chosen = id; parent = from; weight = candidate; }
      }
    }
    total += weight!;
    edges.add('${location(parent)}-$chosen');
    tree.add(chosen);
    remaining.remove(chosen);
  }
  return (total, edges);
}
void improvePlan(String command) {
  final value = requirePlan(), oldLength = planLength(requirePlan()), oldCount = requirePlan().routes.length;
  var moves = 0;
  bool step() {
    final routes = value.routes, capacity = value.capacity;
    if (command == 'RELOCATE') {
      for (var r = 0; r < routes.length; r++) {
        for (var p = 0; p < routes[r].length; p++) {
          for (var t = 0; t < routes.length; t++) {
            if (t == r) continue;
            final a = routes[r], b = routes[t], c = routes[r][p];
            if (load(b) + stops[c]!.demand > capacity) continue;
            for (var j = 0; j <= b.length; j++) {
              final before = p == 0 ? 0 : a[p - 1], after = p + 1 == a.length ? 0 : a[p + 1];
              final u = j == 0 ? 0 : b[j - 1], v = j == b.length ? 0 : b[j];
              final gain = distance(before, c) + distance(c, after) - distance(before, after) - distance(u, c) - distance(c, v) + distance(u, v);
              if (gain > 0) {
                output.add('relocate $c from route ${r + 1} to route ${t + 1} after ${location(u)} gain $gain');
                a.removeAt(p);
                b.insert(j, c);
                value.routes = normalize(routes);
                return true;
              }
            }
          }
        }
      }
    } else if (command == 'EXCHANGE') {
      for (var r = 0; r < routes.length; r++) {
        for (var t = r + 1; t < routes.length; t++) {
          for (var p = 0; p < routes[r].length; p++) {
            for (var j = 0; j < routes[t].length; j++) {
              final a = routes[r], b = routes[t], c = routes[r][p], e = routes[t][j];
              if (load(a) - stops[c]!.demand + stops[e]!.demand > capacity || load(b) - stops[e]!.demand + stops[c]!.demand > capacity) continue;
              final nextA = List<int>.of(a), nextB = List<int>.of(b);
              nextA[p] = e;
              nextB[j] = c;
              final gain = length(a) + length(b) - length(nextA) - length(nextB);
              if (gain > 0) {
                output.add('exchange $c (route ${r + 1}) with $e (route ${t + 1}) gain $gain');
                routes[r] = nextA;
                routes[t] = nextB;
                value.routes = normalize(routes);
                return true;
              }
            }
          }
        }
      }
    } else {
      for (var r = 0; r < routes.length; r++) {
        for (var t = r + 1; t < routes.length; t++) {
          for (var i = 0; i <= routes[r].length; i++) {
            for (var j = 0; j <= routes[t].length; j++) {
              final a = routes[r], b = routes[t];
              final nextA = [...a.take(i), ...b.skip(j)], nextB = [...b.take(j), ...a.skip(i)];
              if (load(nextA) > capacity || load(nextB) > capacity) continue;
              final x = i == 0 ? 0 : a[i - 1], y = j == 0 ? 0 : b[j - 1];
              final afterA = i == a.length ? 0 : a[i], afterB = j == b.length ? 0 : b[j];
              final gain = distance(x, afterA) + distance(y, afterB) - distance(x, afterB) - distance(y, afterA);
              if (gain > 0) {
                output.add('cross route ${r + 1} after ${location(x)} with route ${t + 1} after ${location(y)} gain $gain');
                routes[r] = nextA;
                routes[t] = nextB;
                value.routes = normalize(routes);
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }
  while (step()) { moves++; }
  output.add('${command.toLowerCase()}: moves $moves${command == 'EXCHANGE' ? '' : ', routes $oldCount -> ${value.routes.length}'}, length $oldLength -> ${planLength(value)}');
}
void execute(String line) {
  final words = line.split(' ');
  final command = words.first, args = words.skip(1).toList();
  final a = args.isEmpty ? 0 : int.tryParse(args[0]) ?? 0, b = args.length < 2 ? 0 : int.tryParse(args[1]) ?? 0;
  if (command == 'DEPOT') { depot = Point(a, b); output.add('depot at ($a,$b)'); return; }
  if (command == 'START') { departure = minute(args[0]); output.add('start ${clock(departure)}'); return; }
  if (command == 'STOP') {
    if (stops.containsKey(a)) fail('stop $a already exists');
    final open = args.length > 5 ? minute(args[5]) : null, close = args.length > 5 ? minute(args[6]) : null;
    if (open != null && open > close!) fail('invalid window');
    stops[a] = DeliveryStop(b, int.parse(args[2]), int.parse(args[3]), int.parse(args[4]), open, close);
    tour = null;
    plan = null;
    output.add('stop $a added');
    return;
  }
  if (command == 'REMOVE') {
    if (stops.remove(a) == null) fail('unknown stop $a');
    if (stops.isEmpty) { tour = null; plan = null; }
    else {
      tour?.remove(a);
      if (plan != null) plan!.routes = normalize(plan!.routes.map((route) => route.where((id) => id != a).toList()).toList());
    }
    output.add('stop $a removed');
    return;
  }
  if (command == 'LIST') {
    output.addAll([depot == null ? 'depot none' : 'depot (${depot!.x},${depot!.y})', 'start ${clock(departure)}', 'stops ${stops.length}']);
    for (final id in ids()) {
      final stop = stops[id]!;
      output.add('$id at (${stop.x},${stop.y}) demand ${stop.demand} service ${stop.service} window ${stop.open == null ? 'none' : '${clock(stop.open!)}-${clock(stop.close!)}'}');
    }
    return;
  }
  if (command == 'MATRIX') {
    if (depot == null) fail('no depot');
    final locations = [0, ...ids()];
    final rows = <List<String>>[['', ...locations.map(location)],
      for (final id in locations) [location(id), ...locations.map((other) => '${distance(id, other)}')]];
    final width = rows.expand((row) => row).map((cell) => cell.length).reduce(math.max);
    output.addAll(rows.map((row) => row.map((cell) => cell.padLeft(width)).join(' ')));
    return;
  }
  if (['ORDER', 'NEAREST', 'INSERTION', 'EXACT', 'BOUND', 'VRP', 'SWEEP'].contains(command)) requireStops();
  if (command == 'ORDER') {
    final order = args.map(int.parse).toList();
    for (final id in order) { if (!stops.containsKey(id)) fail('unknown stop $id'); }
    final seen = <int>{};
    for (final id in order) { if (!seen.add(id)) fail('duplicate stop $id'); }
    if (order.length != stops.length) fail('order has ${order.length} stops, expected ${stops.length}');
    tour = order;
  } else if (command == 'NEAREST') {
    final remaining = ids(), route = <int>[];
    var previous = 0;
    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        final order = distance(previous, a).compareTo(distance(previous, b));
        return order == 0 ? a.compareTo(b) : order;
      });
      previous = remaining.removeAt(0);
      route.add(previous);
    }
    tour = route;
  } else if (command == 'INSERTION') {
    final remaining = ids(), route = <int>[];
    while (remaining.isNotEmpty) {
      int? best;
      var chosen = -1, position = -1;
      for (final id in remaining) {
        for (var j = 0; j <= route.length; j++) {
          final before = j == 0 ? 0 : route[j - 1], after = j == route.length ? 0 : route[j];
          final increase = distance(before, id) + distance(id, after) - distance(before, after);
          if (best == null || increase < best) { best = increase; chosen = id; position = j; }
        }
      }
      route.insert(position, chosen);
      remaining.remove(chosen);
    }
    tour = route;
  } else if (command == 'EXACT') {
    if (stops.length > 10) fail('too many stops for exact (${stops.length})');
    tour = exact();
  }
  if (['ORDER', 'NEAREST', 'INSERTION', 'EXACT'].contains(command)) {
    output.add('${command.toLowerCase()}: ${notation(tour!)} length ${length(tour!)}');
    return;
  }
  if (command == 'TOUR') { final route = requireTour(); output.add('tour: ${notation(route)} length ${length(route)}'); return; }
  if (['TWOOPT', 'OROPT', 'SWAP'].contains(command)) {
    final route = requireTour(), old = length(requireTour());
    var moves = 0;
    if (command == 'TWOOPT') { moves = twoOpt(route, true); }
    else {
      while (true) {
        var changed = false;
        if (command == 'SWAP') {
          scan: for (var i = 0; i + 1 < route.length; i++) {
            for (var j = i + 1; j < route.length; j++) {
              final next = List<int>.of(route), temp = route[i];
              next[i] = next[j];
              next[j] = temp;
              final gain = length(route) - length(next);
              if (gain > 0) {
                output.add('swap ${route[i]} and ${route[j]} gain $gain');
                route..clear()..addAll(next);
                moves++;
                changed = true;
                break scan;
              }
            }
          }
        } else {
          scan: for (var size = 1; size <= 3; size++) {
            for (var i = 0; i + size <= route.length; i++) {
              final segment = route.sublist(i, i + size), rest = [...route.take(i), ...route.skip(i + size)];
              for (var j = 0; j <= rest.length; j++) {
                if (j == i) continue;
                final next = [...rest.take(j), ...segment, ...rest.skip(j)], gain = length(route) - length([...rest.take(j), ...segment, ...rest.skip(j)]);
                if (gain > 0) {
                  output.add('move ${segment.join('-')} after ${location(j == 0 ? 0 : rest[j - 1])} gain $gain');
                  route..clear()..addAll(next);
                  moves++;
                  changed = true;
                  break scan;
                }
              }
            }
          }
        }
        if (!changed) break;
      }
    }
    output.add('${command.toLowerCase()}: moves $moves, length $old -> ${length(route)}');
    return;
  }
  if (command == 'TIMECHECK') {
    List<int> route;
    if (args.isEmpty) { route = requireTour(); }
    else {
      final value = requirePlan();
      if (a > value.routes.length) fail('no route $a');
      route = value.routes[a - 1];
    }
    output.add('timecheck ${args.isEmpty ? 'tour' : 'route $a'} depart ${clock(departure)}');
    simulate(route, true);
    return;
  }
  if (command == 'BOUND') {
    final names = ids();
    final (mst, edges) = spanning(names, 0);
    final near = names.map((id) => distance(0, id)).toList()..sort();
    final oneTree = names.length == 1 ? 2 * near[0] : spanning(names, names[0]).$1 + near[0] + near[1];
    final bound = math.max(mst, oneTree);
    output.addAll(['mst: ${edges.join(' ')} (length $mst)', 'bound: mst $mst, one-tree $oneTree, best $bound',
      tour == null ? 'gap: no tour' : 'gap: tour ${length(tour!)}, ${decimal(bound > 0 ? (2000 * (length(tour!) - bound) + bound) ~/ (2 * bound) : 0)}%']);
    return;
  }
  if (command == 'VRP' || command == 'SWEEP' || command == 'SPLIT') {
    if (command == 'SPLIT') requireTour();
    checkCapacity(a);
    List<List<int>> routes;
    var merges = 0;
    if (command == 'VRP') {
      final limit = args.length > 1 ? b : null;
      if (limit != null) {
        for (final id in ids()) { if (2 * distance(0, id) > limit) fail('stop $id too far for limit $limit'); }
      }
      routes = ids().map((id) => [id]).toList();
      final pairs = <Saving>[];
      for (final i in ids()) {
        for (final j in ids()) {
          if (i >= j) continue;
          final saving = distance(0, i) + distance(0, j) - distance(i, j);
          if (saving > 0) pairs.add(Saving(i, j, saving));
        }
      }
      pairs.sort((a, b) {
        final order = b.saving.compareTo(a.saving), first = a.i.compareTo(b.i);
        return order != 0 ? order : first != 0 ? first : a.j.compareTo(b.j);
      });
      for (final pair in pairs) {
        final x = routes.indexWhere((route) => route.contains(pair.i)), y = routes.indexWhere((route) => route.contains(pair.j));
        final first = routes[x], second = routes[y];
        if (x == y || ![first.first, first.last].contains(pair.i) || ![second.first, second.last].contains(pair.j) || load(first) + load(second) > a) continue;
        final joined = [...(first.last == pair.i ? first : first.reversed), ...(second.first == pair.j ? second : second.reversed)];
        if (limit != null && length(joined) > limit) continue;
        routes = [for (var i = 0; i < routes.length; i++) if (i != x && i != y) routes[i]];
        routes.add(joined);
        merges++;
      }
    } else if (command == 'SPLIT') {
      final route = requireTour(), previous = List<int>.filled(requireTour().length + 1, -1);
      final values = List<int?>.filled(route.length + 1, null);
      values[0] = 0;
      for (var j = 1; j <= route.length; j++) {
        for (var i = 0; i < j; i++) {
          final segment = route.sublist(i, j), candidate = values[i]! + length(route.sublist(i, j));
          if (load(segment) <= a && (values[j] == null || candidate < values[j]!)) { values[j] = candidate; previous[j] = i; }
        }
      }
      routes = [];
      for (var j = route.length; j > 0; j = previous[j]) { routes.add(route.sublist(previous[j], j)); }
    } else {
      final ordered = ids()..sort((a, b) {
        final x = stops[a]!, y = stops[b]!;
        final dx = x.x - depot!.x, dy = x.y - depot!.y, ex = y.x - depot!.x, ey = y.y - depot!.y;
        final zeroA = dx == 0 && dy == 0, zeroB = ex == 0 && ey == 0;
        if (zeroA || zeroB) return zeroA && zeroB ? a.compareTo(b) : zeroA ? -1 : 1;
        final halfA = dy > 0 || dy == 0 && dx > 0 ? 0 : 1, halfB = ey > 0 || ey == 0 && ex > 0 ? 0 : 1;
        if (halfA != halfB) return halfA.compareTo(halfB);
        final cross = dx * ey - dy * ex;
        if (cross != 0) return cross > 0 ? -1 : 1;
        final order = distance(0, a).compareTo(distance(0, b));
        return order == 0 ? a.compareTo(b) : order;
      });
      routes = [<int>[]];
      for (final id in ordered) {
        if (load(routes.last) + stops[id]!.demand > a) routes.add([]);
        routes.last.add(id);
      }
    }
    plan = Plan(a, normalize(routes));
    output.add('${command.toLowerCase()}: capacity $a${command == 'VRP' ? ', merges $merges' : ''}, routes ${plan!.routes.length}, length ${planLength(plan!)}');
    routeLines(plan!);
    return;
  }
  if (command == 'ROUTES') {
    final value = requirePlan();
    output.add('plan: capacity ${value.capacity}, routes ${value.routes.length}, length ${planLength(value)}');
    routeLines(value);
    return;
  }
  if (['RELOCATE', 'EXCHANGE', 'CROSS'].contains(command)) { improvePlan(command); return; }
  if (command == 'ROUTEOPT') {
    final value = requirePlan(), old = planLength(requirePlan());
    for (var i = 0; i < value.routes.length; i++) {
      final route = value.routes[i], before = length(value.routes[i]), moves = twoOpt(value.routes[i], false);
      output.add('route ${i + 1}: moves $moves, length $before -> ${length(route)}');
    }
    value.routes = normalize(value.routes);
    output.add('routeopt: length $old -> ${planLength(value)}');
    return;
  }
  if (command == 'REPORT') {
    final all = stops.values;
    output.add('report: stops ${stops.length}, demand ${all.fold<int>(0, (sum, stop) => sum + stop.demand)}, service ${all.fold<int>(0, (sum, stop) => sum + stop.service)}, windows ${all.where((stop) => stop.open != null).length}');
    if (tour == null) { output.add('tour: none'); }
    else { final result = simulate(tour!); output.add('tour: length ${length(tour!)}, return ${clock(result.time)}, violations ${result.violations}, lateness ${result.lateness}'); }
    if (plan == null) { output.add('plan: none'); }
    else {
      final value = plan!, results = plan!.routes.map((route) => simulate(route)).toList();
      final denominator = value.routes.length * value.capacity;
      final utilization = (2000 * value.routes.fold<int>(0, (sum, route) => sum + load(route)) + denominator) ~/ (2 * denominator);
      output.add('plan: capacity ${value.capacity}, routes ${value.routes.length}, length ${planLength(value)}, utilization ${decimal(utilization)}%, return ${clock(results.map((result) => result.time).reduce(math.max))}, violations ${results.fold<int>(0, (sum, result) => sum + result.violations)}, lateness ${results.fold<int>(0, (sum, result) => sum + result.lateness)}');
    }
  }
}
void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try { execute(stdin.readLineSync()!); }
    on RouteError catch (error) { output.add(error.message); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
