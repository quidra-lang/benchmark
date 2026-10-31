part of 'main.dart';

class Model {
  final List<int> selected;
  final List<double> coefficients;
  final List<List<double>> inverse;
  Model(this.selected, this.coefficients, this.inverse);
}

double angle(double speed, double t) {
  final d = speed * t, d2 = d - 360 * (d / 360).floor();
  return d2 * 3.141592653589793 / 180;
}

List<double> regressors(double t, List<int> selected, List<Constituent> c) {
  final x = List.filled(1 + 2 * selected.length, 0.0);
  x[0] = 1;
  for (var k = 0; k < selected.length; k++) {
    final a = angle(c[selected[k]].speed, t);
    x[2 * k + 1] = cos(a);
    x[2 * k + 2] = sin(a);
  }
  return x;
}

Model fit(
  List<int> times,
  Map<int, double> values,
  List<int> selected,
  List<Constituent> c,
) {
  final p = 1 + 2 * selected.length,
      m = List.generate(
        1 + 2 * selected.length,
        (_) => List.filled(2 * (1 + 2 * selected.length) + 1, 0.0),
      );
  for (var i = 0; i < p; i++) {
    m[i][p + 1 + i] = 1;
  }
  for (final t in times) {
    final x = regressors(t.toDouble(), selected, c);
    for (var i = 0; i < p; i++) {
      for (var j = 0; j < p; j++) {
        m[i][j] += x[i] * x[j];
      }
      m[i][p] += x[i] * values[t]!;
    }
  }
  for (var j = 0; j < p; j++) {
    var pivot = j;
    for (var i = j + 1; i < p; i++) {
      if (m[i][j].abs() > m[pivot][j].abs()) pivot = i;
    }
    final swap = m[j];
    m[j] = m[pivot];
    m[pivot] = swap;
    for (var i = j + 1; i < p; i++) {
      final f = m[i][j] / m[j][j];
      for (var col = j; col <= 2 * p; col++) {
        m[i][col] -= f * m[j][col];
      }
    }
  }
  var coefficients = <double>[];
  final inverse = List.generate(p, (_) => List.filled(p, 0.0));
  for (var col = p; col <= 2 * p; col++) {
    final sol = List.filled(p, 0.0);
    for (var i = p - 1; i >= 0; i--) {
      var s = m[i][col];
      for (var j = i + 1; j < p; j++) {
        s -= m[i][j] * sol[j];
      }
      sol[i] = s / m[i][i];
    }
    if (col == p) {
      coefficients = sol;
    } else {
      for (var i = 0; i < p; i++) {
        inverse[i][col - p - 1] = sol[i];
      }
    }
  }
  return Model(List.of(selected), coefficients, inverse);
}

(double, double) amplitudePhase(double a, double b) {
  final amp = sqrt(a * a + b * b);
  var g = atan2(b, a) * 180 / 3.141592653589793;
  if (g < 0) g += 360;
  return (amp, g);
}
