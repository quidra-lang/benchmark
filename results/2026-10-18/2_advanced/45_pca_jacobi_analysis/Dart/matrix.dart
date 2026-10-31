part of 'main.dart';

List<List<double>> zeros(int rows, int cols) =>
    List.generate(rows, (_) => List.filled(cols, 0.0));
List<List<double>> identity(int n) => [
  for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0],
];
List<List<double>> copyMatrix(List<List<double>> a) => [
  for (final row in a) [...row],
];
List<double> column(List<List<double>> a, int j) => [
  for (final row in a) row[j],
];
double sum(Iterable<double> values) {
  var s = 0.0;
  for (final v in values) {
    s += v;
  }
  return s;
}

double dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

List<double> multiply(List<List<double>> a, List<double> v) => [
  for (final row in a) dot(row, v),
];
List<double> normalize(List<double> v) {
  final length = math.sqrt(dot(v, v));
  return [for (final x in v) x / length];
}

List<double> orient(List<double> v) {
  var best = 0;
  for (var j = 1; j < v.length; j++) {
    if (v[j].abs() > v[best].abs()) best = j;
  }
  if (v[best] < 0) {
    for (var j = 0; j < v.length; j++) {
      v[j] = -v[j];
    }
  }
  return v;
}

double maxDifference(List<double> a, List<double> b) {
  var value = 0.0;
  for (var j = 0; j < a.length; j++) {
    value = math.max(value, (a[j] - b[j]).abs());
  }
  return value;
}

void deflate(List<List<double>> a, double value, List<double> v) {
  for (var i = 0; i < a.length; i++) {
    for (var j = 0; j < a[i].length; j++) {
      a[i][j] = a[i][j] - value * v[i] * v[j];
    }
  }
}

(List<List<double>>, double) gaussJordan(List<List<double>> a) {
  final n = a.length,
      unit = identity(a.length),
      work = [
        for (var i = 0; i < a.length; i++) [...a[i], ...unit[i]],
      ];
  var det = 1.0;
  for (var k = 0; k < n; k++) {
    final pivot = work[k][k];
    det *= pivot;
    for (var h = 0; h < 2 * n; h++) {
      work[k][h] /= pivot;
    }
    for (var i = 0; i < n; i++) {
      if (i == k) continue;
      final gamma = work[i][k];
      for (var h = 0; h < 2 * n; h++) {
        work[i][h] = work[i][h] - gamma * work[k][h];
      }
    }
  }
  return ([for (final row in work) row.sublist(n)], det);
}
