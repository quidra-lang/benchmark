import 'dart:math' as math;
import 'instance.dart';

(List<int>, int, int) dispatch(
  Instance instance,
  String rule, [
  List<int>? genePositions,
]) {
  final starts = List.filled(instance.operations.length, 0),
      next = <int, int>{},
      ready = <int, int>{},
      free = List.filled(instance.machineCount, 0);
  var decisions = 0, ties = 0;
  for (var step = 0; step < starts.length; step++) {
    final candidates = <int>[], earliest = <int, int>{};
    var cutoff = 1 << 30, machine = 1 << 30;
    for (final job in instance.jobs) {
      final index = next[job.number] ?? 0;
      if (index == job.operations.length) continue;
      final id = job.operations[index],
          o = instance.operations[job.operations[index]];
      final es = math.max(ready[job.number] ?? 0, free[o.machine - 1]),
          ec =
              math.max(ready[job.number] ?? 0, free[o.machine - 1]) +
              o.duration;
      candidates.add(id);
      earliest[id] = es;
      if (ec < cutoff || ec == cutoff && o.machine < machine) {
        cutoff = ec;
        machine = o.machine;
      }
    }
    var best = -1, bestPriority = 1 << 30, count = 0, tied = 0;
    for (final id in candidates) {
      final o = instance.operations[id];
      if (o.machine != machine || earliest[id]! >= cutoff) continue;
      count++;
      final priority = switch (rule) {
        'SPT' => o.duration,
        'LPT' => -o.duration,
        'MWKR' => -o.duration - o.tail,
        'FIFO' => ready[o.job] ?? 0,
        _ => genePositions![id],
      };
      if (priority < bestPriority) {
        best = id;
        bestPriority = priority;
        tied = 1;
      } else if (priority == bestPriority) {
        tied++;
      }
    }
    if (count > 1) decisions++;
    if (tied > 1) ties++;
    final o = instance.operations[best];
    starts[best] = earliest[best]!;
    ready[o.job] = free[machine - 1] = starts[best] + o.duration;
    next[o.job] = (next[o.job] ?? 0) + 1;
  }
  return (starts, decisions, ties);
}
