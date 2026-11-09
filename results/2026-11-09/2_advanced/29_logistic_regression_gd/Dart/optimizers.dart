import 'dart:math' as math;
import 'logistic.dart';

class Minstd {
  int state;
  Minstd(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }

  void shuffle(List<int> values) {
    for (var size = values.length; size > 1; size--) {
      final j = draw() % size, saved = values[size - 1];
      values[size - 1] = values[j];
      values[j] = saved;
    }
  }
}

typedef Checkpoint = (int, List<double>);
List<double> move(List<double> w, List<double> g, double rate) => [
  for (var j = 0; j < w.length; j++) w[j] - rate * g[j],
];
List<Checkpoint> gradientDescent(
  List<List<double>> x,
  List<int> y,
  double lambda,
  double rate,
  int iterations,
) {
  var w = List.filled(x.first.length, 0.0);
  final checkpoints = <Checkpoint>[(0, w)];
  for (var t = 1; t <= iterations; t++) {
    w = move(w, gradient(w, x, y, lambda), rate);
    if (t % 100 == 0) checkpoints.add((t, w));
  }
  return checkpoints;
}

List<Checkpoint> stochasticDescent(
  List<List<double>> x,
  List<int> y,
  double lambda,
  double rate,
  int batchSize,
  int epochs,
  int seed,
) {
  final rng = Minstd(seed), order = List.generate(x.length, (i) => i);
  var w = List.filled(x.first.length, 0.0);
  final checkpoints = <Checkpoint>[(0, w)];
  for (var e = 1; e <= epochs; e++) {
    rng.shuffle(order);
    for (var start = 0; start < order.length; start += batchSize) {
      final batch = order.sublist(
        start,
        math.min(start + batchSize, order.length),
      );
      w = move(
        w,
        gradient(
          w,
          batch.map((i) => x[i]).toList(),
          batch.map((i) => y[i]).toList(),
          lambda,
        ),
        rate,
      );
    }
    checkpoints.add((e, w));
  }
  return checkpoints;
}

List<List<double>> cholesky(List<List<double>> a) {
  final n = a.length, lower = matrix(a.length, a.length);
  for (var j = 0; j < n; j++) {
    for (var i = j; i < n; i++) {
      var total = 0.0;
      for (var k = 0; k < j; k++) {
        total += lower[i][k] * lower[j][k];
      }
      final remainder = a[i][j] - total;
      if (i == j) {
        lower[j][j] = math.sqrt(remainder);
      } else {
        lower[i][j] = remainder / lower[j][j];
      }
    }
  }
  return lower;
}

List<double> solve(List<List<double>> lower, List<double> b) {
  final n = b.length,
      z = List.filled(b.length, 0.0),
      x = List.filled(b.length, 0.0);
  for (var i = 0; i < n; i++) {
    var total = 0.0;
    for (var k = 0; k < i; k++) {
      total += lower[i][k] * z[k];
    }
    z[i] = (b[i] - total) / lower[i][i];
  }
  for (var i = n - 1; i >= 0; i--) {
    var total = 0.0;
    for (var k = i + 1; k < n; k++) {
      total += lower[k][i] * x[k];
    }
    x[i] = (z[i] - total) / lower[i][i];
  }
  return x;
}

(List<double>, List<double>) newtonDirection(
  List<double> w,
  List<List<double>> x,
  List<int> y,
  double lambda,
) {
  final g = gradient(w, x, y, lambda);
  return (g, solve(cholesky(hessian(w, x, lambda)), g));
}

List<Checkpoint> newtonMethod(
  List<List<double>> x,
  List<int> y,
  double lambda,
) {
  var w = List.filled(x.first.length, 0.0);
  final checkpoints = <Checkpoint>[(0, w)];
  for (var t = 1; t <= 10; t++) {
    final (_, step) = newtonDirection(w, x, y, lambda);
    w = move(w, step, 1);
    checkpoints.add((t, w));
  }
  return checkpoints;
}

List<double> finalWeights(List<Checkpoint> checkpoints) => checkpoints.last.$2;
