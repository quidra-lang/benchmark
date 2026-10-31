part of 'main.dart';

Formula queens(int n) {
  final clauses = [
    for (var r = 1; r <= n; r++) [for (var c = 1; c <= n; c++) (r - 1) * n + c],
  ];
  for (var a = 1; a <= n * n; a++) {
    final ra = (a - 1) ~/ n, ca = (a - 1) % n;
    for (var b = a + 1; b <= n * n; b++) {
      final rb = (b - 1) ~/ n, cb = (b - 1) % n;
      if (ra == rb || ca == cb || (ra - rb).abs() == (ca - cb).abs())
        clauses.add([-a, -b]);
    }
  }
  return Formula(n * n, clauses);
}

Formula pigeon(int p, int h) {
  final clauses = [
    for (var i = 1; i <= p; i++) [for (var j = 1; j <= h; j++) (i - 1) * h + j],
  ];
  for (var i = 1; i <= p; i++) {
    for (var j1 = 1; j1 <= h; j1++) {
      for (var j2 = j1 + 1; j2 <= h; j2++) {
        clauses.add([-((i - 1) * h + j1), -((i - 1) * h + j2)]);
      }
    }
  }
  for (var j = 1; j <= h; j++) {
    for (var i1 = 1; i1 <= p; i1++) {
      for (var i2 = i1 + 1; i2 <= p; i2++) {
        clauses.add([-((i1 - 1) * h + j), -((i2 - 1) * h + j)]);
      }
    }
  }
  return Formula(p * h, clauses);
}

Formula coloring(Graph g, int k) {
  final clauses = [
    for (var v = 1; v <= g.vertices; v++)
      [for (var c = 1; c <= k; c++) (v - 1) * k + c],
  ];
  for (var v = 1; v <= g.vertices; v++) {
    for (var c1 = 1; c1 <= k; c1++) {
      for (var c2 = c1 + 1; c2 <= k; c2++) {
        clauses.add([-((v - 1) * k + c1), -((v - 1) * k + c2)]);
      }
    }
  }
  for (final (a, b) in g.edges) {
    for (var c = 1; c <= k; c++) {
      clauses.add([-((a - 1) * k + c), -((b - 1) * k + c)]);
    }
  }
  return Formula(g.vertices * k, clauses);
}

List<int> positions(List<bool> model, int rows, int width) => [
  for (var r = 1; r <= rows; r++)
    [
      for (var c = 1; c <= width; c++)
        if (model[(r - 1) * width + c]) c,
    ].first,
];
