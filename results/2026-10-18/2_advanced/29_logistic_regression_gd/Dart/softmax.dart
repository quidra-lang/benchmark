import 'dart:math' as math;
import 'logistic.dart';
import 'optimizers.dart' show move;

List<double> shiftedScores(List<List<double>> w, List<double> v) {
  final scores = w.map((row) => score(row, v)).toList();
  final top = scores.reduce(math.max);
  return scores.map((value) => value - top).toList();
}

List<double> softmaxProbabilities(List<List<double>> w, List<double> v) {
  final values = shiftedScores(w, v);
  var total = 0.0;
  for (final u in values) {
    total += math.exp(u);
  }
  return values.map((u) => math.exp(u) / total).toList();
}

int predictedClass(List<double> values) {
  var best = 0;
  for (var k = 1; k < values.length; k++) {
    if (values[k] > values[best]) best = k;
  }
  return best;
}

double softmaxLoss(List<List<double>> w, List<double> v, int label) {
  final values = shiftedScores(w, v);
  var total = 0.0;
  for (final u in values) {
    total += math.exp(u);
  }
  return math.log(total) - values[label];
}

double softmaxAverage(List<List<double>> w, List<List<double>> x, List<int> y) {
  var total = 0.0;
  for (var i = 0; i < x.length; i++) {
    total += softmaxLoss(w, x[i], y[i]);
  }
  return total / x.length;
}

double softmaxObjective(
  List<List<double>> w,
  List<List<double>> x,
  List<int> y,
  double lambda,
) {
  var penalty = 0.0;
  for (final row in w) {
    for (final value in row.skip(1)) {
      penalty += value * value;
    }
  }
  return softmaxAverage(w, x, y) + lambda * penalty / 2;
}

List<List<double>> softmaxGradient(
  List<List<double>> w,
  List<List<double>> x,
  List<int> y,
  double lambda,
) {
  final g = matrix(w.length, w.first.length);
  for (var i = 0; i < x.length; i++) {
    final probabilities = softmaxProbabilities(w, x[i]);
    for (var k = 0; k < w.length; k++) {
      final error = probabilities[k] - (y[i] == k ? 1 : 0);
      for (var j = 0; j < w[k].length; j++) {
        g[k][j] += error * x[i][j];
      }
    }
  }
  for (var k = 0; k < w.length; k++) {
    for (var j = 0; j < w[k].length; j++) {
      g[k][j] /= x.length;
      if (j > 0) g[k][j] += lambda * w[k][j];
    }
  }
  return g;
}

typedef SoftCheckpoint = (int, List<List<double>>);
List<SoftCheckpoint> softmaxTrain(
  List<List<double>> x,
  List<int> y,
  int classes,
  double lambda,
  double rate,
  int iterations,
) {
  var w = matrix(classes, x.first.length);
  final checkpoints = <SoftCheckpoint>[(0, w)];
  for (var t = 1; t <= iterations; t++) {
    final g = softmaxGradient(w, x, y, lambda);
    w = [for (var k = 0; k < classes; k++) move(w[k], g[k], rate)];
    if (t % 100 == 0) checkpoints.add((t, w));
  }
  return checkpoints;
}
