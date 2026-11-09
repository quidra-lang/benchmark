part of 'main.dart';

List<List<double>> zeros(int n) => List.generate(n, (_) => List.filled(n, 0.0));
double dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

List<List<double>> cholesky(List<List<double>> a) {
  final l = zeros(a.length);
  for (var i = 0; i < a.length; i++) {
    for (var j = 0; j <= i; j++) {
      var s = 0.0;
      for (var k = 0; k < j; k++) {
        s += l[i][k] * l[j][k];
      }
      final r = a[i][j] - s;
      l[i][j] = i == j ? math.sqrt(r) : r / l[j][j];
    }
  }
  return l;
}

List<double> forward(List<List<double>> l, List<double> r) {
  final z = List.filled(l.length, 0.0);
  for (var i = 0; i < l.length; i++) {
    var s = 0.0;
    for (var k = 0; k < i; k++) {
      s += l[i][k] * z[k];
    }
    z[i] = (r[i] - s) / l[i][i];
  }
  return z;
}

List<double> backward(List<List<double>> l, List<double> r) {
  final v = List.filled(l.length, 0.0);
  for (var i = l.length - 1; i >= 0; i--) {
    var s = 0.0;
    for (var k = i + 1; k < l.length; k++) {
      s += l[k][i] * v[k];
    }
    v[i] = (r[i] - s) / l[i][i];
  }
  return v;
}

double logDet(List<List<double>> l) {
  var s = 0.0;
  for (var i = 0; i < l.length; i++) {
    s += math.log(l[i][i]);
  }
  return 2 * s;
}

double quadratic(List<List<double>> l, List<double> r) {
  final z = forward(l, r);
  return dot(z, z);
}

class Eigen {
  final List<double> values;
  final List<List<double>> vectors;
  final int sweeps;
  Eigen(this.values, this.vectors, this.sweeps);
}

Eigen jacobi(List<List<double>> a) {
  final n = a.length,
      m = [
        for (final row in a) [...row],
      ],
      v = zeros(a.length);
  for (var i = 0; i < n; i++) {
    v[i][i] = 1;
  }
  var sweeps = 0;
  while (true) {
    var off = 0.0;
    for (var a = 0; a < n - 1; a++) {
      for (var b = a + 1; b < n; b++) {
        off += m[a][b] * m[a][b];
      }
    }
    if (math.sqrt(off) < 1e-12 || sweeps == 50) break;
    for (var a = 0; a < n - 1; a++) {
      for (var b = a + 1; b < n; b++) {
        if (m[a][b] == 0) continue;
        final theta = (m[b][b] - m[a][a]) / (2 * m[a][b]),
            sg = theta < 0 ? -1 : 1,
            t = sg / (theta.abs() + math.sqrt(theta * theta + 1)),
            co = 1 / math.sqrt(t * t + 1),
            si = t * co;
        for (var k = 0; k < n; k++) {
          if (k == a || k == b) continue;
          final x = m[k][a], y = m[k][b];
          m[k][a] = m[a][k] = co * x - si * y;
          m[k][b] = m[b][k] = si * x + co * y;
        }
        final w = m[a][b];
        m[a][a] = m[a][a] - t * w;
        m[b][b] = m[b][b] + t * w;
        m[a][b] = m[b][a] = 0;
        for (var k = 0; k < n; k++) {
          final x = v[k][a], y = v[k][b];
          v[k][a] = co * x - si * y;
          v[k][b] = si * x + co * y;
        }
      }
    }
    sweeps++;
  }
  return Eigen([for (var i = 0; i < n; i++) m[i][i]], v, sweeps);
}
