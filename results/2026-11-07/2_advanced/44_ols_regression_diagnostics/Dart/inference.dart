part of 'main.dart';

double logGamma(double x) {
  const coefficients = [
    76.18009172947146,
    -86.50532032941677,
    24.01409824083091,
    -1.231739572450155,
    0.001208650973866179,
    -0.000005395239384953,
  ];
  final t = x + 5.5, adjustment = t - (x + 0.5) * math.log(t);
  var series = 1.000000000190015;
  for (var j = 0; j < coefficients.length; j++) {
    series += coefficients[j] / (x + (j + 1));
  }
  return -adjustment + math.log(2.5066282746310005 * series / x);
}

double replaceSmall(double value) => value.abs() < 1e-300 ? 1e-300 : value;
double betaFraction(double a, double b, double x) {
  var c = 1.0, d = 1 / replaceSmall(1 - (a + b) * x / (a + 1)), h = d;
  for (var m = 1; m <= 1000; m++) {
    var q = m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m));
    d = 1 / replaceSmall(1 + q * d);
    c = replaceSmall(1 + q / c);
    h *= d * c;
    q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m));
    d = 1 / replaceSmall(1 + q * d);
    c = replaceSmall(1 + q / c);
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < 1e-15) break;
  }
  return h;
}

double incompleteBeta(double x, double a, double b) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final factor = math.exp(
    logGamma(a + b) -
        logGamma(a) -
        logGamma(b) +
        a * math.log(x) +
        b * math.log(1 - x),
  );
  return x < (a + 1) / (a + b + 2)
      ? factor * betaFraction(a, b, x) / a
      : 1 - factor * betaFraction(b, a, 1 - x) / b;
}

double upperGamma(double a, double x) {
  if (x <= 0) return 1;
  final factor = math.exp(-x + a * math.log(x) - logGamma(a));
  if (x < a + 1) {
    var term = 1 / a, e = a, series = term;
    for (var i = 0; i < 1000; i++) {
      e++;
      term *= x / e;
      series += term;
      if (term.abs() < series.abs() * 1e-15) break;
    }
    return 1 - series * factor;
  }
  var b = x + 1 - a, c = 1 / 1e-300, d = 1 / b, h = d;
  for (var i = 1; i <= 1000; i++) {
    final q = -i * (i - a);
    b += 2;
    d = 1 / replaceSmall(q * d + b);
    c = replaceSmall(b + q / c);
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < 1e-15) break;
  }
  return factor * h;
}

double tP(double t, int df) {
  final nu = df.toDouble();
  return incompleteBeta(nu / (nu + t * t), nu / 2, 0.5);
}

double fP(double f, int d1, int d2) =>
    incompleteBeta(d2 / (d2 + d1 * f), d2 / 2, d1 / 2);
double chiP(double stat, int df) => upperGamma(df / 2, stat / 2);
double tQuantile(double confidence, int df) {
  var lo = 0.0, hi = 1000.0;
  for (var i = 0; i < 100; i++) {
    final mid = (lo + hi) / 2;
    if (tP(mid, df) > 1 - confidence)
      lo = mid;
    else
      hi = mid;
  }
  return (lo + hi) / 2;
}

String significance(double p) {
  if (p.isNaN) return '';
  if (p < 0.001) return '***';
  if (p < 0.01) return '**';
  if (p < 0.05) return '*';
  if (p < 0.1) return '.';
  return '';
}

String four(double value) {
  if (value.isNaN) return 'NA';
  final s = value.toStringAsFixed(4);
  return s == '-0.0000' ? '0.0000' : s;
}

String probability(double value) => value.isNaN
    ? 'NA'
    : value < 0.0001
    ? '<0.0001'
    : four(value);
