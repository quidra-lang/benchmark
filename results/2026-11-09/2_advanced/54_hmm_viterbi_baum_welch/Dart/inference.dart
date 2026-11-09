part of 'main.dart';

int maximumIndex(List<double> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[best]) {
      best = i;
    }
  }
  return best;
}

List<double> emissionFactors(Model model, int observation, bool logarithm) => [
  for (var i = 0; i < model.states.length; i++)
    observation < 0
        ? (logarithm ? 0.0 : 1.0)
        : logarithm
        ? log(model.emission[i][observation])
        : model.emission[i][observation],
];

class Forward {
  final values = <List<double>>[],
      emissions = <List<double>>[],
      scales = <double>[];
  double loglik = 0;
}

Forward scaledForward(Model model, List<int> observations) {
  final result = Forward(), k = model.states.length;
  for (var t = 0; t < observations.length; t++) {
    final factors = emissionFactors(model, observations[t], false),
        values = List.filled(k, 0.0);
    result.emissions.add(factors);
    for (var state = 0; state < k; state++) {
      if (t == 0) {
        values[state] = model.initial[state] * factors[state];
      } else {
        var total = 0.0;
        for (var previous = 0; previous < k; previous++) {
          total +=
              result.values[t - 1][previous] *
              model.transition[previous][state];
        }
        values[state] = total * factors[state];
      }
    }
    final scale = sum(values);
    result.scales.add(scale);
    for (var i = 0; i < k; i++) {
      values[i] /= scale;
    }
    result.values.add(values);
    result.loglik += log(scale);
  }
  return result;
}

class ForwardBackward {
  final Forward forward;
  final List<List<double>> backward, posterior;
  ForwardBackward(this.forward, this.backward, this.posterior);
}

ForwardBackward forwardBackward(Model model, List<int> observations) {
  final forward = scaledForward(model, observations),
      k = model.states.length,
      length = observations.length,
      backward = matrix(length, k);
  for (var i = 0; i < k; i++) {
    backward[length - 1][i] = 1;
  }
  for (var t = length - 2; t >= 0; t--) {
    for (var i = 0; i < k; i++) {
      var total = 0.0;
      for (var j = 0; j < k; j++) {
        total +=
            model.transition[i][j] *
            forward.emissions[t + 1][j] *
            backward[t + 1][j];
      }
      backward[t][i] = total / forward.scales[t + 1];
    }
  }
  final posterior = [
    for (var t = 0; t < length; t++)
      [for (var i = 0; i < k; i++) forward.values[t][i] * backward[t][i]],
  ];
  return ForwardBackward(forward, backward, posterior);
}

double posteriorTransition(
  Model model,
  ForwardBackward result,
  int t,
  int i,
  int j,
) =>
    result.forward.values[t][i] *
    model.transition[i][j] *
    result.forward.emissions[t + 1][j] *
    result.backward[t + 1][j] /
    result.forward.scales[t + 1];
(List<int>, double) viterbi(Model model, List<int> observations) {
  final k = model.states.length,
      transition = [for (final row in model.transition) row.map(log).toList()],
      predecessors = List.generate(
        observations.length,
        (_) => List.filled(model.states.length, 0),
      );
  var factors = emissionFactors(model, observations.first, true),
      scores = [for (var i = 0; i < k; i++) log(model.initial[i]) + factors[i]];
  for (var t = 1; t < observations.length; t++) {
    factors = emissionFactors(model, observations[t], true);
    final next = List.filled(k, 0.0);
    for (var state = 0; state < k; state++) {
      final candidates = [
            for (var previous = 0; previous < k; previous++)
              scores[previous] + transition[previous][state],
          ],
          previous = maximumIndex(candidates);
      predecessors[t][state] = previous;
      next[state] = candidates[previous] + factors[state];
    }
    scores = next;
  }
  final path = List.filled(observations.length, 0);
  path[path.length - 1] = maximumIndex(scores);
  final logprob = scores[path.last];
  for (var t = path.length - 1; t > 0; t--) {
    path[t - 1] = predecessors[t][path[t]];
  }
  return (path, logprob);
}

class Decoding {
  final List<int> viterbi, posterior;
  final double viterbiLogprob;
  final List<double> confidence;
  final ForwardBackward fb;
  Decoding(
    this.viterbi,
    this.posterior,
    this.viterbiLogprob,
    this.confidence,
    this.fb,
  );
}

Decoding decode(Model model, List<int> observations) {
  final fb = forwardBackward(model, observations);
  final (path, logprob) = viterbi(model, observations);
  final posterior = [for (final row in fb.posterior) maximumIndex(row)],
      confidence = [
        for (var t = 0; t < observations.length; t++)
          fb.posterior[t][posterior[t]],
      ];
  return Decoding(path, posterior, logprob, confidence, fb);
}
