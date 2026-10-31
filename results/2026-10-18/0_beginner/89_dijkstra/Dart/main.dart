void main() {
  final graph = List.generate(7, (_) => List.filled(7, 0));
  for (final e in [
    (0, 1, 7),
    (0, 2, 3),
    (0, 3, 9),
    (1, 2, 2),
    (2, 4, 6),
    (1, 3, 3),
    (3, 4, 4),
    (3, 5, 5),
    (4, 5, 3),
    (4, 6, 8),
    (5, 6, 4),
  ]) {
    graph[e.$1][e.$2] = e.$3;
    graph[e.$2][e.$1] = e.$3;
  }
  final distance = List.filled(7, 1000000);
  final previous = List.filled(7, 0);
  final done = List.filled(7, false);
  distance[0] = 0;
  for (var k = 0; k < 7; k++) {
    int? best;
    for (var i = 0; i < 7; i++) {
      if (!done[i] && (best == null || distance[i] < distance[best])) best = i;
    }
    final u = best!;
    done[u] = true;
    for (var v = 0; v < 7; v++) {
      if (graph[u][v] > 0 && distance[u] + graph[u][v] < distance[v]) {
        distance[v] = distance[u] + graph[u][v];
        previous[v] = u;
      }
    }
  }
  for (var v = 0; v < 7; v++) {
    final path = <String>[];
    var u = v;
    while (true) {
      path.add(String.fromCharCode(65 + u));
      if (u == 0) break;
      u = previous[u];
    }
    print(
      '${String.fromCharCode(65 + v)}: distance=${distance[v]} path=${path.reversed.join('-')}',
    );
  }
}
