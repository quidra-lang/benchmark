part of 'main.dart';

int lineClass(int slack, bool last) => last
    ? 1
    : slack <= 1
    ? 0
    : slack <= 3
    ? 1
    : slack <= 6
    ? 2
    : 3;
int lineCost(
  TextMetrics m,
  int start,
  int end,
  int previousClass,
  Map<String, int> p,
) {
  final slack = m.slack(start, end),
      last = end == m.end,
      current = lineClass(m.slack(start, end), end == m.end);
  var cost = p['line_penalty']!;
  if (slack < 0) {
    cost += p['overfull_penalty']!;
  } else if (!last) {
    cost += slack * slack;
  }
  if (m.breaks[end].midword) {
    cost += p['hyphen_penalty']!;
    if (m.breaks[start].midword) cost += p['double_hyphen_demerit']!;
  }
  if (last && m.breaks[start].midword) cost += p['final_hyphen_demerit']!;
  if ((current - previousClass).abs() >= 2) cost += p['fitness_demerit']!;
  return cost;
}

int breakingCost(TextMetrics m, List<int> breaking, Map<String, int> p) {
  var total = 0, previous = 0, previousClass = 1;
  for (final end in breaking) {
    total += lineCost(m, previous, end, previousClass, p);
    previousClass = lineClass(m.slack(previous, end), end == m.end);
    previous = end;
  }
  return total;
}

(List<int>, int) knuthPlass(TextMetrics m, Map<String, int> p) {
  final states = List.generate(
    m.end + 1,
    (_) => List<(int, int, int)?>.filled(4, null),
  );
  states[0][1] = (0, 0, 0);
  for (var end = 1; end <= m.end; end++) {
    for (var start = end - 1; start >= 0; start--) {
      final slack = m.slack(start, end);
      if (slack < 0 && end != start + 1) break;
      final current = lineClass(slack, end == m.end);
      for (var previousClass = 0; previousClass < 4; previousClass++) {
        final previous = states[start][previousClass];
        if (previous == null) continue;
        final cost = previous.$1 + lineCost(m, start, end, previousClass, p),
            best = states[end][current];
        if (best == null ||
            cost < best.$1 ||
            cost == best.$1 &&
                (start < best.$2 ||
                    start == best.$2 && previousClass < best.$3))
          states[end][current] = (cost, start, previousClass);
      }
    }
  }
  final breaking = <int>[];
  var position = m.end, current = 1;
  final cost = states[position][current]!.$1;
  while (position > 0) {
    breaking.add(position);
    final state = states[position][current]!;
    position = state.$2;
    current = state.$3;
  }
  return (breaking.reversed.toList(), cost);
}

(List<int>, int) greedyBreaking(TextMetrics m, Map<String, int> p) {
  final breaking = <int>[];
  var start = 0;
  while (start < m.end) {
    var chosen = start + 1;
    if (m.slack(start, chosen) >= 0) {
      for (var end = chosen + 1; end <= m.end; end++) {
        if (m.slack(start, end) < 0) break;
        chosen = end;
      }
    }
    breaking.add(chosen);
    start = chosen;
  }
  return (breaking, breakingCost(m, breaking, p));
}

(List<int>, int) breakText(TextMetrics m, String method, Map<String, int> p) =>
    method == 'kp' ? knuthPlass(m, p) : greedyBreaking(m, p);
