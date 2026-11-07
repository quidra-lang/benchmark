part of 'main.dart';

class Tree {
  final Map<int, Map<int, double>> adj = {};
  int next, negative = 0;
  Tree(this.next);
  void connect(int a, int b, double length) {
    (adj[a] ??= {})[b] = length;
    (adj[b] ??= {})[a] = length;
  }

  void disconnect(int a, int b) {
    adj[a]!.remove(b);
    adj[b]!.remove(a);
  }

  Tree copy() {
    final v = Tree(next);
    v.negative = negative;
    for (final entry in adj.entries) {
      v.adj[entry.key] = Map.of(entry.value);
    }
    return v;
  }

  List<int> leaves(int n) => [
    for (var i = 0; i < n; i++)
      if (adj[i]?.isNotEmpty ?? false) i,
  ];
}

class Rooted {
  final int root;
  final Map<int, int> parent = {}, masks = {};
  final Map<int, List<int>> children = {};
  int all = 0;
  Rooted(this.root);
}

String minimumName(int mask, List<SequenceRecord> taxa) {
  var s = '';
  for (var i = 0; i < taxa.length; i++) {
    if (((mask >> i) & 1) != 0 && (s.isEmpty || taxa[i].name.compareTo(s) < 0))
      s = taxa[i].name;
  }
  return s;
}

Rooted rootTree(Tree t, List<SequenceRecord> taxa, int outgroup) {
  final root = t.adj[outgroup]!.keys.single, r = Rooted(root);
  int visit(int v, int parent) {
    r.parent[v] = parent;
    if (v < taxa.length) {
      r.masks[v] = 1 << v;
      return 1 << v;
    }
    var mask = 0;
    final children = t.adj[v]!.keys.where((c) => c != parent).toList()..sort();
    for (final c in children) {
      mask |= visit(c, v);
    }
    children.sort(
      (a, b) => minimumName(
        r.masks[a]!,
        taxa,
      ).compareTo(minimumName(r.masks[b]!, taxa)),
    );
    r.children[v] = children;
    r.masks[v] = mask;
    return mask;
  }

  final all = visit(root, -1);
  r.all = all & ~(1 << outgroup);
  r.masks[root] = r.all;
  return r;
}

Set<int> splitSet(Tree t, List<SequenceRecord> taxa, int outgroup) {
  final r = rootTree(t, taxa, outgroup);
  return {
    for (final entry in r.masks.entries)
      if (entry.key >= taxa.length && entry.key != r.root) entry.value,
  };
}

Tree neighborJoining(List<List<double>> matrix, List<int> list, int n) {
  final t = Tree(n),
      d = List.generate(
        3 * n,
        (i) => [
          for (var j = 0; j < 3 * n; j++) i < n && j < n ? matrix[i][j] : 0.0,
        ],
      );
  var active = List.of(list);
  while (active.length >= 4) {
    final r = active.length, totals = <int, double>{};
    for (final x in active) {
      var sum = 0.0;
      for (final y in active) {
        if (y != x) sum += d[x][y];
      }
      totals[x] = sum;
    }
    var bi = 0, bj = 1;
    var best =
        (r - 2) * d[active[0]][active[1]] -
        totals[active[0]]! -
        totals[active[1]]!;
    for (var i = 0; i < r; i++) {
      for (var j = i + 1; j < r; j++) {
        final q =
            (r - 2) * d[active[i]][active[j]] -
            totals[active[i]]! -
            totals[active[j]]!;
        if (q < best) {
          bi = i;
          bj = j;
          best = q;
        }
      }
    }
    final i = active[bi], j = active[bj], u = t.next++;
    final li = d[i][j] / 2 + (totals[i]! - totals[j]!) / (2 * (r - 2));
    t.connect(i, u, li);
    t.connect(j, u, d[i][j] - li);
    final next = <int>[];
    for (final k in active) {
      if (k != i && k != j) {
        d[u][k] = (d[i][k] + d[j][k] - d[i][j]) / 2;
        d[k][u] = d[u][k];
        next.add(k);
      }
    }
    active = [...next, u];
  }
  final a = active[0], b = active[1], c = active[2], z = t.next++;
  t.connect(a, z, (d[a][b] + d[a][c] - d[b][c]) / 2);
  t.connect(b, z, (d[a][b] + d[b][c] - d[a][c]) / 2);
  t.connect(c, z, (d[a][c] + d[b][c] - d[a][b]) / 2);
  for (final entry in t.adj.entries) {
    for (final branch in entry.value.entries.toList()) {
      final a = entry.key, b = branch.key;
      if (a < b && branch.value < 0) {
        t.negative++;
        t.adj[a]![b] = 0;
        t.adj[b]![a] = 0;
      }
    }
  }
  return t;
}

(double, int) path(Tree t, int a, int b) {
  (double, int)? find(int v, int parent, double length, int edges) {
    if (v == b) return (length, edges);
    final neighbors = t.adj[v]!.keys.toList()..sort();
    for (final u in neighbors) {
      if (u != parent) {
        final result = find(u, v, length + t.adj[v]![u]!, edges + 1);
        if (result != null) return result;
      }
    }
    return null;
  }

  return find(a, -1, 0, 0)!;
}

List<List<double>> patristic(Tree t, int n) => [
  for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) path(t, i, j).$1],
];
