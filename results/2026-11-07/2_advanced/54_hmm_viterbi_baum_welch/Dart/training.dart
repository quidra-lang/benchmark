part of 'main.dart';

class TrainingPair {
  final List<int> observations, path;
  TrainingPair(this.observations, this.path);
}

Model smoothedModel(
  Model template,
  String name,
  List<double> initial,
  List<List<double>> transition,
  List<List<double>> emission,
  double alpha,
) => newModel(
  name,
  template,
  [for (final v in initial) v + alpha],
  [
    for (final row in transition) [for (final v in row) v + alpha],
  ],
  [
    for (final row in emission) [for (final v in row) v + alpha],
  ],
);
Model baumWelchStep(
  Model model,
  List<List<int>> sequences,
  double pseudocount,
) {
  final k = model.states.length,
      initial = List.filled(model.states.length, 0.0),
      transition = matrix(k, k),
      emission = matrix(k, model.symbols.length);
  for (final observations in sequences) {
    final result = forwardBackward(model, observations);
    for (var i = 0; i < k; i++) {
      initial[i] += result.posterior[0][i];
    }
    for (var t = 0; t < observations.length; t++) {
      final observation = observations[t];
      for (var i = 0; i < k; i++) {
        if (observation >= 0) {
          emission[i][observation] += result.posterior[t][i];
        }
        if (t + 1 < observations.length) {
          for (var j = 0; j < k; j++) {
            transition[i][j] += posteriorTransition(model, result, t, i, j);
          }
        }
      }
    }
  }
  return smoothedModel(
    model,
    'BAUM_WELCH',
    initial,
    transition,
    emission,
    pseudocount,
  );
}

Model estimateByCounting(
  Model template,
  List<TrainingPair> pairs,
  double alpha,
  String name,
) {
  final k = template.states.length,
      m = template.symbols.length,
      initialCounts = List.filled(k, 0),
      transitionCounts = intMatrix(k, k),
      emissionCounts = intMatrix(k, m);
  for (final pair in pairs) {
    initialCounts[pair.path.first]++;
    for (var t = 0; t < pair.path.length; t++) {
      final state = pair.path[t];
      if (pair.observations[t] >= 0) {
        emissionCounts[state][pair.observations[t]]++;
      }
      if (t + 1 < pair.path.length) {
        transitionCounts[state][pair.path[t + 1]]++;
      }
    }
  }
  return smoothedModel(
    template,
    name,
    [for (final v in initialCounts) v.toDouble()],
    [
      for (final row in transitionCounts) [for (final v in row) v.toDouble()],
    ],
    [
      for (final row in emissionCounts) [for (final v in row) v.toDouble()],
    ],
    alpha,
  );
}

double totalLoglik(Model model, List<List<int>> sequences) {
  var total = 0.0;
  for (final observations in sequences) {
    total += scaledForward(model, observations).loglik;
  }
  return total;
}
