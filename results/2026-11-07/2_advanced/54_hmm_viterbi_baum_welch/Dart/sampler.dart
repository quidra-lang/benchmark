part of 'main.dart';

class Minstd {
  int state;
  Minstd(this.state);
  double uniform() {
    state = 48271 * state % 2147483647;
    return state / 2147483647;
  }
}

int draw(List<double> weights, Minstd rng) {
  final total = sum(weights), threshold = rng.uniform() * total;
  var cumulative = 0.0;
  for (var i = 0; i < weights.length; i++) {
    cumulative += weights[i];
    if (threshold < cumulative) {
      return i;
    }
  }
  return weights.length - 1;
}

(List<int>, List<int>) syntheticSequence(Model model, int length, Minstd rng) {
  final states = List.filled(length, 0), observations = List.filled(length, 0);
  for (var t = 0; t < length; t++) {
    final weights = t == 0 ? model.initial : model.transition[states[t - 1]],
        state = draw(weights, rng),
        symbol = draw(model.emission[state], rng);
    states[t] = state;
    observations[t] = symbol;
  }
  return (states, observations);
}

List<int> posteriorPath(Model model, List<List<double>> forward, Minstd rng) {
  final path = List.filled(forward.length, 0);
  path[path.length - 1] = draw(forward.last, rng);
  for (var t = path.length - 2; t >= 0; t--) {
    final following = path[t + 1],
        weights = [
          for (var i = 0; i < model.states.length; i++)
            forward[t][i] * model.transition[i][following],
        ];
    path[t] = draw(weights, rng);
  }
  return path;
}
