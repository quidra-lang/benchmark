part of 'main.dart';

int choose(RandomGenerator g, List<int> row, int epsilon) =>
    g.draw() % 1000 < epsilon ? g.draw() % 4 : firstMax(row);
int tdTarget(int reward, bool terminal, int next, int gamma) =>
    10000 * reward + (terminal ? 0 : floorDiv(gamma * next, 100));
int expectedValue(List<int> row, int epsilon) =>
    floorDiv(epsilon * sum(row) + 4 * (1000 - epsilon) * rowMax(row), 4000);
void tdUpdate(List<int> row, int action, int target, int alpha) {
  row[action] += floorDiv(alpha * (target - row[action]), 100);
}

class DynaModel {
  final List<List<(int, int)?>> outcomes;
  final pairs = <(int, int)>[];
  DynaModel(int count)
    : outcomes = List.generate(count, (_) => List.filled(4, null));
  void record(int state, int action, int reward, int next) {
    if (outcomes[state][action] == null) pairs.add((state, action));
    outcomes[state][action] = (reward, next);
  }

  void plan(
    RandomGenerator g,
    List<List<int>> q,
    int gamma,
    int alpha,
    int count,
  ) {
    for (var i = 0; i < count; i++) {
      final (state, action) = pairs[g.draw() % pairs.length];
      final (reward, next) = outcomes[state][action]!;
      tdUpdate(
        q[state],
        action,
        tdTarget(reward, next < 0, next < 0 ? 0 : rowMax(q[next]), gamma),
        alpha,
      );
    }
  }
}
