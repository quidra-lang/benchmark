part of 'main.dart';

class PairCounts {
  int n = 0, s = 0, v = 0;
}

PairCounts tally(String a, String b, List<int> weights) {
  final c = PairCounts();
  for (var i = 0; i < weights.length; i++) {
    final x = a[i], y = b[i];
    if (!isBase(x) || !isBase(y)) continue;
    final w = weights[i];
    c.n += w;
    if (x != y) {
      if ((x == 'A' && y == 'G') ||
          (x == 'G' && y == 'A') ||
          (x == 'C' && y == 'T') ||
          (x == 'T' && y == 'C')) {
        c.s += w;
      } else {
        c.v += w;
      }
    }
  }
  return c;
}

(double, bool) distance(PairCounts c, String model, double saturation) {
  final n = c.n, s = c.s, v = c.v;
  if (n == 0 ||
      (model == 'JC' && 4 * (s + v) >= 3 * n) ||
      (model == 'K2P' && (2 * s + v >= n || 2 * v >= n)))
    return (saturation, true);
  if (model == 'P') return ((s + v) / n, false);
  if (model == 'JC') return (-0.75 * log(1 - 4 * (s + v) / (3 * n)), false);
  return (-0.5 * log(1 - 2 * s / n - v / n) - 0.25 * log(1 - 2 * v / n), false);
}

List<List<double>> distanceMatrix(
  List<SequenceRecord> taxa,
  List<int> weights,
  String model,
  double saturation,
) {
  final n = taxa.length,
      d = List.generate(taxa.length, (_) => List.filled(taxa.length, 0.0));
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final (value, _) = distance(
        tally(taxa[i].sequence, taxa[j].sequence, weights),
        model,
        saturation,
      );
      d[i][j] = value;
      d[j][i] = value;
    }
  }
  return d;
}
