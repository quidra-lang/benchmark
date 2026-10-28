part of 'main.dart';

typedef Fraction = (int, int);
Fraction fraction(int a, int b) {
  if (b == 0) return (0, 0);
  final g = a.abs().gcd(b);
  return (a ~/ g, b ~/ g);
}

Fraction addFractions(Fraction a, Fraction b) =>
    fraction(a.$1 * b.$2 + b.$1 * a.$2, a.$2 * b.$2);

class Metrics {
  final List<List<int>> matrix;
  final List<int> support;
  final List<Fraction> recall, precision, f1;
  int correct = 0;
  late final Fraction accuracy, balanced, kappa;
  double macroF1 = 0;
  Metrics(List<int> actual, List<int> predicted, int c)
    : matrix = List.generate(c, (_) => List.filled(c, 0)),
      support = List.filled(c, 0),
      recall = [],
      precision = [],
      f1 = [] {
    for (var i = 0; i < actual.length; i++) {
      matrix[actual[i]][predicted[i]]++;
    }
    final counts = List.filled(c, 0);
    for (var a = 0; a < c; a++) {
      for (var b = 0; b < c; b++) {
        support[a] += matrix[a][b];
        counts[b] += matrix[a][b];
      }
    }
    Fraction recallSum = (0, 1);
    var expected = 0;
    for (var k = 0; k < c; k++) {
      final v = matrix[k][k];
      correct += v;
      recall.add(fraction(v, support[k]));
      precision.add(fraction(v, counts[k]));
      f1.add(fraction(2 * v, support[k] + counts[k]));
      recallSum = addFractions(recallSum, recall[k]);
      expected += support[k] * counts[k];
      macroF1 += (2 * v) / (support[k] + counts[k]);
    }
    macroF1 /= c;
    final n = actual.length;
    accuracy = fraction(correct, n);
    balanced = fraction(recallSum.$1, recallSum.$2 * c);
    kappa = fraction(n * correct - expected, n * n - expected);
  }
}

(int, int, double) mcnemar(List<int> actual, List<int> a, List<int> b) {
  var b01 = 0, b10 = 0;
  for (var i = 0; i < actual.length; i++) {
    final ca = a[i] == actual[i], cb = b[i] == actual[i];
    if (ca && !cb)
      b01++;
    else if (cb && !ca)
      b10++;
  }
  var chi = 0.0;
  if (b01 != b10) {
    final d = (b01 - b10).abs() - 1;
    chi = d * d / (b01 + b10);
  }
  return (b01, b10, chi);
}

class RandomGenerator {
  int state;
  RandomGenerator(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }
}
