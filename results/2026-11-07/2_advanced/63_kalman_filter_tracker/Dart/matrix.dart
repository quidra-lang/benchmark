part of 'main.dart';

typedef Matrix = List<List<double>>;
Matrix zeros(int rows, int cols) =>
    List.generate(rows, (_) => List.filled(cols, 0.0));
Matrix identity(int n) {
  final a = zeros(n, n);
  for (var i = 0; i < n; i++) {
    a[i][i] = 1;
  }
  return a;
}

Matrix diagonal(List<double> v) {
  final a = zeros(v.length, v.length);
  for (var i = 0; i < v.length; i++) {
    a[i][i] = v[i];
  }
  return a;
}

Matrix transpose(Matrix a) => List.generate(
  a.first.length,
  (j) => List.generate(a.length, (i) => a[i][j]),
);
Matrix product(Matrix a, Matrix b) {
  final out = zeros(a.length, b.first.length);
  for (var i = 0; i < out.length; i++) {
    for (var j = 0; j < out[i].length; j++) {
      var s = 0.0;
      for (var k = 0; k < b.length; k++) {
        s += a[i][k] * b[k][j];
      }
      out[i][j] = s;
    }
  }
  return out;
}

List<double> matrixVector(Matrix a, List<double> v) => a.map((row) {
  var s = 0.0;
  for (var j = 0; j < row.length; j++) {
    s += row[j] * v[j];
  }
  return s;
}).toList();
Matrix matrixAdd(Matrix a, Matrix b, double sign) => List.generate(
  a.length,
  (i) => List.generate(a[i].length, (j) => a[i][j] + sign * b[i][j]),
);
List<double> vectorAdd(List<double> a, List<double> b, double sign) =>
    List.generate(a.length, (i) => a[i] + sign * b[i]);
Matrix inverse(Matrix a) {
  final n = a.length, x = zeros(a.length, 2 * a.length);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      x[i][j] = a[i][j];
    }
    x[i][n + i] = 1;
  }
  for (var c = 0; c < n; c++) {
    final p = x[c][c];
    for (var j = 0; j < 2 * n; j++) {
      x[c][j] /= p;
    }
    for (var i = 0; i < n; i++) {
      if (i == c) continue;
      final f = x[i][c];
      for (var j = 0; j < 2 * n; j++) {
        x[i][j] = x[i][j] - f * x[c][j];
      }
    }
  }
  return [for (final row in x) row.sublist(n)];
}

double determinant(Matrix a) => a[0][0] * a[1][1] - a[0][1] * a[1][0];
double quadratic(List<double> v, Matrix a) =>
    v[0] * (a[0][0] * v[0] + a[0][1] * v[1]) +
    v[1] * (a[1][0] * v[0] + a[1][1] * v[1]);
Matrix positionCovariance(Matrix a) => [
  [a[0][0], a[0][1]],
  [a[1][0], a[1][1]],
];
