import 'dart:math' as math;

double score(List<double> weights, List<double> vector) {
  var total = 0.0;
  for (var j = 0; j < weights.length; j++) {
    total += weights[j] * vector[j];
  }
  return total;
}

double probability(double u) {
  if (u >= 0) return 1 / (1 + math.exp(-u));
  final e = math.exp(u);
  return e / (1 + e);
}

double loss(double u, int target) =>
    math.max(u, 0.0) - target * u + math.log(1 + math.exp(-u.abs()));
double averageLoss(List<double> w, List<List<double>> x, List<int> y) {
  var total = 0.0;
  for (var i = 0; i < x.length; i++) {
    total += loss(score(w, x[i]), y[i]);
  }
  return total / x.length;
}

double objective(
  List<double> w,
  List<List<double>> x,
  List<int> y,
  double lambda,
) {
  var penalty = 0.0;
  for (final v in w.skip(1)) {
    penalty += v * v;
  }
  return averageLoss(w, x, y) + lambda * penalty / 2;
}

List<double> gradient(
  List<double> w,
  List<List<double>> x,
  List<int> y,
  double lambda,
) {
  final g = List.filled(w.length, 0.0);
  for (var i = 0; i < x.length; i++) {
    final error = probability(score(w, x[i])) - y[i];
    for (var j = 0; j < g.length; j++) {
      g[j] += error * x[i][j];
    }
  }
  for (var j = 0; j < g.length; j++) {
    g[j] /= x.length;
    if (j > 0) g[j] += lambda * w[j];
  }
  return g;
}

List<List<double>> matrix(int rows, int columns) =>
    List.generate(rows, (_) => List.filled(columns, 0.0));
List<List<double>> hessian(
  List<double> w,
  List<List<double>> x,
  double lambda,
) {
  final n = w.length, h = matrix(w.length, w.length);
  for (final v in x) {
    final p = probability(score(w, v));
    final variance = p * (1 - p);
    for (var j = 0; j < n; j++) {
      for (var k = 0; k <= j; k++) {
        h[j][k] += variance * v[j] * v[k];
      }
    }
  }
  for (var j = 0; j < n; j++) {
    for (var k = 0; k <= j; k++) {
      var value = h[j][k] / x.length;
      if (j == k && j > 0) value += lambda;
      h[j][k] = h[k][j] = value;
    }
  }
  return h;
}
