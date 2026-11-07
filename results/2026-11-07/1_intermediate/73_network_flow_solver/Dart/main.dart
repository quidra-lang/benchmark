import 'dart:io';
import 'dart:math' as math;

class Edge {
  int u, v, capacity, cost, lower, flow;
  Edge(this.u, this.v, this.capacity, this.cost, [this.lower = 0, this.flow = 0]);
  Edge copy() => Edge(u, v, capacity, cost, lower);
}
class Owner {
  final String kind;
  final int source, sink;
  Owner(this.kind, [this.source = -1, this.sink = -1]);
}
class Network {
  List<String> names = [];
  List<Edge> edges = [];
  List<int> demands = [];
  Owner owner = Owner('none');
  Network copy() => Network()
    ..names = List.of(names)
    ..demands = List.of(demands)
    ..edges = edges.map((edge) => edge.copy()).toList();
}
class Arc {
  final int edge, from, to;
  final bool forward;
  Arc(this.edge, this.forward, this.from, this.to);
}
class Augmentation {
  final List<Arc> path;
  final int amount, phase, delta, cost;
  Augmentation(this.path, this.amount, {this.phase = 0, this.delta = 1, this.cost = 0});
}
class Decomposition {
  final bool cycle;
  final int start, amount;
  final List<int> edges;
  Decomposition(this.cycle, this.start, this.edges, this.amount);
}
class BreadthFirst {
  final List<int> level;
  final List<Arc?> parent;
  BreadthFirst(this.level, this.parent);
}
class Cheapest {
  final List<Arc> path;
  final int cost;
  Cheapest(this.path, this.cost);
}
class FlowError implements Exception {
  final String message;
  FlowError(this.message);
}
final network = Network();
final output = <String>[];
Never fail(String message) => throw FlowError('ERROR $message');
int vertex(String name) {
  final index = network.names.indexOf(name);
  if (index < 0) fail('UNKNOWN NODE $name');
  return index;
}
(int, int) endpoints(String a, String b) {
  final source = vertex(a), sink = vertex(b);
  if (source == sink) fail('SAME NODE');
  return (source, sink);
}
Edge edgeAt(String word) {
  final index = int.parse(word) - 1;
  if (index < 0 || index >= network.edges.length) fail('UNKNOWN EDGE $word');
  return network.edges[index];
}
List<int> balances(Network net) {
  final result = List<int>.filled(net.names.length, 0);
  for (final edge in net.edges) {
    result[edge.u] += edge.flow;
    result[edge.v] -= edge.flow;
  }
  return result;
}
int totalCost(Network net) => net.edges.fold<int>(0, (sum, edge) => sum + edge.flow * edge.cost);
List<Arc> globalArcs(Network net) => [
  for (var i = 0; i < net.edges.length; i++) Arc(i, true, net.edges[i].u, net.edges[i].v),
  for (var i = 0; i < net.edges.length; i++) Arc(i, false, net.edges[i].v, net.edges[i].u)
];
List<List<Arc>> adjacency(Network net) {
  final result = List.generate(net.names.length, (_) => <Arc>[]);
  for (final arc in globalArcs(net)) { result[arc.from].add(arc); }
  return result;
}
int residual(Network net, Arc arc) {
  final edge = net.edges[arc.edge];
  return arc.forward ? edge.capacity - edge.flow : edge.flow;
}
void push(Network net, List<Arc> path, int amount) {
  for (final arc in path) { net.edges[arc.edge].flow += arc.forward ? amount : -amount; }
}
int bottleneck(Network net, List<Arc> path) => path.map((arc) => residual(net, arc)).reduce(math.min);
BreadthFirst bfs(Network net, int source, [int threshold = 1]) {
  final level = List<int>.filled(net.names.length, -1);
  final parent = List<Arc?>.filled(net.names.length, null), queue = <int>[source];
  final lists = adjacency(net);
  level[source] = 0;
  for (var i = 0; i < queue.length; i++) {
    final u = queue[i];
    for (final arc in lists[u]) {
      if (residual(net, arc) >= threshold && level[arc.to] < 0) {
        level[arc.to] = level[u] + 1;
        parent[arc.to] = arc;
        queue.add(arc.to);
      }
    }
  }
  return BreadthFirst(level, parent);
}
List<Arc> restorePath(List<Arc?> parent, int source, int sink) {
  final result = <Arc>[];
  for (var at = sink; at != source;) {
    final arc = parent[at]!;
    result.add(arc);
    at = arc.from;
  }
  return result.reversed.toList();
}
Augmentation? single(Network net, int source, int sink, [int threshold = 1]) {
  final search = bfs(net, source, threshold);
  if (search.level[sink] < 0) return null;
  final path = restorePath(search.parent, source, sink), amount = bottleneck(net, path);
  push(net, path, amount);
  return Augmentation(path, amount, delta: threshold);
}
List<Augmentation> edmondsKarp(Network net, int source, int sink) {
  final paths = <Augmentation>[];
  while (true) {
    final augmentation = single(net, source, sink);
    if (augmentation == null) return paths;
    paths.add(augmentation);
  }
}
(List<Augmentation>, int) dinic(Network net, int source, int sink) {
  final paths = <Augmentation>[], lists = adjacency(net);
  var phases = 0;
  while (true) {
    final level = bfs(net, source).level;
    if (level[sink] < 0) return (paths, phases);
    phases++;
    final pointers = List<int>.filled(net.names.length, 0);
    var path = <Arc>[], current = source;
    while (true) {
      if (current == sink) {
        final amount = bottleneck(net, path);
        push(net, path, amount);
        paths.add(Augmentation(List.of(path), amount, phase: phases));
        path = [];
        current = source;
      } else if (pointers[current] >= lists[current].length) {
        if (current == source) break;
        final arc = path.removeLast();
        current = arc.from;
        pointers[current]++;
      } else {
        final arc = lists[current][pointers[current]];
        if (residual(net, arc) > 0 && level[arc.to] == level[current] + 1) {
          path.add(arc);
          current = arc.to;
        } else {
          pointers[current]++;
        }
      }
    }
  }
}
List<Augmentation> scaling(Network net, int source, int sink) {
  final paths = <Augmentation>[];
  final maximum = net.edges.fold<int>(1, (value, edge) => math.max(value, edge.capacity));
  var delta = 1;
  while (delta * 2 <= maximum) { delta *= 2; }
  while (delta >= 1) {
    while (true) {
      final augmentation = single(net, source, sink, delta);
      if (augmentation == null) break;
      paths.add(augmentation);
    }
    delta ~/= 2;
  }
  return paths;
}
bool negativeCycle(Network net, [bool lowerBounds = false]) {
  final distance = List<int>.filled(net.names.length, 0);
  for (var pass = 0; pass < net.names.length; pass++) {
    var changed = false;
    for (final edge in net.edges) {
      if (edge.capacity - (lowerBounds ? edge.lower : 0) > 0 && distance[edge.v] > distance[edge.u] + edge.cost) {
        distance[edge.v] = distance[edge.u] + edge.cost;
        changed = true;
      }
    }
    if (!changed) return false;
    if (pass + 1 == net.names.length) return true;
  }
  return false;
}
Cheapest? shortest(Network net, int source, int sink) {
  final arcs = globalArcs(net).where((arc) => residual(net, arc) > 0).toList();
  final distance = List<int?>.filled(net.names.length, null), parent = List<Arc?>.filled(net.names.length, null);
  distance[source] = 0;
  while (true) {
    var changed = false;
    for (final arc in arcs) {
      if (distance[arc.from] == null) continue;
      final cost = net.edges[arc.edge].cost * (arc.forward ? 1 : -1);
      final next = distance[arc.from]! + cost;
      if (distance[arc.to] == null || next < distance[arc.to]!) {
        distance[arc.to] = next;
        parent[arc.to] = arc;
        changed = true;
      }
    }
    if (!changed) break;
  }
  return distance[sink] == null ? null : Cheapest(restorePath(parent, source, sink), distance[sink]!);
}
(List<Augmentation>, int, int) minCost(Network net, int source, int sink, [int? target]) {
  final paths = <Augmentation>[];
  var flow = 0, cost = 0;
  while (target == null || flow < target) {
    final cheapest = shortest(net, source, sink);
    if (cheapest == null) break;
    final amount = target == null ? bottleneck(net, cheapest.path) : math.min(bottleneck(net, cheapest.path), target - flow);
    push(net, cheapest.path, amount);
    flow += amount;
    cost += amount * cheapest.cost;
    paths.add(Augmentation(cheapest.path, amount, cost: cheapest.cost));
  }
  return (paths, flow, cost);
}
List<Decomposition> decompose(Network net) {
  final remaining = net.edges.map((edge) => edge.flow).toList(), balance = balances(net);
  final result = <Decomposition>[];
  while (remaining.any((value) => value > 0)) {
    var start = balance.indexWhere((value) => value > 0);
    if (start < 0) start = net.edges[remaining.indexWhere((value) => value > 0)].u;
    final vertices = <int>[start], edges = <int>[];
    while (true) {
      final current = vertices.last;
      var index = 0;
      while (net.edges[index].u != current || remaining[index] <= 0) { index++; }
      final next = net.edges[index].v;
      edges.add(index);
      final repeat = vertices.indexOf(next);
      if (repeat >= 0) {
        final cycle = edges.sublist(repeat), amount = edges.sublist(repeat).map((i) => remaining[i]).reduce(math.min);
        for (final i in cycle) { remaining[i] -= amount; }
        result.add(Decomposition(true, next, cycle, amount));
        break;
      }
      vertices.add(next);
      if (balance[next] < 0) {
        final amount = math.min(edges.map((i) => remaining[i]).reduce(math.min), math.min(balance[start], -balance[next]));
        for (final i in edges) { remaining[i] -= amount; }
        balance[start] -= amount;
        balance[next] += amount;
        result.add(Decomposition(false, start, List.of(edges), amount));
        break;
      }
    }
  }
  return result;
}
String pathText(Network net, List<Arc> path, int source) => [net.names[source],
  for (final arc in path) ...['${arc.forward ? '+' : '-'}${arc.edge + 1}', net.names[arc.to]]].join(' ');
String decompositionText(Network net, Decomposition item, [int? originalEdges]) => [net.names[item.start],
  for (final i in item.edges) if (originalEdges == null || i < originalEdges) ...['+${i + 1}', net.names[net.edges[i].v]]].join(' ');
void flowList() {
  for (var i = 0; i < network.edges.length; i++) {
    final edge = network.edges[i];
    output.add('FLOW ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} ${edge.flow}/${edge.capacity}');
  }
}
int startFlow(int source, int sink) {
  if (network.owner.kind != 'flow' || network.owner.source != source || network.owner.sink != sink) {
    for (final edge in network.edges) { edge.flow = 0; }
  }
  network.owner = Owner('flow', source, sink);
  return balances(network)[source];
}
void matching(String a, String b, String pairs) {
  final left = a.split(','), right = b.split(',');
  final links = pairs == '-' ? <(String, String)>[] : pairs.split(',').map((pair) {
    final parts = pair.split('-');
    return (parts[0], parts[1]);
  }).toList();
  final seen = <String>{};
  for (final name in [...left, ...right]) {
    if (!seen.add(name)) fail('DUPLICATE VERTEX $name');
  }
  final used = <String>{};
  for (final (u, v) in links) {
    if (!left.contains(u)) fail('UNKNOWN VERTEX $u');
    if (!right.contains(v)) fail('UNKNOWN VERTEX $v');
    if (!used.add('$u-$v')) fail('DUPLICATE PAIR $u-$v');
  }
  final partnerLeft = <String, String>{}, partnerRight = <String, String>{};
  bool attempt(String name, Set<String> examined) {
    for (final (u, v) in links) {
      if (u == name && examined.add(v)) {
        if (!partnerRight.containsKey(v) || attempt(partnerRight[v]!, examined)) {
          partnerLeft[u] = v;
          partnerRight[v] = u;
          return true;
        }
      }
    }
    return false;
  }
  for (final name in left) { attempt(name, {}); }
  final free = left.where((name) => !partnerLeft.containsKey(name)).toList();
  final zl = free.toSet(), zr = <String>{}, queue = List.of(free);
  for (var i = 0; i < queue.length; i++) {
    for (final (u, v) in links) {
      if (u == queue[i] && partnerLeft[u] != v && zr.add(v)) {
        final partner = partnerRight[v];
        if (partner != null && zl.add(partner)) queue.add(partner);
      }
    }
  }
  final cover = [...left.where((name) => !zl.contains(name)), ...right.where(zr.contains)];
  output.add('MATCH size=${partnerLeft.length} left=${left.length} right=${right.length}');
  for (final name in left) {
    if (partnerLeft.containsKey(name)) output.add('PAIR $name ${partnerLeft[name]}');
  }
  final freeRight = right.where((name) => !partnerRight.containsKey(name)).toList();
  output.add('FREE ${free.isEmpty ? '-' : free.join(',')} ${freeRight.isEmpty ? '-' : freeRight.join(',')}');
  output.add('COVER size=${cover.length}${cover.isEmpty ? '' : ' ${cover.join(' ')}'}');
  if (free.isNotEmpty) {
    final rightHall = right.where(zr.contains).toList();
    output.add('HALL ${left.where(zl.contains).join(',')} ${rightHall.isEmpty ? '-' : rightHall.join(',')}');
  }
}
void assignment(String mode, int size, List<String> words) {
  if (size < 1 || size > 8) fail('BAD SIZE');
  if (words.length != size * size) fail('BAD LENGTH');
  int? best;
  var count = 0, chosen = <int>[];
  final current = <int>[];
  void visit(int row, int used, int sum) {
    if (row == size) {
      if (best == null || (mode == 'MIN' ? sum < best! : sum > best!)) {
        best = sum;
        count = 1;
        chosen = List.of(current);
      } else if (sum == best) {
        count++;
      }
      return;
    }
    for (var col = 0; col < size; col++) {
      if ((used & (1 << col)) == 0 && words[row * size + col] != 'x') {
        current.add(col);
        visit(row + 1, used | (1 << col), sum + int.parse(words[row * size + col]));
        current.removeLast();
      }
    }
  }
  visit(0, 0, 0);
  if (best == null) {
    output.add('ASSIGN $mode n=$size infeasible');
  } else {
    output.add('ASSIGN $mode n=$size total=$best optimal=$count');
    for (var row = 0; row < size; row++) {
      final col = chosen[row];
      output.add('MATE ${row + 1} ${col + 1} ${words[row * size + col]}');
    }
  }
}
void execute(String commandLine) {
  final words = commandLine.split(' '), command = words.first, args = words.skip(1).toList();
  final a = args.isEmpty ? '' : args[0], b = args.length < 2 ? '' : args[1];
  switch (command) {
    case 'NODE':
      final seen = network.names.toSet();
      for (final name in args) {
        if (!seen.add(name)) fail('DUPLICATE NODE $name');
      }
      if (network.names.length + args.length > 20) fail('TOO MANY NODES');
      network.names.addAll(args);
      network.demands.addAll(args.map((_) => 0));
      output.add('NODE added=${args.length} total=${network.names.length}');
    case 'EDGE':
      final u = vertex(a), v = vertex(b);
      if (u == v) fail('SELF LOOP');
      if (network.edges.length == 60) fail('TOO MANY EDGES');
      final capacity = int.parse(args[2]), cost = args.length > 3 ? int.parse(args[3]) : 0;
      network.edges.add(Edge(u, v, capacity, cost));
      output.add('EDGE ${network.edges.length} $a $b cap=$capacity cost=$cost');
    case 'LOWER':
      final edge = edgeAt(a), lower = int.parse(b);
      if (lower > edge.capacity) fail('BAD BOUND');
      edge.lower = lower;
      output.add('LOWER $a low=$lower cap=${edge.capacity}');
    case 'CAP':
      final edge = edgeAt(a), capacity = int.parse(b);
      if (capacity < edge.lower) fail('BAD BOUND');
      if (capacity < edge.flow) fail('BELOW FLOW');
      edge.capacity = capacity;
      output.add('CAP $a low=${edge.lower} cap=$capacity');
    case 'COST':
      final edge = edgeAt(a);
      edge.cost = int.parse(b);
      output.add('COST $a cost=$b');
    case 'DEMAND':
      final index = vertex(a);
      network.demands[index] = int.parse(b);
      output.add('DEMAND $a $b total=${network.demands.fold<int>(0, (sum, demand) => sum + demand)}');
    case 'RESET':
      final count = network.edges.where((edge) => edge.flow != 0).length;
      for (final edge in network.edges) { edge.flow = 0; }
      network.owner = Owner('none');
      output.add('RESET edges=$count');
    case 'CLEAR':
      output.add('CLEAR nodes=${network.names.length} edges=${network.edges.length}');
      network.names = [];
      network.demands = [];
      network.edges = [];
      network.owner = Owner('none');
    case 'SHOW':
      final out = List<int>.filled(network.names.length, 0), incoming = List<int>.filled(network.names.length, 0);
      for (final edge in network.edges) {
        out[edge.u] += edge.flow;
        incoming[edge.v] += edge.flow;
      }
      final owner = network.owner;
      output.add('NETWORK nodes=${network.names.length} edges=${network.edges.length}');
      output.add(owner.kind == 'none' ? 'STATE none' : owner.kind == 'circulation'
          ? 'STATE circulation cost=${totalCost(network)}'
          : 'STATE flow ${network.names[owner.source]} ${network.names[owner.sink]} value=${balances(network)[owner.source]} cost=${totalCost(network)}');
      for (var i = 0; i < network.names.length; i++) {
        output.add('NODE ${network.names[i]} demand=${network.demands[i]} out=${out[i]} in=${incoming[i]}');
      }
      for (var i = 0; i < network.edges.length; i++) {
        final edge = network.edges[i];
        output.add('EDGE ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} cap=${edge.capacity} cost=${edge.cost} low=${edge.lower} flow=${edge.flow}');
      }
    case 'AUGMENT':
    case 'MAXFLOW':
    case 'DINIC':
    case 'SCALING':
    case 'MINCUT':
      final (source, sink) = endpoints(a, b);
      final start = startFlow(source, sink);
      if (command == 'AUGMENT') {
        final augmentation = single(network, source, sink);
        output.add('AUGMENT $a $b value=${balances(network)[source]}${augmentation == null ? ' none' : ' amount=${augmentation.amount} ${pathText(network, augmentation.path, source)}'}');
      } else {
        final (paths, phases) = command == 'DINIC' ? dinic(network, source, sink)
            : (command == 'SCALING' ? scaling(network, source, sink) : edmondsKarp(network, source, sink), 0);
        final value = balances(network)[source];
        if (command == 'MINCUT') {
          final level = bfs(network, source).level;
          final cut = [for (var i = 0; i < network.edges.length; i++)
            if (level[network.edges[i].u] >= 0 && level[network.edges[i].v] < 0) i];
          output.add('MINCUT $a $b value=$value edges=${cut.length}');
          output.add('SOURCE ${[for (var i = 0; i < network.names.length; i++) if (level[i] >= 0) network.names[i]].join(' ')}');
          output.add('SINK ${[for (var i = 0; i < network.names.length; i++) if (level[i] < 0) network.names[i]].join(' ')}');
          for (final i in cut) {
            final edge = network.edges[i];
            output.add('CUT ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} ${edge.capacity}');
          }
        } else {
          output.add('$command $a $b value=$value start=$start${command == 'DINIC' ? ' phases=$phases' : ''} paths=${paths.length}');
          for (var i = 0; i < paths.length; i++) {
            final item = paths[i];
            output.add('AUG ${i + 1}${command == 'DINIC' ? ' phase=${item.phase}' : command == 'SCALING' ? ' delta=${item.delta}' : ''} amount=${item.amount} ${pathText(network, item.path, source)}');
          }
          flowList();
        }
      }
    case 'SENSITIVITY':
      final (source, sink) = endpoints(a, b);
      final base = network.copy();
      edmondsKarp(base, source, sink);
      final value = balances(base)[source], effective = <(bool, bool)>[];
      for (var i = 0; i < network.edges.length; i++) {
        final up = network.copy();
        up.edges[i].capacity++;
        edmondsKarp(up, source, sink);
        var downEffective = false;
        if (network.edges[i].capacity > 0) {
          final down = network.copy();
          down.edges[i].capacity--;
          edmondsKarp(down, source, sink);
          downEffective = balances(down)[source] < value;
        }
        effective.add((balances(up)[source] > value, downEffective));
      }
      output.add('SENSITIVITY $a $b value=$value up=${effective.where((item) => item.$1).length} down=${effective.where((item) => item.$2).length}');
      for (var i = 0; i < effective.length; i++) {
        final (up, down) = effective[i];
        final edge = network.edges[i];
        if (up || down) output.add('CRITICAL ${i + 1} ${network.names[edge.u]} ${network.names[edge.v]} up=${up ? 'yes' : 'no'} down=${down ? 'yes' : 'no'}');
      }
    case 'MINCOST':
      final (source, sink) = endpoints(a, b);
      if (negativeCycle(network)) fail('NEGATIVE CYCLE');
      final working = network.copy(), target = args[2] == 'MAX' ? null : int.parse(args[2]);
      final (paths, flow, cost) = minCost(working, source, sink, target);
      if (target != null && flow < target) {
        output.add('MINCOST $a $b k=${args[2]} infeasible max=$flow');
      } else {
        for (var i = 0; i < network.edges.length; i++) { network.edges[i].flow = working.edges[i].flow; }
        network.owner = Owner('flow', source, sink);
        output.add('MINCOST $a $b k=${args[2]} flow=$flow cost=$cost');
        for (var i = 0; i < paths.length; i++) {
          final item = paths[i];
          output.add('AUG ${i + 1} amount=${item.amount} cost=${item.cost} ${pathText(working, item.path, source)}');
        }
        flowList();
      }
    case 'DISJOINT':
      final (source, sink) = endpoints(a, b);
      final working = network.copy(), original = network.edges.length;
      for (final edge in working.edges) { edge.capacity = edge.capacity > 0 ? 1 : 0; }
      if (args[2] == 'VERTEX') {
        final exits = List.generate(working.names.length, (i) => i);
        for (var i = 0; i < network.names.length; i++) {
          if (i != source && i != sink) {
            exits[i] = working.names.length;
            working.names.add(network.names[i]);
            working.demands.add(0);
          }
        }
        for (final edge in working.edges) { edge.u = exits[edge.u]; }
        for (var i = 0; i < network.names.length; i++) {
          if (i != source && i != sink) working.edges.add(Edge(i, exits[i], 1, 0));
        }
      }
      edmondsKarp(working, source, sink);
      final paths = decompose(working).where((item) => !item.cycle).toList();
      output.add('DISJOINT $a $b ${args[2]} count=${paths.length}');
      for (var i = 0; i < paths.length; i++) {
        output.add('PATH ${i + 1} ${decompositionText(working, paths[i], original)}');
      }
    case 'DECOMPOSE':
      final pieces = decompose(network);
      output.add('DECOMPOSE paths=${pieces.where((item) => !item.cycle).length} cycles=${pieces.where((item) => item.cycle).length}');
      var paths = 0, cycles = 0;
      for (final item in pieces) {
        output.add('${item.cycle ? 'CYCLE' : 'PATH'} ${item.cycle ? ++cycles : ++paths} amount=${item.amount} ${decompositionText(network, item)}');
      }
    case 'VERIFY':
      final violations = <String>[], balance = balances(network);
      for (var i = 0; i < network.edges.length; i++) {
        final edge = network.edges[i];
        if (edge.flow < edge.lower) violations.add('LOW ${i + 1} flow=${edge.flow} low=${edge.lower}');
      }
      for (var i = 0; i < network.names.length; i++) {
        if (network.owner.kind == 'flow' && (network.owner.source == i || network.owner.sink == i)) continue;
        final need = network.owner.kind == 'flow' ? 0 : network.demands[i];
        if (-balance[i] != need) violations.add('BALANCE ${network.names[i]} net=${-balance[i]} need=$need');
      }
      output.addAll(violations.isEmpty ? ['VERIFY ok'] : ['VERIFY violations=${violations.length}', ...violations]);
    case 'CIRCULATION':
      if (a == 'MINCOST' && negativeCycle(network, true)) fail('NEGATIVE CYCLE');
      final sum = network.demands.fold<int>(0, (total, demand) => total + demand);
      if (sum != 0) {
        output.add('CIRCULATION infeasible unbalanced=$sum');
      } else {
        final working = network.copy(), balance = List<int>.of(network.demands);
        final source = working.names.length, sink = source + 1;
        working.names.addAll(['superSource', 'superSink']);
        working.demands.addAll([0, 0]);
        for (var i = 0; i < network.edges.length; i++) {
          final edge = working.edges[i], lower = network.edges[i].lower;
          edge.capacity -= lower;
          balance[edge.u] += lower;
          balance[edge.v] -= lower;
        }
        for (var i = 0; i < balance.length; i++) {
          if (balance[i] < 0) working.edges.add(Edge(source, i, -balance[i], 0));
        }
        for (var i = 0; i < balance.length; i++) {
          if (balance[i] > 0) working.edges.add(Edge(i, sink, balance[i], 0));
        }
        if (a == 'ANY') { edmondsKarp(working, source, sink); } else { minCost(working, source, sink); }
        final required = balance.where((value) => value > 0).fold<int>(0, (total, value) => total + value);
        final achieved = working.edges.where((edge) => edge.v == sink).fold<int>(0, (total, edge) => total + edge.flow);
        if (achieved < required) {
          final level = bfs(working, source).level;
          output.add('CIRCULATION infeasible required=$required achieved=$achieved');
          output.add('CUT ${[for (var i = 0; i < network.names.length; i++) if (level[i] >= 0) network.names[i]].join(' ')}');
        } else {
          for (var i = 0; i < network.edges.length; i++) { network.edges[i].flow = network.edges[i].lower + working.edges[i].flow; }
          network.owner = Owner('circulation');
          output.add('CIRCULATION feasible required=$required cost=${totalCost(network)}');
          flowList();
        }
      }
    case 'MATCH':
      matching(a, b, args[2]);
    case 'ASSIGN':
      assignment(a, int.parse(b), args.skip(2).toList());
  }
}
void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try { execute(stdin.readLineSync()!); }
    on FlowError catch (error) { output.add(error.message); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
