import 'dart:math' as math;
import 'instance.dart';
import 'minstd.dart';

List<int> geneOperations(Instance instance, List<int> chromosome) {
  final counts = <int, int>{}, operations = <int>[];
  for (final j in chromosome) {
    final n = counts[j] ?? 0;
    operations.add(instance.byJob[j]!.operations[n]);
    counts[j] = n + 1;
  }
  return operations;
}

List<int> decode(Instance instance, List<int> chromosome) {
  final starts = List.filled(instance.operations.length, 0),
      ready = <int, int>{},
      free = List.filled(instance.machineCount, 0);
  for (final id in geneOperations(instance, chromosome)) {
    final o = instance.operations[id];
    starts[id] = math.max(ready[o.job] ?? 0, free[o.machine - 1]);
    ready[o.job] = free[o.machine - 1] = starts[id] + o.duration;
  }
  return starts;
}

int tournament(Minstd rng, List<int> values, int size) {
  var best = -1;
  for (var i = 0; i < size; i++) {
    final pick = rng.below(values.length);
    if (best < 0 ||
        values[pick] < values[best] ||
        values[pick] == values[best] && pick < best)
      best = pick;
  }
  return best;
}

List<int> preserveOrder(List<int> keeper, List<int> donor, Set<int> kept) {
  final fillers = donor.where((gene) => !kept.contains(gene)).iterator;
  return [
    for (final gene in keeper)
      if (kept.contains(gene)) gene else (fillers..moveNext()).current,
  ];
}

(List<int>, List<int>) crossover(
  Minstd rng,
  List<int> a,
  List<int> b,
  List<Job> jobs,
) {
  final kept = {
    for (final job in jobs)
      if (rng.below(2) == 0) job.number,
  };
  return (preserveOrder(a, b, kept), preserveOrder(b, a, kept));
}

void swapMutation(Minstd rng, List<int> chromosome) {
  final a = rng.below(chromosome.length),
      b = rng.below(chromosome.length),
      saved = chromosome[a];
  chromosome[a] = chromosome[b];
  chromosome[b] = saved;
}

void insertMutation(Minstd rng, List<int> chromosome) {
  final source = rng.below(chromosome.length),
      target = rng.below(chromosome.length);
  chromosome.insert(target, chromosome.removeAt(source));
}
