import 'dart:io';
import 'dart:math';
part 'graph_io.dart';
part 'acyclic_layering.dart';
part 'crossing.dart';
part 'coordinates.dart';
part 'canvas.dart';

class Edge {
  final int from, to;
  int upper = 0, lower = 0, span = 0, crossings = 0, bends = 0, length = 0;
  bool reversed = false, transitive = false;
  final List<int> chain = [], segments = [];
  List<Cell> route = [];
  Edge(this.from, this.to);
}

class Vertex {
  final String name;
  final int width, left, right;
  int layer, x = 0;
  final List<int> upper = [], lower = [];
  Vertex(
    this.name,
    this.width, {
    this.layer = 0,
    this.left = 0,
    this.right = 0,
  });
}

class Segment {
  final int upper, lower, edge, gap;
  int offset = 0;
  Segment(this.upper, this.lower, this.edge, this.gap);
}

class Sweep {
  final int run, number, moved, swaps, crossings;
  final String direction;
  Sweep(
    this.run,
    this.number,
    this.moved,
    this.swaps,
    this.crossings,
    this.direction,
  );
}

class Sift {
  final int round, moves, crossings;
  Sift(this.round, this.moves, this.crossings);
}

class Layout {
  final Block block;
  final int n;
  final List<Vertex> vertices = [];
  final List<Edge> edges = [];
  final List<Segment> segments = [];
  List<List<int>> gaps = [], orders = [];
  List<int> acyclic = [];
  late LayeringResult layering;
  late Coordinates coordinates;
  final List<Sweep> sweeps = [];
  final List<Sift> sifts = [];
  int bestRun = 0,
      bestSweep = 0,
      initialCrossings = 0,
      adoptedCrossings = 0,
      finalCrossings = 0,
      brute = 0,
      sources = 0,
      sinks = 0,
      isolated = 0,
      components = 0;
  final List<List<int>> scc = [];
  List<int> tracks = [], gapWidths = [], bandStarts = [], thickness = [];
  int mainLength = 0, secondaryLength = 0;
  late Canvas canvas;
  List<int> path = [];
  Layout(this.block) : n = block.nodes.length;
}

int compareInts(List<int> a, List<int> b) {
  for (var i = 0; i < min(a.length, b.length); i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

List<List<int>> cloneOrders(List<List<int>> orders) => [
  for (final row in orders) List<int>.of(row),
];
bool equalOrders(List<List<int>> a, List<List<int>> b) =>
    a.length == b.length &&
    List.generate(
      a.length,
      (i) => compareInts(a[i], b[i]) == 0,
    ).every((v) => v);
void graphAnalysis(Layout g) {
  final indegree = List.filled(g.n, 0),
      outdegree = List.filled(g.n, 0),
      weak = List.generate(g.n, (_) => <int>[]),
      reach = List.generate(g.n, (i) => List.generate(g.n, (j) => i == j));
  for (final e in g.edges) {
    outdegree[e.from]++;
    indegree[e.to]++;
    weak[e.from].add(e.to);
    weak[e.to].add(e.from);
    reach[e.from][e.to] = true;
  }
  for (var v = 0; v < g.n; v++) {
    if (indegree[v] == 0 && outdegree[v] > 0) g.sources++;
    if (outdegree[v] == 0 && indegree[v] > 0) g.sinks++;
    if (indegree[v] == 0 && outdegree[v] == 0) g.isolated++;
  }
  var seen = List.filled(g.n, false);
  for (var v = 0; v < g.n; v++) {
    if (seen[v]) continue;
    g.components++;
    final queue = [v];
    seen[v] = true;
    for (var h = 0; h < queue.length; h++) {
      for (final w in weak[queue[h]]) {
        if (!seen[w]) {
          seen[w] = true;
          queue.add(w);
        }
      }
    }
  }
  for (var k = 0; k < g.n; k++) {
    for (var i = 0; i < g.n; i++) {
      for (var j = 0; j < g.n; j++) {
        reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j]);
      }
    }
  }
  seen = List.filled(g.n, false);
  for (var v = 0; v < g.n; v++) {
    if (seen[v]) continue;
    final component = <int>[];
    for (var w = v; w < g.n; w++) {
      if (reach[v][w] && reach[w][v]) {
        seen[w] = true;
        component.add(w);
      }
    }
    if (component.length > 1) g.scc.add(component);
  }
}

Layout initialize(Block block) {
  final g = Layout(block),
      index = <int, int>{},
      horizontal =
          block.settings.direction == 'TB' || block.settings.direction == 'BT';
  for (var i = 0; i < block.nodes.length; i++) {
    final node = block.nodes[i],
        width = node.label.length + 2,
        left = horizontal ? (width - 1) ~/ 2 : 0;
    index[node.id] = i;
    g.vertices.add(
      Vertex(
        '${node.id}',
        width,
        left: left,
        right: horizontal ? width - 1 - left : 0,
      ),
    );
  }
  for (final e in block.edges) {
    g.edges.add(Edge(index[e.from]!, index[e.to]!));
  }
  graphAnalysis(g);
  g.acyclic = acyclic(g.n, g.edges);
  final rank = List.filled(g.n, 0);
  for (var i = 0; i < g.acyclic.length; i++) {
    rank[g.acyclic[i]] = i;
  }
  final allSuccessors = List.generate(g.n, (_) => <int>[]),
      reach = List.generate(g.n, (i) => List.generate(g.n, (j) => i == j));
  for (final e in g.edges) {
    e.upper = e.from;
    e.lower = e.to;
    if (rank[e.from] > rank[e.to]) {
      e.reversed = true;
      e.upper = e.to;
      e.lower = e.from;
    }
    allSuccessors[e.upper].add(e.lower);
    reach[e.upper][e.lower] = true;
  }
  for (var k = 0; k < g.n; k++) {
    for (var i = 0; i < g.n; i++) {
      for (var j = 0; j < g.n; j++) {
        reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j]);
      }
    }
  }
  if (block.settings.reduce == 'on') {
    for (final e in g.edges) {
      if (!e.reversed &&
          allSuccessors[e.upper].any((w) => w != e.lower && reach[w][e.lower]))
        e.transitive = true;
    }
  }
  final pre = List.generate(g.n, (_) => <int>[]),
      succ = List.generate(g.n, (_) => <int>[]);
  for (final e in g.edges) {
    if (!e.transitive) {
      pre[e.lower].add(e.upper);
      succ[e.upper].add(e.lower);
    }
  }
  for (var i = 0; i < g.n; i++) {
    pre[i].sort();
    succ[i].sort();
  }
  g.layering = assignLayers(g.n, pre, succ, block.settings);
  var maxHeight = 0;
  for (final h in g.layering.height) {
    maxHeight = max(maxHeight, h);
  }
  final used = {for (final h in g.layering.height) maxHeight - h};
  for (final e in g.edges) {
    if (e.transitive) continue;
    final a = maxHeight - g.layering.height[e.upper],
        b = maxHeight - g.layering.height[e.lower];
    for (var k = a + 1; k < b; k++) {
      used.add(k);
    }
  }
  final levels = used.toList()..sort(),
      renumber = {for (var i = 0; i < levels.length; i++) levels[i]: i};
  g.orders = List.generate(levels.length, (_) => <int>[]);
  g.gaps = List.generate(max(0, levels.length - 1), (_) => <int>[]);
  for (var i = 0; i < g.n; i++) {
    g.vertices[i].layer = renumber[maxHeight - g.layering.height[i]]!;
  }
  for (var edgeIndex = 0; edgeIndex < g.edges.length; edgeIndex++) {
    final e = g.edges[edgeIndex];
    if (e.transitive) continue;
    final a = g.vertices[e.upper].layer, b = g.vertices[e.lower].layer;
    e.span = b - a;
    e.chain.add(e.upper);
    for (var layer = a + 1; layer < b; layer++) {
      final v = g.vertices.length;
      g.vertices.add(Vertex('d${v - g.n + 1}', 1, layer: layer));
      e.chain.add(v);
    }
    e.chain.add(e.lower);
    for (var i = 0; i + 1 < e.chain.length; i++) {
      final u = e.chain[i],
          v = e.chain[i + 1],
          gap = g.vertices[u].layer,
          number = g.segments.length;
      g.segments.add(Segment(u, v, edgeIndex, gap));
      e.segments.add(number);
      g.gaps[gap].add(number);
      g.vertices[u].lower.add(v);
      g.vertices[v].upper.add(u);
    }
  }
  final visited = List.filled(g.vertices.length, false);
  void visit(int v) {
    if (visited[v]) return;
    visited[v] = true;
    g.orders[g.vertices[v].layer].add(v);
    for (final w in g.vertices[v].lower) {
      visit(w);
    }
  }

  for (var v = 0; v < g.n; v++) {
    visit(v);
  }
  return g;
}

void reorderLayer(Layout g, List<List<int>> orders, int layer, bool down) {
  final pos = positions(orders, g.vertices.length),
      slots = <int>[],
      vertices = <int>[],
      keys = <int, (int, int)>{};
  for (var j = 0; j < orders[layer].length; j++) {
    final v = orders[layer][j],
        reference = down ? g.vertices[v].upper : g.vertices[v].lower;
    if (reference.isEmpty) continue;
    slots.add(j);
    vertices.add(v);
    final values = [for (final u in reference) pos[u]];
    var sum = 0;
    for (final value in values) {
      sum += value;
    }
    var key = (sum, reference.length);
    if (g.block.settings.heuristic == 'median') {
      values.sort();
      key = (values[(values.length - 1) ~/ 2] + values[values.length ~/ 2], 1);
    }
    keys[v] = key;
  }
  vertices.sort((a, b) {
    final left = keys[a]!,
        right = keys[b]!,
        c = (left.$1 * right.$2).compareTo(right.$1 * left.$2);
    return c != 0 ? c : pos[a].compareTo(pos[b]);
  });
  for (var i = 0; i < slots.length; i++) {
    orders[layer][slots[i]] = vertices[i];
  }
}

int adjacentExchanges(Layout g, List<List<int>> orders) {
  var swaps = 0;
  final pos = positions(orders, g.vertices.length);
  while (true) {
    var changed = false;
    for (final row in orders) {
      for (var j = 0; j + 1 < row.length; j++) {
        final v = row[j], w = row[j + 1];
        if (adjacentCost(g, v, w, pos) > adjacentCost(g, w, v, pos)) {
          row[j] = w;
          row[j + 1] = v;
          pos[v] = j + 1;
          pos[w] = j;
          swaps++;
          changed = true;
        }
      }
    }
    if (!changed) return swaps;
  }
}

void reduceCrossings(Layout g) {
  final initial = cloneOrders(g.orders);
  var random = g.block.settings.seed, bestCrossings = -1;
  List<List<int>>? adopted;
  for (var run = 0; run <= g.block.settings.restarts; run++) {
    var orders = cloneOrders(initial);
    if (run > 0) {
      for (final row in orders) {
        for (var j = row.length - 1; j >= 1; j--) {
          random = 48271 * random % 2147483647;
          final k = random % (j + 1), temporary = row[j];
          row[j] = row[k];
          row[k] = temporary;
        }
      }
    }
    var crossings = totalCrossings(g, orders);
    g.sweeps.add(Sweep(run, 0, 0, 0, crossings, 'initial'));
    if (run == 0) g.initialCrossings = crossings;
    final history = [cloneOrders(orders)];
    var runBest = crossings, runSweep = 0, runOrder = cloneOrders(orders);
    for (var sweep = 1; ; sweep++) {
      final last = history.length - 1;
      if (crossings == 0 ||
          sweep - 1 == g.block.settings.sweeps ||
          (last >= 2 && equalOrders(history[last], history[last - 2])))
        break;
      final oldPos = positions(orders, g.vertices.length),
          down = sweep % 2 == 1;
      final direction = down ? 'down' : 'up';
      if (down) {
        for (var layer = 1; layer < orders.length; layer++) {
          reorderLayer(g, orders, layer, true);
        }
      } else {
        for (var layer = orders.length - 2; layer >= 0; layer--) {
          reorderLayer(g, orders, layer, false);
        }
      }
      final newPos = positions(orders, g.vertices.length);
      var moved = 0;
      for (var v = 0; v < oldPos.length; v++) {
        if (oldPos[v] != newPos[v]) moved++;
      }
      final swaps = adjacentExchanges(g, orders);
      crossings = totalCrossings(g, orders);
      g.sweeps.add(Sweep(run, sweep, moved, swaps, crossings, direction));
      history.add(cloneOrders(orders));
      if (crossings < runBest) {
        runBest = crossings;
        runSweep = sweep;
        runOrder = cloneOrders(orders);
      }
    }
    if (bestCrossings < 0 || runBest < bestCrossings) {
      bestCrossings = runBest;
      g.bestRun = run;
      g.bestSweep = runSweep;
      adopted = runOrder;
    }
  }
  g.adoptedCrossings = bestCrossings;
  g.orders = adopted!;
  if (g.block.settings.sifting == 'on') {
    for (var round = 1; ; round++) {
      var moves = 0;
      for (var v = 0; v < g.vertices.length; v++) {
        final layer = g.vertices[v].layer,
            row = g.orders[layer],
            original = row.indexOf(v),
            without = [...row.take(original), ...row.skip(original + 1)];
        var minimum = 0x7fffffffffffffff, best = 0, originalCost = 0;
        for (var p = 0; p <= without.length; p++) {
          final inserted = [...without.take(p), v, ...without.skip(p)],
              trial = List<List<int>>.of(g.orders);
          trial[layer] = inserted;
          final pos = positions(trial, g.vertices.length);
          var cost = 0;
          if (layer > 0)
            cost += gapCrossings(
              g.segments,
              g.gaps[layer - 1],
              pos,
              trial[layer].length,
            );
          if (layer + 1 < trial.length)
            cost += gapCrossings(
              g.segments,
              g.gaps[layer],
              pos,
              trial[layer + 1].length,
            );
          if (p == original) originalCost = cost;
          if (cost < minimum) {
            minimum = cost;
            best = p;
          }
        }
        if (originalCost == minimum) best = original;
        g.orders[layer] = [...without.take(best), v, ...without.skip(best)];
        if (best != original) moves++;
      }
      final crossings = totalCrossings(g, g.orders);
      g.sifts.add(Sift(round, moves, crossings));
      if (moves == 0) break;
    }
  }
  g.finalCrossings = totalCrossings(g, g.orders);
  g.brute = bruteCrossings(g, g.orders, true);
}

class Bus {
  final (bool, int) key;
  int low, high, track = 0;
  final List<int> segments = [];
  Bus(this.key, this.low, this.high);
}

void geometry(Layout g) {
  final layers = g.orders.length;
  g.tracks = List.filled(g.gaps.length, 0);
  g.gapWidths = List.filled(g.gaps.length, 0);
  for (var gap = 0; gap < g.gaps.length; gap++) {
    final indices = g.gaps[gap], counts = <int, int>{};
    for (final index in indices) {
      final s = g.segments[index];
      if (g.vertices[s.upper].x != g.vertices[s.lower].x)
        counts[s.upper] = (counts[s.upper] ?? 0) + 1;
    }
    final byKey = <(bool, int), Bus>{}, buses = <Bus>[];
    for (final index in indices) {
      final s = g.segments[index],
          upper = g.vertices[s.upper].x,
          lower = g.vertices[s.lower].x;
      if (upper == lower) continue;
      final isUpper = (counts[s.upper] ?? 0) >= 2,
          key = (isUpper, isUpper ? s.upper : s.lower);
      var bus = byKey[key];
      if (bus == null) {
        bus = Bus(key, min(upper, lower), max(upper, lower));
        byKey[key] = bus;
        buses.add(bus);
      }
      bus.low = min(bus.low, min(upper, lower));
      bus.high = max(bus.high, max(upper, lower));
      bus.segments.add(index);
    }
    buses.sort((a, b) {
      var c = a.low.compareTo(b.low);
      if (c != 0) return c;
      c = a.high.compareTo(b.high);
      if (c != 0) return c;
      if (a.key.$1 != b.key.$1) return a.key.$1 ? -1 : 1;
      return g.vertices[a.key.$2].x.compareTo(g.vertices[b.key.$2].x);
    });
    final ends = <int>[];
    for (final bus in buses) {
      var track = -1;
      for (var t = 0; t < ends.length; t++) {
        if (ends[t] + 1 < bus.low) {
          track = t;
          break;
        }
      }
      if (track < 0) {
        track = ends.length;
        ends.add(bus.high);
      } else {
        ends[track] = bus.high;
      }
      bus.track = track + 1;
    }
    g.tracks[gap] = ends.length;
    g.gapWidths[gap] = max(g.block.settings.layerGap, ends.length + 2);
    for (final bus in buses) {
      final offset = bus.track + (g.gapWidths[gap] - 2 - ends.length) ~/ 2;
      for (final index in bus.segments) {
        g.segments[index].offset = offset;
      }
    }
  }
  g.thickness = List.filled(layers, 1);
  g.bandStarts = List.filled(layers, 0);
  final vertical =
      g.block.settings.direction == 'TB' || g.block.settings.direction == 'BT';
  for (var i = 0; i < layers; i++) {
    if (!vertical) {
      for (final v in g.orders[i]) {
        g.thickness[i] = max(g.thickness[i], g.vertices[v].width);
      }
    }
    if (i > 0)
      g.bandStarts[i] =
          g.bandStarts[i - 1] + g.thickness[i - 1] + g.gapWidths[i - 1];
  }
  g.mainLength = g.bandStarts.last + g.thickness.last;
  for (final v in g.vertices) {
    g.secondaryLength = max(g.secondaryLength, v.x + v.right + 1);
  }
  g.canvas = Canvas(
    g.mainLength,
    g.secondaryLength,
    g.block.settings.direction,
  );
  int vertexSize(int v) => vertical ? 1 : g.vertices[v].width;
  for (final e in g.edges) {
    if (e.transitive) continue;
    final upper = g.canvas.map(
          g.bandStarts[g.vertices[e.upper].layer] + vertexSize(e.upper),
          g.vertices[e.upper].x,
        ),
        lower = g.canvas.map(
          g.bandStarts[g.vertices[e.lower].layer] - 1,
          g.vertices[e.lower].x,
        );
    e.route = [upper];
    for (final index in e.segments) {
      final s = g.segments[index],
          x = g.vertices[s.upper].x,
          y = g.vertices[s.lower].x;
      if (x != y) {
        final main = g.bandStarts[s.gap] + g.thickness[s.gap] + s.offset;
        e.route.addAll([g.canvas.map(main, x), g.canvas.map(main, y)]);
        e.bends += 2;
      }
    }
    e.route.add(lower);
    if (e.reversed) e.route = e.route.reversed.toList();
    e.length = 1;
    for (var i = 0; i + 1 < e.route.length; i++) {
      final a = e.route[i], b = e.route[i + 1];
      e.length += (a.$1 - b.$1).abs() + (a.$2 - b.$2).abs();
    }
  }
  if (g.block.hasPath) {
    final indices = {for (var i = 0; i < g.n; i++) g.block.nodes[i].id: i},
        from = indices[g.block.pathFrom]!,
        to = indices[g.block.pathTo]!,
        adjacent = List.generate(g.n, (_) => <int>[]);
    for (final e in g.edges) {
      if (!e.transitive) adjacent[e.from].add(e.to);
    }
    for (final row in adjacent) {
      row.sort();
    }
    final parent = List.filled(g.n, -2), queue = [from];
    parent[from] = -1;
    for (var h = 0; h < queue.length; h++) {
      for (final v in adjacent[queue[h]]) {
        if (parent[v] == -2) {
          parent[v] = queue[h];
          queue.add(v);
        }
      }
    }
    if (parent[to] != -2) {
      for (var v = to; v >= 0; v = parent[v]) {
        g.path.add(v);
      }
      g.path = g.path.reversed.toList();
    }
  }
}

void draw(Layout g) {
  final c = g.canvas;
  for (var i = 0; i < g.vertices.length; i++) {
    final v = g.vertices[i];
    if (i >= g.n) {
      for (var j = 0; j < g.thickness[v.layer]; j++) {
        c.mainLine(g.bandStarts[v.layer] + j, v.x);
      }
    } else if ((c.direction == 'LR' || c.direction == 'RL') &&
        v.lower.isNotEmpty) {
      for (var j = v.width; j < g.thickness[v.layer]; j++) {
        c.mainLine(g.bandStarts[v.layer] + j, v.x);
      }
    }
  }
  for (final s in g.segments) {
    c.segment(
      g.bandStarts[s.gap] + g.thickness[s.gap],
      g.gapWidths[s.gap],
      g.vertices[s.upper].x,
      g.vertices[s.lower].x,
      s.offset,
    );
  }
  const arrows = {
    'TB': ('v', '^'),
    'BT': ('^', 'v'),
    'LR': ('>', '<'),
    'RL': ('<', '>'),
  };
  for (final e in g.edges) {
    if (e.transitive) continue;
    final position = e.route.last,
        arrow = e.reversed ? arrows[c.direction]!.$2 : arrows[c.direction]!.$1;
    c.arrows[position.$1][position.$2] = arrow;
  }
  final pathNodes = g.path.toSet(),
      pathEdges = {
        for (var i = 1; i < g.path.length; i++) (g.path[i - 1], g.path[i]),
      };
  for (final e in g.edges) {
    if (e.transitive || !pathEdges.contains((e.from, e.to))) continue;
    for (var i = 0; i + 1 < e.route.length; i++) {
      c.highlight(e.route[i], e.route[i + 1]);
    }
  }
  for (var i = 0; i < g.n; i++) {
    final node = g.block.nodes[i],
        v = g.vertices[i],
        text = pathNodes.contains(i) ? '{${node.label}}' : '[${node.label}]';
    Cell start;
    switch (c.direction) {
      case 'TB':
      case 'BT':
        start = c.map(g.bandStarts[v.layer], v.x - v.left);
        break;
      case 'LR':
        start = (v.x, g.bandStarts[v.layer]);
        break;
      default:
        start = (v.x, g.mainLength - g.bandStarts[v.layer] - v.width);
    }
    for (var j = 0; j < text.length; j++) {
      c.boxes[start.$1][start.$2 + j] = text[j];
    }
  }
}

List<String> displayNames(Layout g, List<int> vertices) =>
    vertices.map((v) => g.vertices[v].name).toList();
String edgeName(Layout g, Edge edge) =>
    '${g.vertices[edge.from].name}->${g.vertices[edge.to].name}';
List<String> layoutLines(Layout g) {
  final block = g.block,
      values = g.block.settings.values(),
      out = [
        'graph ${g.block.name}',
        'settings ${[for (var i = 0; i < settingNames.length; i++) '${settingNames[i]}=${values[i]}'].join(' ')}',
        'acyclic ${displayNames(g, g.acyclic).join(' ')}',
      ];
  if (block.settings.layering == 'coffman')
    out.add(
      'labels ${[for (var v = 0; v < g.n; v++) '${g.vertices[v].name}:${g.layering.labels[v]}'].join(' ')}',
    );
  for (final p in g.layering.promotions) {
    out.add('promote ${p.round} ${g.vertices[p.node].name} ${p.diff}');
  }
  for (final s in g.sweeps) {
    out.add(
      s.number == 0
          ? 'sweep ${s.run} 0 initial crossings ${s.crossings}'
          : 'sweep ${s.run} ${s.number} ${s.direction} moved ${s.moved} swaps ${s.swaps} crossings ${s.crossings}',
    );
  }
  out.add(
    'best run ${g.bestRun} sweep ${g.bestSweep} crossings ${g.adoptedCrossings}',
  );
  for (final s in g.sifts) {
    out.add('sift ${s.round} moves ${s.moves} crossings ${s.crossings}');
  }
  for (var i = 0; i < g.orders.length; i++) {
    final row = g.orders[i];
    var bandStart = g.bandStarts[i],
        bandEnd = g.bandStarts[i] + g.thickness[i] - 1;
    if (block.settings.direction == 'BT' || block.settings.direction == 'RL') {
      final start = g.mainLength - 1 - bandEnd;
      bandEnd = g.mainLength - 1 - bandStart;
      bandStart = start;
    }
    var low = 0, high = 0;
    final vertices = <String>[];
    for (var j = 0; j < row.length; j++) {
      final v = g.vertices[row[j]];
      if (j == 0 || v.x - v.left < low) low = v.x - v.left;
      if (j == 0 || v.x + v.right > high) high = v.x + v.right;
      vertices.add('${v.name}@${v.x}');
    }
    out.add(
      'layer $i band $bandStart $bandEnd extent $low $high : ${vertices.join(' ')}',
    );
  }
  final pos = positions(g.orders, g.vertices.length);
  for (var i = 0; i < g.gaps.length; i++) {
    final indices = g.gaps[i],
        crossings = gapCrossings(
          g.segments,
          g.gaps[i],
          pos,
          g.orders[i + 1].length,
        );
    out.add(
      'between $i ${i + 1} segments ${indices.length} crossings $crossings tracks ${g.tracks[i]} gap ${g.gapWidths[i]}',
    );
  }
  out.add(
    'bk conflicts ${g.coordinates.marked.length} ${[for (final variant in g.coordinates.variants) '${variant.name}=${variant.blocks}/${variant.width}'].join(' ')} smallest ${g.coordinates.variants[g.coordinates.smallest].name}',
  );
  for (var layer = 0; layer < g.orders.length; layer++) {
    final row = g.orders[layer];
    for (var p = 0; p < row.length; p++) {
      final v = row[p], variants = g.coordinates.variants;
      out.add(
        'vertex ${g.vertices[v].name} layer $layer pos $p ul ${variants[0].aligned[v]} ur ${variants[1].aligned[v]} dl ${variants[2].aligned[v]} dr ${variants[3].aligned[v]} x ${g.vertices[v].x}',
      );
    }
  }
  for (final e in g.edges) {
    var prefix = 'edge ${g.vertices[e.from].name} ${g.vertices[e.to].name}';
    if (e.transitive) {
      out.add('$prefix transitive');
      continue;
    }
    if (e.reversed) prefix += ' reversed';
    final chain = e.reversed ? e.chain.reversed.toList() : e.chain,
        path = [for (final v in chain) g.vertices[v].x],
        route = [for (final p in e.route) '${p.$1},${p.$2}'];
    out.add(
      '$prefix span ${e.span} crossings ${e.crossings} bends ${e.bends} path ${path.join(' ')} route ${route.join(' ')}',
    );
  }
  out.add('end');
  return out;
}

List<String> statsLines(Layout g) {
  final block = g.block,
      out = [
        'graph ${g.block.name}',
        'nodes ${g.n} edges ${g.edges.length} self_loops ${g.block.selfLoops} duplicates ${g.block.duplicates}',
        'sources ${g.sources} sinks ${g.sinks} isolated ${g.isolated} components ${g.components}',
      ];
  for (final component in g.scc) {
    out.add('scc ${displayNames(g, component).join(' ')}');
  }
  final reversed = <String>[],
      transitive = <String>[],
      spanCounts = <int, int>{};
  var spanTotal = 0,
      spanMax = 0,
      longEdges = 0,
      vertical = 0,
      routeLength = 0,
      bends = 0,
      longest = -1;
  for (var i = 0; i < g.edges.length; i++) {
    final e = g.edges[i];
    if (e.reversed) reversed.add(edgeName(g, e));
    if (e.transitive) {
      transitive.add(edgeName(g, e));
      continue;
    }
    spanCounts[e.span] = (spanCounts[e.span] ?? 0) + 1;
    spanTotal += e.span;
    spanMax = max(spanMax, e.span);
    if (e.span >= 2) {
      longEdges++;
      final dummies = e.chain.sublist(1, e.chain.length - 1),
          x = g.vertices[dummies.first].x;
      if (dummies.every((v) => g.vertices[v].x == x)) vertical++;
    }
    routeLength += e.length;
    bends += e.bends;
    if (longest < 0 || e.length > g.edges[longest].length) longest = i;
  }
  out.add(
    'reversed ${reversed.length}${reversed.isEmpty ? '' : ' ${reversed.join(' ')}'}',
  );
  out.add(
    'transitive ${transitive.length}${transitive.isEmpty ? '' : ' ${transitive.join(' ')}'}',
  );
  var maxNodes = 0, maxVertices = 0;
  for (final row in g.orders) {
    maxNodes = max(maxNodes, row.where((v) => v < g.n).length);
    maxVertices = max(maxVertices, row.length);
  }
  out.add(
    'layers ${g.orders.length} max_nodes $maxNodes max_vertices $maxVertices',
  );
  out.add(
    block.settings.promotion == 'on'
        ? 'promotion rounds ${g.layering.rounds} accepted ${g.layering.promotions.length} dummies_before ${g.layering.dummiesBefore}'
        : 'promotion off',
  );
  out.add(
    'dummies ${g.vertices.length - g.n} span_total $spanTotal span_max $spanMax',
  );
  final spans = spanCounts.keys.toList()..sort();
  out.add(
    spans.isEmpty
        ? 'spans none'
        : 'spans ${[for (final span in spans) '$span:${spanCounts[span]}'].join(' ')}',
  );
  out.addAll([
    'long_edges $longEdges vertical $vertical',
    'crossings initial ${g.initialCrossings} swept ${g.adoptedCrossings} best_run ${g.bestRun} best_sweep ${g.bestSweep} final ${g.finalCrossings} brute ${g.brute}',
  ]);
  var straight = 0, offset = 0;
  for (final s in g.segments) {
    final a = g.vertices[s.upper].x, b = g.vertices[s.lower].x;
    if (a == b) straight++;
    offset += (a - b).abs();
  }
  out.add(
    'segments ${g.segments.length} straight $straight bent ${g.segments.length - straight} offset $offset',
  );
  out.add(
    'routes length $routeLength bends $bends${longest < 0 ? '' : ' longest ${edgeName(g, g.edges[longest])} ${g.edges[longest].length}'}',
  );
  out.add(
    'canvas width ${g.canvas.columns} height ${g.canvas.rows} crossing_cells ${g.canvas.crossingCells()}',
  );
  if (block.hasPath) {
    out.add(
      g.path.isEmpty
          ? 'path ${block.pathFrom} ${block.pathTo} none'
          : 'path ${block.pathFrom} ${block.pathTo} hops ${g.path.length - 1} : ${displayNames(g, g.path).join(' ')}',
    );
  }
  out.add('end');
  return out;
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final blocks = readBlocks(),
      layout = <String>[],
      stats = <String>[],
      drawings = <String>[],
      crossings = ['graph,run,sweep,crossings'];
  var laidOut = 0,
      errors = 0,
      nodes = 0,
      edges = 0,
      dummies = 0,
      initial = 0,
      finalCross = 0;
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (i > 0) drawings.add('');
    if (block.error.isNotEmpty) {
      errors++;
      final errorLines = [
        'graph ${block.name}',
        'error ${block.error} line ${block.errorLine}',
        'end',
      ];
      layout.addAll(errorLines);
      stats.addAll(errorLines);
      drawings.add('graph ${block.name} error ${block.error}');
      continue;
    }
    final g = initialize(block);
    reduceCrossings(g);
    g.coordinates = coordinates(g);
    geometry(g);
    draw(g);
    layout.addAll(layoutLines(g));
    stats.addAll(statsLines(g));
    drawings.addAll(g.canvas.drawing(block.name));
    for (final s in g.sweeps) {
      crossings.add('${block.name},${s.run},${s.number},${s.crossings}');
    }
    laidOut++;
    nodes += g.n;
    edges += g.edges.length;
    dummies += g.vertices.length - g.n;
    initial += g.initialCrossings;
    finalCross += g.finalCrossings;
  }
  stats.add(
    'summary graphs ${blocks.length} laid_out $laidOut errors $errors nodes $nodes edges $edges dummies $dummies crossings_initial $initial crossings_final $finalCross',
  );
  Directory('output').createSync(recursive: true);
  writeLines('layout.txt', layout);
  writeLines('stats.txt', stats);
  writeLines('crossings.csv', crossings);
  writeLines('drawings.txt', drawings);
}
