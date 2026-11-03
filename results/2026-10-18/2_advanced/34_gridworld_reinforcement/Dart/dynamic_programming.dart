part of 'main.dart';

int floorDiv(int a, int b) => a ~/ b - (a < 0 && a.remainder(b) != 0 ? 1 : 0);
int firstMax(List<int> values) {
  var best = 0;
  for (var a = 1; a < values.length; a++) {
    if (values[a] > values[best]) best = a;
  }
  return best;
}

int rowMax(List<int> row) => row[firstMax(row)];
int bellman(Environment e, List<int> values, int gamma, int state, int action) {
  var total = 0;
  for (final (cell, weight) in e.transitions[state][action]) {
    final target = e.world.stateIndex[cell],
        future = target < 0 ? 0 : floorDiv(gamma * values[target], 100);
    total += weight * (10000 * e.reward(cell) + future);
  }
  return floorDiv(total, e.slipTotal);
}

List<int> actionValues(Environment e, List<int> values, int gamma, int state) =>
    [for (var a = 0; a < 4; a++) bellman(e, values, gamma, state, a)];
List<int> greedyPolicy(Environment e, List<int> values, int gamma) => [
  for (var s = 0; s < values.length; s++)
    firstMax(actionValues(e, values, gamma, s)),
];
(List<int>, List<int>) valueIteration(Environment e, int gamma, int theta) {
  var values = List.filled(e.world.states.length, 0);
  final changes = <int>[];
  while (true) {
    final updated = [
      for (var s = 0; s < values.length; s++)
        rowMax(actionValues(e, values, gamma, s)),
    ];
    var delta = 0;
    for (var s = 0; s < values.length; s++) {
      delta = math.max(delta, (updated[s] - values[s]).abs());
    }
    changes.add(delta);
    values = updated;
    if (delta <= theta) return (values, changes);
  }
}

(List<int>, int) inPlaceValueIteration(Environment e, int gamma, int theta) {
  final values = List.filled(e.world.states.length, 0);
  for (var sweep = 1; ; sweep++) {
    var delta = 0;
    for (var s = 0; s < values.length; s++) {
      final value = rowMax(actionValues(e, values, gamma, s));
      delta = math.max(delta, (value - values[s]).abs());
      values[s] = value;
    }
    if (delta <= theta) return (values, sweep);
  }
}

(List<int>, int) evaluatePolicy(
  Environment e,
  List<int> policy,
  List<int> initial,
  int gamma,
  int theta,
) {
  final values = [...initial];
  for (var sweep = 1; ; sweep++) {
    var delta = 0;
    for (var s = 0; s < policy.length; s++) {
      final value = bellman(e, values, gamma, s, policy[s]);
      delta = math.max(delta, (value - values[s]).abs());
      values[s] = value;
    }
    if (delta <= theta) return (values, sweep);
  }
}

(List<int>, List<int>, List<(int, int, int)>) policyIteration(
  Environment e,
  int gamma,
  int theta,
) {
  var policy = List.filled(e.world.states.length, 0),
      values = List.filled(e.world.states.length, 0);
  final rounds = <(int, int, int)>[];
  while (true) {
    final (evaluated, sweeps) = evaluatePolicy(e, policy, values, gamma, theta);
    values = evaluated;
    final improved = greedyPolicy(e, values, gamma),
        changes = policy.length - agreements(improved, policy);
    rounds.add((sweeps, changes, values[e.world.startState]));
    policy = improved;
    if (changes == 0) return (policy, values, rounds);
  }
}
