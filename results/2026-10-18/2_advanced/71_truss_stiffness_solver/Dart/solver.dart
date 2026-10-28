part of 'main.dart';

(List<List<double>>?, int) cholesky(List<List<double>> a) {
  final n = a.length, g = matrix(a.length, a.length);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j <= i; j++) {
      var w = a[i][j];
      for (var h = 0; h < j; h++) {
        w -= g[i][h] * g[j][h];
      }
      if (j < i) {
        g[i][j] = w / g[j][j];
      } else {
        if (w <= 0.000000001 * a[i][i]) return (null, i);
        g[i][i] = sqrt(w);
      }
    }
  }
  return (g, -1);
}

List<double> solve(List<List<double>> g, List<double> b) {
  final n = b.length,
      y = List.filled(b.length, 0.0),
      x = List.filled(b.length, 0.0);
  for (var i = 0; i < n; i++) {
    var w = b[i];
    for (var h = 0; h < i; h++) {
      w -= g[i][h] * y[h];
    }
    y[i] = w / g[i][i];
  }
  for (var i = n - 1; i >= 0; i--) {
    var w = y[i];
    for (var h = i + 1; h < n; h++) {
      w -= g[h][i] * x[h];
    }
    x[i] = w / g[i][i];
  }
  return x;
}
