part of 'main.dart';

const z95 = 1.959963984540054;
List<List<double>> zeros(int n) => List.generate(n, (_) => List.filled(n, 0.0));
List<double> solve(List<List<double>> matrix, List<double> vector) {
  final n = vector.length,
      a = [
        for (final row in matrix) [...row],
      ],
      b = [...vector];
  for (var k = 0; k < n; k++) {
    for (var i = k + 1; i < n; i++) {
      final f = a[i][k] / a[k][k];
      for (var j = k; j < n; j++) {
        a[i][j] -= f * a[k][j];
      }
      b[i] -= f * b[k];
    }
  }
  final x = List.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    var v = b[i];
    for (var j = i + 1; j < n; j++) {
      v -= a[i][j] * x[j];
    }
    x[i] = v / a[i][i];
  }
  return x;
}

List<List<double>> inverse(List<List<double>> matrix) {
  final n = matrix.length, out = zeros(matrix.length);
  for (var c = 0; c < n; c++) {
    final unit = List.filled(n, 0.0);
    unit[c] = 1;
    final x = solve(matrix, unit);
    for (var r = 0; r < n; r++) {
      out[r][c] = x[r];
    }
  }
  return out;
}

double logGamma(double a) {
  const coefficients = [
    76.18009172947146,
    -86.50532032941677,
    24.01409824083091,
    -1.231739572450155,
    0.001208650973866179,
    -0.000005395239384953,
  ];
  var xi = a + 5.5;
  xi = xi - (a + 0.5) * math.log(xi);
  var sigma = 1.000000000190015, y = a;
  for (final g in coefficients) {
    y += 1;
    sigma += g / y;
  }
  return -xi + math.log(2.5066282746310005 * sigma / a);
}

double gammaQ(double a, double x) {
  if (x == 0) return 1;
  final pref = math.exp(-x + a * math.log(x) - logGamma(a));
  if (x < a + 1) {
    var alpha = a, xi = 1 / a, sigma = 1 / a;
    for (var i = 0; i < 1000; i++) {
      alpha++;
      xi *= x / alpha;
      sigma += xi;
      if (xi.abs() < sigma.abs() * 1e-15) break;
    }
    return 1 - sigma * pref;
  }
  const eps = 1e-300;
  var b = x + 1 - a, c = 1 / eps, d = 1 / b, h = d;
  for (var i = 1; i <= 1000; i++) {
    final an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (d.abs() < eps) d = eps;
    c = b + an / c;
    if (c.abs() < eps) c = eps;
    d = 1 / d;
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < 1e-15) break;
  }
  return pref * h;
}

double chiP(double statistic, int degrees) =>
    gammaQ(degrees / 2, statistic / 2);
