part of 'main.dart';

class Kernel {
  final String name, kind;
  final int degree;
  final double gamma, coef;
  Kernel(
    this.name,
    this.kind, [
    this.degree = 0,
    this.gamma = 0,
    this.coef = 0,
  ]);
  double value(Point a, Point b) {
    if (kind == 'rbf') {
      final e1 = a.$1 - b.$1, e2 = a.$2 - b.$2;
      return exp(-gamma * (e1 * e1 + e2 * e2));
    }
    var v = a.$1 * b.$1 + a.$2 * b.$2;
    if (kind == 'linear') return v;
    final s = gamma * v + coef;
    v = 1;
    for (var d = 0; d < degree; d++) {
      v *= s;
    }
    return v;
  }

  String get description => kind == 'linear'
      ? 'linear'
      : kind == 'poly'
      ? 'poly degree $degree gamma ${fixed(gamma, 4)} coef0 ${fixed(coef, 4)}'
      : 'rbf gamma ${fixed(gamma, 4)}';
}

List<List<double>> kernelMatrix(List<Example> a, Kernel k) => [
  for (final x in a) [for (final y in a) k.value(x.point, y.point)],
];
(List<Example>, List<List<double>>) subset(
  List<Example> a,
  List<List<double>> q,
  List<int> indices,
) => (
  [for (final i in indices) a[i]],
  [
    for (final i in indices) [for (final j in indices) q[i][j]],
  ],
);
