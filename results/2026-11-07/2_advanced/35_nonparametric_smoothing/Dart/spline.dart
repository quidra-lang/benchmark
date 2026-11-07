part of 'main.dart';

typedef SplineValues = (List<double>, List<double>);

class SplineFit extends Fit {
  final List<int> positions;
  final List<double> x;
  final double penalty;
  late final List<double> h, d, l1, l2;
  late final SplineValues fit;
  List<SplineValues>? basis;
  SplineFit(this.positions, List<double> values, this.penalty, bool diagnostics)
    : x = positions.map((p) => p / 100).toList() {
    h = [for (var i = 0; i < positions.length - 1; i++) x[i + 1] - x[i]];
    decompose();
    fit = fitValues(values);
    fitted = fit.$1;
    if (diagnostics) prepareBasis();
  }
  void decompose() {
    final size = positions.length - 2,
        a = [for (var i = 0; i < positions.length - 2; i++) 1 / h[i]],
        c = [for (var i = 0; i < positions.length - 2; i++) 1 / h[i + 1]];
    final b = [for (var i = 0; i < size; i++) -(a[i] + c[i])];
    final diagonal = [
          for (var i = 0; i < size; i++)
            (h[i] + h[i + 1]) / 3 +
                penalty * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i]),
        ],
        first = [
          for (var i = 0; i < size - 1; i++)
            h[i + 1] / 6 + penalty * c[i] * (b[i] + b[i + 1]),
        ],
        second = [for (var i = 0; i < size - 2; i++) penalty * c[i] * c[i + 1]];
    d = List.filled(size, 0.0);
    l1 = List.filled(size, 0.0);
    l2 = List.filled(size, 0.0);
    for (var i = 0; i < size; i++) {
      if (i >= 2) l2[i] = second[i - 2] / d[i - 2];
      if (i >= 1) {
        final correction = i >= 2 ? l2[i] * d[i - 2] * l1[i - 1] : 0.0;
        l1[i] = (first[i - 1] - correction) / d[i - 1];
      }
      var value = diagonal[i];
      if (i >= 1) value -= l1[i] * l1[i] * d[i - 1];
      if (i >= 2) value -= l2[i] * l2[i] * d[i - 2];
      d[i] = value;
    }
  }

  SplineValues fitValues(List<double> values) {
    final n = values.length,
        size = values.length - 2,
        z = List.filled(values.length - 2, 0.0);
    for (var i = 0; i < size; i++) {
      var value =
          (values[i + 2] - values[i + 1]) / h[i + 1] -
          (values[i + 1] - values[i]) / h[i];
      if (i >= 1) value -= l1[i] * z[i - 1];
      if (i >= 2) value -= l2[i] * z[i - 2];
      z[i] = value;
    }
    final gamma = List.filled(n, 0.0);
    for (var i = size - 1; i >= 0; i--) {
      var value = z[i] / d[i];
      if (i + 1 < size) value -= l1[i + 1] * gamma[i + 2];
      if (i + 2 < size) value -= l2[i + 2] * gamma[i + 3];
      gamma[i + 1] = value;
    }
    final omega = [
      (gamma[1] - gamma[0]) / h[0],
      for (var i = 1; i < n - 1; i++)
        (gamma[i + 1] - gamma[i]) / h[i] - (gamma[i] - gamma[i - 1]) / h[i - 1],
      0 - (gamma[n - 1] - gamma[n - 2]) / h[n - 2],
    ];
    return (
      [for (var i = 0; i < n; i++) values[i] - penalty * omega[i]],
      gamma,
    );
  }

  double evaluateFit(SplineValues fit, int position) {
    final g = fit.$1, gamma = fit.$2, n = fit.$1.length, x0 = position / 100;
    var index = 0;
    while (index < positions.length && positions[index] < position) {
      index++;
    }
    if (index < n && positions[index] == position) return g[index];
    if (index == 0) {
      final tau = (g[1] - g[0]) / h[0] - h[0] * gamma[1] / 6;
      return g[0] - (x[0] - x0) * tau;
    }
    if (index == n) {
      final tau =
          (g[n - 1] - g[n - 2]) / h[n - 2] + h[n - 2] * gamma[n - 2] / 6;
      return g[n - 1] + (x0 - x[n - 1]) * tau;
    }
    final i = index - 1, pl = x0 - x[index - 1], pr = x[index] - x0;
    return (pl * g[i + 1] + pr * g[i]) / h[i] -
        pl *
            pr *
            ((1 + pl / h[i]) * gamma[i + 1] + (1 + pr / h[i]) * gamma[i]) /
            6;
  }

  void prepareBasis() {
    if (basis != null) return;
    final units = <SplineValues>[];
    for (var i = 0; i < positions.length; i++) {
      final unit = List.filled(positions.length, 0.0);
      unit[i] = 1;
      units.add(fitValues(unit));
    }
    basis = units;
    leverage = [for (var i = 0; i < units.length; i++) units[i].$1[i]];
    edf = orderedSum(leverage!);
  }

  @override
  double estimate(int position) => evaluateFit(fit, position);
  @override
  List<double> weights(int position) {
    prepareBasis();
    return basis!.map((fit) => evaluateFit(fit, position)).toList();
  }
}
