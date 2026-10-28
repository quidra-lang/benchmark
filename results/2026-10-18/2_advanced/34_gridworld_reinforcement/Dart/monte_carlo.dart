part of 'main.dart';

int discountedReturn(List<int> rewards, int gamma) {
  var value = 0;
  for (final reward in rewards.reversed) {
    value = 10000 * reward + floorDiv(gamma * value, 100);
  }
  return value;
}

class ReturnAverages {
  final List<List<int>> sums, counts;
  ReturnAverages(int count)
    : sums = List.generate(count, (_) => List.filled(4, 0)),
      counts = List.generate(count, (_) => List.filled(4, 0));
  void update(List<List<int>> q, List<(int, int, int)> history, int gamma) {
    final seen = <(int, int)>{}, first = <bool>[];
    for (final (s, a, _) in history) {
      first.add(seen.add((s, a)));
    }
    var value = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      final (s, a, reward) = history[i];
      value = 10000 * reward + floorDiv(gamma * value, 100);
      if (first[i]) {
        sums[s][a] += value;
        counts[s][a]++;
        q[s][a] = floorDiv(sums[s][a], counts[s][a]);
      }
    }
  }
}
