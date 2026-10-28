part of 'main.dart';

const kernelConstants = {
  'epanechnikov': 0.75,
  'biweight': 0.9375,
  'triweight': 1.09375,
};

class KernelFit extends Fit {
  final List<int> positions;
  final List<double> x, y;
  final int bandwidth;
  final String kernel;
  final bool localLinear;
  final cache = <int, (double, List<double>?)>{};
  KernelFit(
    this.positions,
    this.y,
    this.bandwidth,
    this.kernel,
    this.localLinear,
    bool diagnostics,
  ) : x = positions.map((p) => p / 100).toList() {
    if (diagnostics) {
      leverage = List.filled(y.length, 0.0);
      fitted = List.filled(y.length, 0.0);
      for (var i = 0; i < y.length; i++) {
        final result = evaluate(positions[i]);
        if (result.$1.isNaN) {
          fitted = [];
          leverage = null;
          return;
        }
        fitted[i] = result.$1;
        leverage![i] = result.$2![i];
      }
      edf = orderedSum(leverage!);
    }
  }
  (double, List<double>?) evaluate(int position) {
    final existing = cache[position];
    if (existing != null) return existing;
    final used = [
      for (var i = 0; i < positions.length; i++)
        if ((positions[i] - position).abs() < bandwidth) i,
    ];
    if (used.length < (localLinear ? 2 : 1))
      return cache[position] = (double.nan, null);
    final x0 = position / 100,
        h = bandwidth / 100,
        kernels = <double>[],
        differences = <double>[];
    var s0 = 0.0, t0 = 0.0, s1 = 0.0, s2 = 0.0, t1 = 0.0;
    for (final i in used) {
      final d = x[i] - x0, u = d / h, t = 1 - u * u;
      var k = kernelConstants[kernel]! * t;
      if (kernel != 'epanechnikov') k *= t;
      if (kernel == 'triweight') k *= t;
      kernels.add(k);
      differences.add(d);
      s0 += k;
      t0 += k * y[i];
      s1 += k * d;
      s2 += k * d * d;
      t1 += k * d * y[i];
    }
    final weights = List.filled(positions.length, 0.0);
    var estimate = t0 / s0;
    if (localLinear) {
      final q = s0 * s2 - s1 * s1;
      estimate = (s2 * t0 - s1 * t1) / q;
      for (var j = 0; j < used.length; j++) {
        weights[used[j]] = kernels[j] * (s2 - s1 * differences[j]) / q;
      }
    } else {
      for (var j = 0; j < used.length; j++) {
        weights[used[j]] = kernels[j] / s0;
      }
    }
    return cache[position] = (estimate, weights);
  }

  @override
  double estimate(int position) => evaluate(position).$1;
  @override
  List<double>? weights(int position) => evaluate(position).$2;
}
