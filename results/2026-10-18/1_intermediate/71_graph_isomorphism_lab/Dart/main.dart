import 'dart:io';
import 'dart:math' as math;

typedef Edge = (int, int);
class Refinement {
  final List<int> colors;
  final int rounds;
  Refinement(this.colors, this.rounds);
}
class Canonical {
  int nodes = 0;
  int leaves = 0;
  List<int> labels = [];
  String string = '';
  List<List<int>> bestLeaves = [];
}
class Invariants {
  final List<int> degrees;
  final int triangles;
  final List<int> sizes;
  final String girth, diameter, radius, bipartite;
  Invariants(this.degrees, this.triangles, this.sizes, this.girth,
      this.diameter, this.radius, this.bipartite);
}
class Graph {
  final int n;
  final List<int> rows;
  Canonical? canonical;
  Invariants? invariants;
  Refinement? stable;
  Graph(this.n) : rows = List<int>.filled(n, 0);
  void add(int u, int v) {
    rows[u] |= 1 << v;
    rows[v] |= 1 << u;
  }
  bool adjacent(int u, int v) => (rows[u] & (1 << v)) != 0;
  List<int> neighbors(int u) => [for (var v = 0; v < n; v++) if (adjacent(u, v)) v];
  List<Edge> edges() => [
    for (var u = 0; u < n; u++)
      for (var v = u + 1; v < n; v++) if (adjacent(u, v)) (u, v)
  ];
}
class GraphError implements Exception {
  final String message;
  GraphError(this.message);
}
final registry = <String, Graph>{};
final output = <String>[];
Never fail(String message) => throw GraphError('error: $message');
int lex(List<int> a, List<int> b) {
  for (var i = 0; i < math.min(a.length, b.length); i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
}
int popcount(int mask) {
  var count = 0;
  while (mask != 0) {
    mask &= mask - 1;
    count++;
  }
  return count;
}
List<List<int>> cells(List<int> colors) {
  final result = List.generate(colors.reduce(math.max) + 1, (_) => <int>[]);
  for (var v = 0; v < colors.length; v++) {
    result[colors[v]].add(v);
  }
  return result;
}
Refinement refine(Graph graph, List<int> initial) {
  var colors = List<int>.of(initial), rounds = 0;
  while (true) {
    final signatures = <List<int>>[];
    for (var v = 0; v < graph.n; v++) {
      final neighbors = graph.neighbors(v).map((u) => colors[u]).toList()..sort();
      signatures.add([colors[v], ...neighbors]);
    }
    final order = List.generate(graph.n, (v) => v)
      ..sort((a, b) => lex(signatures[a], signatures[b]));
    final next = List<int>.filled(graph.n, 0);
    var color = 0;
    for (var i = 0; i < order.length; i++) {
      if (i > 0 && lex(signatures[order[i - 1]], signatures[order[i]]) != 0) color++;
      next[order[i]] = color;
    }
    if (color + 1 == colors.reduce(math.max) + 1) return Refinement(colors, rounds);
    colors = next;
    rounds++;
  }
}
Refinement stable(Graph graph) {
  if (graph.stable == null) {
    final degrees = graph.rows.map(popcount).toList();
    final unique = degrees.toSet().toList()..sort();
    graph.stable = refine(graph, degrees.map(unique.indexOf).toList());
  }
  return graph.stable!;
}
List<int> individualize(List<int> colors, int vertex) => [
  for (var w = 0; w < colors.length; w++)
    colors[w] < colors[vertex] || w == vertex ? colors[w] : colors[w] + 1
];
String leafString(Graph graph, List<int> labels) {
  final inverse = List<int>.filled(graph.n, 0);
  for (var v = 0; v < graph.n; v++) {
    inverse[labels[v]] = v;
  }
  final result = StringBuffer();
  for (var i = 0; i < graph.n; i++) {
    for (var j = i + 1; j < graph.n; j++) {
      result.write(graph.adjacent(inverse[i], inverse[j]) ? '1' : '0');
    }
  }
  return result.toString();
}
Canonical canon(Graph graph) {
  if (graph.canonical != null) return graph.canonical!;
  final result = Canonical();
  void visit(List<int> colors) {
    result.nodes++;
    final partition = cells(colors);
    if (partition.length == graph.n) {
      result.leaves++;
      final string = leafString(graph, colors);
      if (result.bestLeaves.isEmpty || string.compareTo(result.string) > 0) {
        result.string = string;
        result.labels = List.of(colors);
        result.bestLeaves = [List.of(colors)];
      } else if (string == result.string) {
        result.bestLeaves.add(List.of(colors));
      }
      return;
    }
    final candidates = partition.where((cell) => cell.length > 1);
    final chosen = candidates.reduce((best, cell) => cell.length < best.length ? cell : best);
    for (final vertex in chosen) {
      visit(refine(graph, individualize(colors, vertex)).colors);
    }
  }
  visit(stable(graph).colors);
  graph.canonical = result;
  return result;
}
Invariants invariants(Graph graph) {
  if (graph.invariants != null) return graph.invariants!;
  final n = graph.n;
  final degrees = graph.rows.map(popcount).toList()..sort((a, b) => b.compareTo(a));
  final sizes = <int>[], seen = <int>{}, eccentricities = <int>[];
  var triangles = 0;
  int? shortest;
  var bipartite = true;
  for (var u = 0; u < n; u++) {
    for (var v = u + 1; v < n; v++) {
      for (var w = v + 1; w < n; w++) {
        if (graph.adjacent(u, v) && graph.adjacent(u, w) && graph.adjacent(v, w)) triangles++;
      }
    }
  }
  for (var start = 0; start < n; start++) {
    final distance = List<int>.filled(n, -1), parent = List<int>.filled(n, -1);
    final queue = <int>[start];
    distance[start] = 0;
    for (var i = 0; i < queue.length; i++) {
      final u = queue[i];
      for (final v in graph.neighbors(u)) {
        if (distance[v] < 0) {
          distance[v] = distance[u] + 1;
          parent[v] = u;
          queue.add(v);
        } else if (parent[u] != v) {
          final cycle = distance[u] + distance[v] + 1;
          shortest = shortest == null ? cycle : math.min(shortest!, cycle);
        }
        if (distance[v] % 2 == distance[u] % 2) bipartite = false;
      }
    }
    eccentricities.add(distance.reduce(math.max));
    if (!seen.contains(start)) {
      sizes.add(queue.length);
      seen.addAll(queue);
    }
  }
  sizes.sort((a, b) => b.compareTo(a));
  final result = Invariants(degrees, triangles, sizes, shortest?.toString() ?? 'none',
      sizes.length > 1 ? 'INF' : eccentricities.reduce(math.max).toString(),
      sizes.length > 1 ? 'INF' : eccentricities.reduce(math.min).toString(),
      bipartite ? 'yes' : 'no');
  graph.invariants = result;
  return result;
}
List<int> clique(Graph graph) {
  var best = <int>[];
  for (var mask = 1; mask < (1 << graph.n); mask++) {
    final vertices = [for (var v = 0; v < graph.n; v++) if ((mask & (1 << v)) != 0) v];
    if (vertices.length < best.length) continue;
    if (vertices.every((u) => vertices.every((v) => u == v || graph.adjacent(u, v))) &&
        (vertices.length > best.length || lex(vertices, best) < 0)) best = vertices;
  }
  return best;
}
List<int> coloring(Graph graph, int lower) {
  final colors = List<int>.filled(graph.n, -1);
  bool search(int vertex, int count) {
    if (vertex == graph.n) return true;
    for (var color = 0; color < count; color++) {
      var valid = true;
      for (var u = 0; u < vertex; u++) {
        if (colors[u] == color && graph.adjacent(u, vertex)) {
          valid = false;
          break;
        }
      }
      if (!valid) continue;
      colors[vertex] = color;
      if (search(vertex + 1, count)) return true;
    }
    colors[vertex] = -1;
    return false;
  }
  for (var count = lower; count <= graph.n; count++) {
    if (search(0, count)) return List.of(colors);
  }
  return colors;
}
class DisjointSet {
  final List<int> parent;
  DisjointSet(int n) : parent = List.generate(n, (i) => i);
  int find(int x) => parent[x] == x ? x : parent[x] = find(parent[x]);
  void join(int a, int b) { parent[find(b)] = find(a); }
  List<List<int>> groups() {
    final groups = <int, List<int>>{};
    for (var i = 0; i < parent.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(i);
    }
    return groups.values.toList()..sort((a, b) => a.first.compareTo(b.first));
  }
}
class Format {
  final List<String> fixed;
  final String? rest;
  const Format(this.fixed, [this.rest]);
}
final formats = <String, Format>{
  'GRAPH': Format(['name', 'num'], 'edge'),
  for (final command in ['CYCLE', 'PATH', 'COMPLETE', 'STAR', 'WHEEL', 'HYPERCUBE'])
    command: Format(['name', 'num']),
  'BIPARTITE': Format(['name', 'num', 'num']),
  'PETERSEN': Format(['name']),
  'CIRCULANT': Format(['name', 'num', 'num'], 'num'),
  'GRID': Format(['name', 'num', 'num']),
  for (final command in ['COMPLEMENT', 'LINE', 'CANONIZE'])
    command: Format(['name', 'graph']),
  for (final command in ['PRODUCT', 'UNION'])
    command: Format(['name', 'graph', 'graph']),
  'RELABEL': Format(['name', 'graph'], 'num'),
  'INDUCED': Format(['name', 'graph', 'num'], 'num'),
  for (final command in ['DELETE', 'SHOW', 'INVARIANTS', 'CANON', 'AUT'])
    command: Format(['graph']),
  'LIST': Format([]),
  'REFINE': Format(['graph'], 'num'),
  for (final command in ['ISO', 'SUBISO']) command: Format(['graph', 'graph']),
  'CLASSIFY': Format(['num'])
};
final namePattern = RegExp(r'^[a-z][a-z0-9]{0,7}$');
final numberPattern = RegExp(r'^(0|[1-9][0-9]{0,2})$');
bool valid(String word, String kind) {
  if (kind == 'num') return numberPattern.hasMatch(word);
  if (kind == 'edge') {
    final pair = word.split('-');
    return pair.length == 2 && pair.every(numberPattern.hasMatch);
  }
  return namePattern.hasMatch(word);
}
void checkSize(int n, [int minimum = 1]) {
  if (n < minimum) fail('bad value');
  if (n > 16) fail('too large');
}
Graph relabel(Graph graph, List<int> permutation) {
  final result = Graph(graph.n);
  for (final (u, v) in graph.edges()) {
    result.add(permutation[u], permutation[v]);
  }
  return result;
}
Graph define(String command, List<String> args) {
  final n = int.tryParse(args.length > 1 ? args[1] : '') ?? 0;
  final source = args.length > 1 ? registry[args[1]] : null;
  Graph result;
  switch (command) {
    case 'GRAPH':
      checkSize(n);
      result = Graph(n);
      for (final word in args.skip(2)) {
        final pair = word.split('-').map(int.parse).toList();
        final u = pair[0], v = pair[1];
        if (u >= n || v >= n || u == v) fail('bad edge $word');
        if (result.adjacent(u, v)) fail('duplicate edge $word');
        result.add(u, v);
      }
      return result;
    case 'CYCLE':
    case 'PATH':
    case 'COMPLETE':
      checkSize(n, command == 'CYCLE' ? 3 : 1);
      result = Graph(n);
      for (var u = 0; u < n; u++) {
        for (var v = u + 1; v < n; v++) {
          if (command == 'COMPLETE' || v == u + 1 || command == 'CYCLE' && u == 0 && v == n - 1) result.add(u, v);
        }
      }
      return result;
    case 'BIPARTITE':
      final b = int.parse(args[2]);
      if (n == 0 || b == 0) fail('bad value');
      checkSize(n + b);
      result = Graph(n + b);
      for (var u = 0; u < n; u++) {
        for (var v = 0; v < b; v++) { result.add(u, n + v); }
      }
      return result;
    case 'STAR':
    case 'WHEEL':
      if (n < (command == 'WHEEL' ? 3 : 1)) fail('bad value');
      checkSize(n + 1);
      result = Graph(n + 1);
      for (var v = 1; v <= n; v++) { result.add(0, v); }
      if (command == 'WHEEL') {
        for (var v = 1; v <= n; v++) { result.add(v, v % n + 1); }
      }
      return result;
    case 'PETERSEN':
      result = Graph(10);
      for (var i = 0; i < 5; i++) {
        result.add(i, (i + 1) % 5);
        result.add(i, i + 5);
        result.add(i + 5, 5 + (i + 2) % 5);
      }
      return result;
    case 'HYPERCUBE':
      if (n == 0) fail('bad value');
      if (n >= 5) fail('too large');
      result = Graph(1 << n);
      for (var u = 0; u < result.n; u++) {
        for (var bit = 0; bit < n; bit++) { result.add(u, u ^ (1 << bit)); }
      }
      return result;
    case 'CIRCULANT':
      checkSize(n, 3);
      final jumps = args.skip(2).map(int.parse).toList();
      for (var i = 0; i < jumps.length; i++) {
        if (jumps[i] == 0 || 2 * jumps[i] > n || i > 0 && jumps[i - 1] >= jumps[i]) fail('bad value');
      }
      result = Graph(n);
      for (var u = 0; u < n; u++) {
        for (final jump in jumps) { result.add(u, (u + jump) % n); }
      }
      return result;
    case 'GRID':
      final c = int.parse(args[2]);
      if (n == 0 || c == 0) fail('bad value');
      checkSize(n * c);
      result = Graph(n * c);
      for (var x = 0; x < n; x++) {
        for (var y = 0; y < c; y++) {
          if (y + 1 < c) result.add(x * c + y, x * c + y + 1);
          if (x + 1 < n) result.add(x * c + y, (x + 1) * c + y);
        }
      }
      return result;
    case 'COMPLEMENT':
      result = Graph(source!.n);
      for (var u = 0; u < source.n; u++) {
        for (var v = u + 1; v < source.n; v++) {
          if (!source.adjacent(u, v)) result.add(u, v);
        }
      }
      return result;
    case 'LINE':
      final edges = source!.edges();
      if (edges.isEmpty) fail('no edges');
      checkSize(edges.length);
      result = Graph(edges.length);
      for (var u = 0; u < edges.length; u++) {
        for (var v = u + 1; v < edges.length; v++) {
          final (a, b) = edges[u];
          final (c, d) = edges[v];
          if (a == c || a == d || b == c || b == d) result.add(u, v);
        }
      }
      return result;
    case 'PRODUCT':
    case 'UNION':
      final other = registry[args[2]]!, a = source!.n, b = other.n;
      checkSize(command == 'PRODUCT' ? a * b : a + b);
      result = Graph(command == 'PRODUCT' ? a * b : a + b);
      if (command == 'UNION') {
        for (final (u, v) in source.edges()) { result.add(u, v); }
        for (final (u, v) in other.edges()) { result.add(u + a, v + a); }
      } else {
        for (var x = 0; x < a; x++) {
          for (final (u, v) in other.edges()) { result.add(x * b + u, x * b + v); }
        }
        for (final (u, v) in source.edges()) {
          for (var y = 0; y < b; y++) { result.add(u * b + y, v * b + y); }
        }
      }
      return result;
    case 'RELABEL':
      final permutation = args.skip(2).map(int.parse).toList();
      if (permutation.length != source!.n || permutation.toSet().length != source.n ||
          permutation.any((v) => v >= source.n)) fail('bad permutation');
      return relabel(source, permutation);
    case 'INDUCED':
      final vertices = args.skip(2).map(int.parse).toList();
      if (vertices.toSet().length != vertices.length || vertices.any((v) => v >= source!.n)) fail('bad vertices');
      result = Graph(vertices.length);
      for (var u = 0; u < vertices.length; u++) {
        for (var v = u + 1; v < vertices.length; v++) {
          if (source!.adjacent(vertices[u], vertices[v])) result.add(u, v);
        }
      }
      return result;
    case 'CANONIZE':
      return relabel(source!, canon(source).labels);
  }
  return Graph(1);
}
void iso(Graph a, Graph b) {
  if (a.n != b.n) { output.add('not isomorphic vertices ${a.n} ${b.n}'); return; }
  final ma = a.edges().length, mb = b.edges().length;
  if (ma != mb) { output.add('not isomorphic edges $ma $mb'); return; }
  final x = invariants(a), y = invariants(b);
  if (lex(x.degrees, y.degrees) != 0) { output.add('not isomorphic degrees'); return; }
  final checks = <(String, Object, Object)>[
    ('triangles', x.triangles, y.triangles), ('components', x.sizes.length, y.sizes.length),
    ('girth', x.girth, y.girth), ('diameter', x.diameter, y.diameter), ('bipartite', x.bipartite, y.bipartite)
  ];
  for (final (name, p, q) in checks) {
    if (p != q) { output.add('not isomorphic $name $p $q'); return; }
  }
  final r = stable(a), s = stable(b);
  if (r.rounds != s.rounds || lex(cells(r.colors).map((cell) => cell.length).toList(),
      cells(s.colors).map((cell) => cell.length).toList()) != 0) {
    output.add('not isomorphic refinement');
    return;
  }
  final ca = canon(a), cb = canon(b);
  if (ca.string != cb.string) { output.add('not isomorphic canonical'); return; }
  final inverse = List<int>.filled(b.n, 0);
  for (var v = 0; v < b.n; v++) { inverse[cb.labels[v]] = v; }
  output.add('isomorphic');
  output.add('mapping ${ca.labels.map((label) => inverse[label]).join(' ')}');
}
void automorphisms(String name, Graph graph) {
  final canonical = canon(graph), edges = graph.edges();
  final vertices = DisjointSet(graph.n), edgeOrbits = DisjointSet(edges.length);
  final inverse = List<int>.filled(graph.n, 0);
  for (var v = 0; v < graph.n; v++) { inverse[canonical.labels[v]] = v; }
  final edgeIndices = <Edge, int>{for (var i = 0; i < edges.length; i++) edges[i]: i};
  for (final labels in canonical.bestLeaves) {
    final sigma = labels.map((label) => inverse[label]).toList();
    for (var v = 0; v < graph.n; v++) { vertices.join(v, sigma[v]); }
    for (var i = 0; i < edges.length; i++) {
      final (u, v) = edges[i];
      final a = math.min(sigma[u], sigma[v]), b = math.max(sigma[u], sigma[v]);
      edgeOrbits.join(i, edgeIndices[(a, b)]!);
    }
  }
  final vg = vertices.groups(), eg = edgeOrbits.groups();
  output.add('aut $name order ${canonical.bestLeaves.length}');
  output.add('vertex orbits ${vg.length}');
  for (final group in vg) { output.add('orbit ${group.join(' ')}'); }
  output.add('edge orbits ${eg.length}');
  for (final group in eg) {
    output.add('orbit ${group.map((i) => '${edges[i].$1}-${edges[i].$2}').join(' ')}');
  }
  output.add('transitive vertex ${vg.length == 1 ? 'yes' : 'no'} edge ${eg.length == 1 ? 'yes' : 'no'}');
}
void subiso(String nameA, String nameB, Graph pattern, Graph target) {
  var embeddings = 0, induced = 0;
  final first = <(List<int>, bool)>[], mapping = <int>[];
  void search(int vertex, int used, bool isInduced) {
    if (vertex == pattern.n) {
      embeddings++;
      if (isInduced) induced++;
      if (first.length < 5) first.add((List.of(mapping), isInduced));
      return;
    }
    for (var v = 0; v < target.n; v++) {
      if ((used & (1 << v)) != 0) continue;
      var valid = true, nextInduced = isInduced;
      for (var u = 0; u < vertex; u++) {
        if (pattern.adjacent(u, vertex) && !target.adjacent(mapping[u], v)) {
          valid = false;
          break;
        }
        if (!pattern.adjacent(u, vertex) && target.adjacent(mapping[u], v)) nextInduced = false;
      }
      if (valid) {
        mapping.add(v);
        search(vertex + 1, used | (1 << v), nextInduced);
        mapping.removeLast();
      }
    }
  }
  if (pattern.n <= target.n) search(0, 0, true);
  final order = canon(pattern).bestLeaves.length;
  output.add('subiso $nameA $nameB embeddings $embeddings induced $induced');
  output.add('copies ${embeddings ~/ order} induced ${induced ~/ order}');
  for (final (mapping, isInduced) in first) {
    output.add('embedding ${mapping.join(' ')}${isInduced ? ' induced' : ''}');
  }
}
void classify(int n) {
  if (n == 0) fail('bad value');
  if (n > 5) fail('too large');
  final levels = <List<String>>[[canon(Graph(n)).string]];
  final max = n * (n - 1) ~/ 2;
  for (var m = 0; m < max; m++) {
    final next = <String>{};
    for (final string in levels[m]) {
      final graph = Graph(n);
      var i = 0;
      for (var u = 0; u < n; u++) {
        for (var v = u + 1; v < n; v++) {
          if (string[i++] == '1') graph.add(u, v);
        }
      }
      for (var u = 0; u < n; u++) {
        for (var v = u + 1; v < n; v++) {
          if (graph.adjacent(u, v)) continue;
          final added = relabel(graph, List.generate(n, (vertex) => vertex));
          added.add(u, v);
          next.add(canon(added).string);
        }
      }
    }
    levels.add(next.toList()..sort());
  }
  output.add('classify $n total ${levels.fold<int>(0, (sum, level) => sum + level.length)}');
  for (var m = 0; m < levels.length; m++) {
    final level = levels[m];
    output.add('edges $m count ${level.length} ${level.map((string) => string.isEmpty ? '-' : string).join(' ')}');
  }
}
void execute(String line) {
  final words = line.split(' '), command = words.first, args = words.skip(1).toList();
  final format = formats[command];
  if (format == null) fail('unknown command $command');
  if (args.length < format.fixed.length || format.rest == null && args.length != format.fixed.length) fail('bad arguments');
  for (var i = 0; i < args.length; i++) {
    if (!valid(args[i], i < format.fixed.length ? format.fixed[i] : format.rest!)) fail('bad arguments');
  }
  for (var i = 0; i < format.fixed.length; i++) {
    if (format.fixed[i] == 'graph' && !registry.containsKey(args[i])) fail('no graph ${args[i]}');
  }
  final name = args.isEmpty ? '' : args.first, graph = registry[args.isEmpty ? '' : args.first];
  if (format.fixed.isNotEmpty && format.fixed.first == 'name') {
    final result = define(command, args), redefined = registry.containsKey(name);
    registry[name] = result;
    output.add('${redefined ? 'redefined' : 'defined'} $name n ${result.n} m ${result.edges().length}');
    return;
  }
  switch (command) {
    case 'DELETE':
      registry.remove(name);
      output.add('deleted $name');
    case 'LIST':
      output.add('graphs ${registry.length}');
      for (final key in registry.keys.toList()..sort()) {
        final item = registry[key]!;
        output.add('$key n ${item.n} m ${item.edges().length}');
      }
    case 'SHOW':
      output.add('graph $name n ${graph!.n} m ${graph.edges().length}');
      for (var v = 0; v < graph.n; v++) {
        final neighbors = graph.neighbors(v);
        output.add('$v:${neighbors.isEmpty ? '' : ' ${neighbors.join(' ')}'}');
      }
    case 'INVARIANTS':
      final value = invariants(graph!);
      output.addAll(['invariants $name', 'degrees ${value.degrees.join(' ')}',
        'edges ${graph.edges().length} triangles ${value.triangles}',
        'components ${value.sizes.length} sizes ${value.sizes.join(' ')}',
        'girth ${value.girth} diameter ${value.diameter} radius ${value.radius}',
        'bipartite ${value.bipartite}']);
      if (graph.n > 12) {
        output.addAll(['clique -', 'chromatic -']);
      } else {
        final largest = clique(graph), colors = coloring(graph, largest.length);
        output.add('clique ${largest.length} ${largest.join(' ')}');
        output.add('chromatic ${colors.reduce(math.max) + 1} ${colors.join(' ')}');
      }
    case 'REFINE':
      final vertices = args.skip(1).map(int.parse).toList();
      if (vertices.any((v) => v >= graph!.n)) fail('bad vertices');
      var colors = stable(graph!).colors, rounds = stable(graph).rounds;
      for (final vertex in vertices) {
        if (colors.where((color) => color == colors[vertex]).length == 1) fail('singleton $vertex');
        final next = refine(graph, individualize(colors, vertex));
        colors = next.colors;
        rounds += next.rounds;
      }
      final partition = cells(colors);
      output.add('refine $name rounds $rounds cells ${partition.length}');
      for (var color = 0; color < partition.length; color++) {
        output.add('$color: ${partition[color].join(' ')}');
      }
    case 'CANON':
      final result = canon(graph!);
      output.addAll(['canon $name nodes ${result.nodes} leaves ${result.leaves}',
        'labels ${result.labels.join(' ')}', 'string ${result.string.isEmpty ? '-' : result.string}']);
    case 'ISO':
      iso(graph!, registry[args[1]]!);
    case 'AUT':
      automorphisms(name, graph!);
    case 'SUBISO':
      subiso(name, args[1], graph!, registry[args[1]]!);
    case 'CLASSIFY':
      classify(int.parse(name));
  }
}
void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try {
      execute(stdin.readLineSync()!);
    } on GraphError catch (error) {
      output.add(error.message);
    }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
