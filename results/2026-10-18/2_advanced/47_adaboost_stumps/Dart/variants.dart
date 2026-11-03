part of 'main.dart';

List<double> updateWeights(List<Row> rows, List<double> weights, Stump stump) {
  final result = [
    for (var i = 0; i < rows.length; i++)
      weights[i] * exp(-rows[i].label * stump.output(rows[i].values)),
  ];
  final z = sum(result);
  for (var i = 0; i < result.length; i++) {
    result[i] /= z;
  }
  return result;
}

Model trainReal(
  List<Row> rows,
  int maxRounds,
  int bins,
  double smoothing,
  double convergence,
) {
  final space = SearchSpace(rows);
  final (cuts, assignments) = realGeometry(space, bins);
  final labels = labelsOf(rows), model = Model()..cuts = cuts;
  var weights = uniformWeights(rows.length), bound = 1.0;
  for (var t = 0; t < maxRounds; t++) {
    final c = realSearch(assignments, labels, weights, bins), z = c.error;
    if (z >= 1 - convergence) {
      model.stop = 'converged';
      break;
    }
    final values = [
      for (var b = 0; b < bins; b++)
        0.5 * log((c.positive[b] + smoothing) / (c.negative[b] + smoothing)),
    ];
    final stump = Stump(c.feature, cuts[c.feature], values);
    bound *= z;
    model.rounds.add(
      Round(stump, weights: List<double>.of(weights), z: z, bound: bound),
    );
    weights = updateWeights(rows, weights, stump);
  }
  return model;
}

Model trainGentle(List<Row> rows, int maxRounds) {
  final space = SearchSpace(rows),
      targets = [for (final row in rows) row.label.toDouble()],
      model = Model();
  var weights = uniformWeights(rows.length);
  for (var t = 0; t < maxRounds; t++) {
    final (stump, e) = regressionSearch(space, targets, weights);
    model.rounds.add(Round(stump, weights: List<double>.of(weights), error: e));
    weights = updateWeights(rows, weights, stump);
  }
  return model;
}

Model trainLogit(List<Row> rows, int maxRounds, double clip) {
  final space = SearchSpace(rows),
      scores = List.filled(rows.length, 0.0),
      probabilities = List.filled(rows.length, 0.5),
      model = Model();
  for (var t = 0; t < maxRounds; t++) {
    final q = List.filled(rows.length, 0.0),
        responses = List.filled(rows.length, 0.0);
    for (var i = 0; i < rows.length; i++) {
      final p = probabilities[i], target = rows[i].label == 1 ? 1.0 : 0.0;
      q[i] = p * (1 - p);
      responses[i] = ((target - p) / q[i]).clamp(-clip, clip).toDouble();
    }
    final z = sum(q), weights = [for (final w in q) w / z];
    final (fitted, e) = regressionSearch(space, responses, weights);
    final stump = Stump(fitted.feature, fitted.thresholds, [
      fitted.values[0] / 2,
      fitted.values[1] / 2,
    ]);
    var loss = 0.0;
    for (var i = 0; i < rows.length; i++) {
      scores[i] += stump.output(rows[i].values);
      probabilities[i] = 1 / (1 + exp(-2 * scores[i]));
      loss += log(1 + exp(-2 * rows[i].label * scores[i]));
    }
    loss /= rows.length;
    model.rounds.add(Round(stump, weights: weights, error: e, loss: loss));
  }
  return model;
}
