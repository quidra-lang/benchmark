part of 'main.dart';

class Round {
  final Stump stump;
  final List<double> weights;
  final double error, alpha, z, bound, loss;
  final int polarity;
  Round(
    this.stump, {
    this.weights = const [],
    this.error = 0,
    this.alpha = 0,
    this.polarity = 0,
    this.z = 0,
    this.bound = 0,
    this.loss = 0,
  });
}

class Model {
  final rounds = <Round>[];
  String stop = 'completed';
  List<List<double>> cuts = [];
}

List<int> labelsOf(List<Row> rows) => [for (final row in rows) row.label];
List<double> uniformWeights(int n) => List.filled(n, 1 / n);
Model trainDiscrete(
  List<Row> rows,
  int maxRounds, {
  List<double>? initial,
  double shrinkage = 1,
  SearchSpace? space,
}) {
  space ??= SearchSpace(rows);
  final labels = labelsOf(rows),
      weights = initial == null
          ? uniformWeights(rows.length)
          : List<double>.of(initial);
  final model = Model();
  var bound = 1.0;
  for (var t = 0; t < maxRounds; t++) {
    final c = discreteSearch(space, labels, weights), e = c.error;
    if (e >= 0.5) {
      model.stop = 'weak';
      break;
    }
    final alpha = e <= 1e-10 ? 1.0 : shrinkage * (0.5 * log((1 - e) / e));
    final stump = Stump(
      c.feature,
      [c.threshold],
      [-c.polarity * alpha, c.polarity * alpha],
    );
    final before = List<double>.of(weights),
        updated = List.filled(weights.length, 0.0);
    for (var i = 0; i < rows.length; i++) {
      final decision = rows[i].values[c.feature] > c.threshold
          ? c.polarity
          : -c.polarity;
      final factor = exp(decision == rows[i].label ? -alpha : alpha);
      if (weights[i] != 0) {
        updated[i] = weights[i] * factor;
      }
    }
    final z = sum(updated);
    for (var i = 0; i < weights.length; i++) {
      weights[i] = updated[i] / z;
    }
    bound *= z;
    model.rounds.add(
      Round(
        stump,
        weights: before,
        error: e,
        alpha: alpha,
        polarity: c.polarity,
        z: z,
        bound: bound,
      ),
    );
    if (e <= 1e-10) {
      model.stop = 'perfect';
      break;
    }
  }
  return model;
}

Model trainSamme(List<Row> rows, int maxRounds, int classes) {
  final space = SearchSpace(rows),
      labels = labelsOf(rows),
      weights = uniformWeights(rows.length),
      model = Model();
  for (var t = 0; t < maxRounds; t++) {
    final (stump, e) = multiclassSearch(space, labels, weights, classes);
    if (e >= (classes - 1) / classes) {
      model.stop = 'weak';
      break;
    }
    final alpha = e <= 1e-10 ? 1.0 : log((1 - e) / e) + log(classes - 1);
    final updated = List<double>.of(weights);
    for (var i = 0; i < rows.length; i++) {
      if (stump.output(rows[i].values).toInt() != rows[i].label) {
        updated[i] *= exp(alpha);
      }
    }
    final z = sum(updated);
    for (var i = 0; i < weights.length; i++) {
      weights[i] = updated[i] / z;
    }
    model.rounds.add(Round(stump, error: e, alpha: alpha));
    if (e <= 1e-10) {
      model.stop = 'perfect';
      break;
    }
  }
  return model;
}
