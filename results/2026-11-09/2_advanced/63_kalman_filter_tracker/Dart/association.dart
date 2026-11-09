part of 'main.dart';

List<int> hungarian(Matrix cost) {
  final n = cost.length,
      m = cost.first.length,
      u = List.filled(n + 1, 0.0),
      v = List.filled(m + 1, 0.0),
      p = List.filled(m + 1, 0),
      way = List.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    p[0] = i;
    var j0 = 0;
    final minv = List.filled(m + 1, double.infinity),
        used = List.filled(m + 1, false);
    while (true) {
      used[j0] = true;
      final i0 = p[j0];
      var delta = double.infinity, j1 = 0;
      for (var j = 1; j <= m; j++) {
        if (used[j]) continue;
        final current = cost[i0 - 1][j - 1] - u[i0] - v[j];
        if (current < minv[j]) {
          minv[j] = current;
          way[j] = j0;
        }
        if (minv[j] < delta) {
          delta = minv[j];
          j1 = j;
        }
      }
      for (var j = 0; j <= m; j++) {
        if (used[j]) {
          u[p[j]] += delta;
          v[j] -= delta;
        } else if (j > 0) {
          minv[j] -= delta;
        }
      }
      j0 = j1;
      if (p[j0] == 0) break;
    }
    while (true) {
      final j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
      if (j0 == 0) break;
    }
  }
  final out = List.filled(n, -1);
  for (var j = 1; j <= m; j++) {
    if (p[j] > 0) out[p[j] - 1] = j - 1;
  }
  return out;
}

List<int> assignment(Matrix cost, List<List<bool>> usable, int columns) {
  final rows = cost.length, out = List.filled(cost.length, -1);
  if (rows == 0 || columns == 0) return out;
  var penalty = 1.0;
  for (var i = 0; i < rows; i++) {
    for (var j = 0; j < columns; j++) {
      if (usable[i][j]) penalty += cost[i][j].abs();
    }
  }
  final matrix = List.generate(
    rows,
    (i) => List.generate(columns, (j) => usable[i][j] ? cost[i][j] : penalty),
  );
  if (rows <= columns) {
    final chosen = hungarian(matrix);
    for (var i = 0; i < chosen.length; i++) {
      final j = chosen[i];
      if (j >= 0 && usable[i][j]) out[i] = j;
    }
  } else {
    final chosen = hungarian(transpose(matrix));
    for (var j = 0; j < chosen.length; j++) {
      final i = chosen[j];
      if (i >= 0 && usable[i][j]) out[i] = j;
    }
  }
  return out;
}
