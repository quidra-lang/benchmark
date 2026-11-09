part of 'main.dart';

class Family {
  final List<List<int>> counts;
  final List<List<double>> learned;
  final int parameters;
  Family(this.counts, this.learned, this.parameters);
}

int parentCombination(List<int> parents, List<int> a, Network n) {
  var r = 0;
  for (final p in parents) {
    r = r * n.variables[p].states.length + a[p];
  }
  return r;
}

Family learn(int v, List<int> parents, Network n) {
  final rows = assignmentCount(parents, n), k = n.variables[v].states.length;
  final counts = List.generate(rows, (_) => List.filled(k, 0)),
      learned = List.generate(rows, (_) => List.filled(k, 0.0));
  for (final a in n.samples) {
    counts[parentCombination(parents, a, n)][a[v]]++;
  }
  for (var r = 0; r < rows; r++) {
    var total = 0.0;
    for (var s = 0; s < k; s++) {
      total += counts[r][s] + n.settings.alpha;
    }
    for (var s = 0; s < k; s++) {
      learned[r][s] = (counts[r][s] + n.settings.alpha) / total;
    }
  }
  return Family(counts, learned, (k - 1) * rows);
}

double logLikelihood(List<List<int>> counts, List<List<double>> theta) {
  var ll = 0.0;
  for (var r = 0; r < counts.length; r++) {
    for (var s = 0; s < counts[r].length; s++) {
      final count = counts[r][s];
      if (count > 0) ll += count * log(theta[r][s]);
    }
  }
  return ll;
}

double familyScore(int v, List<int> parents, Network n) {
  final f = learn(v, parents, n);
  return logLikelihood(f.counts, f.learned) -
      f.parameters * log(n.samples.length) / 2;
}
