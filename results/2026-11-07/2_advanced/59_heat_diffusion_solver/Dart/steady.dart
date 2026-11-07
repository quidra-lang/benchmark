part of 'main.dart';

List<List<double>> direct(Plate plate, List<List<double>> right) {
  final n = plate.c.length,
      w = plate.mesh.w,
      matrix = List.generate(n, (_) => List.filled(n, 0.0));
  for (var p = 0; p < n; p++) {
    matrix[p][p] = plate.a[p];
    for (final f in plate.faces[p]) {
      if (f.neighbor >= 0) matrix[p][f.neighbor] = -f.g;
    }
  }
  final rhs = right.map((r) => List<double>.of(r)).toList();
  for (var k = 0; k < n; k++) {
    for (var i = k + 1; i <= min(n - 1, k + w); i++) {
      final factor = matrix[i][k] / matrix[k][k];
      matrix[i][k] = 0;
      for (var j = k + 1; j <= min(n - 1, k + w); j++) {
        matrix[i][j] -= factor * matrix[k][j];
      }
      for (final r in rhs) {
        r[i] -= factor * r[k];
      }
    }
  }
  final out = <List<double>>[];
  for (final y in rhs) {
    final x = List.filled(n, 0.0);
    for (var i = n - 1; i >= 0; i--) {
      var v = y[i];
      for (var j = i + 1; j <= min(n - 1, i + w); j++) {
        v -= matrix[i][j] * x[j];
      }
      x[i] = v / matrix[i][i];
    }
    out.add(x);
  }
  return out;
}

double iterationValue(Plate plate, List<double> x, int p) {
  var s = 0.0;
  for (final f in plate.faces[p]) {
    if (f.neighbor >= 0) {
      s += f.g * x[f.neighbor];
    } else if (f.boundary) {
      s += f.g * f.theta;
    }
  }
  return (s + plate.sall[p]) / plate.a[p];
}

class Solver {
  final String name;
  final double omega;
  final List<double> field, deltas = [];
  bool converged = false;
  double rate = 0, error = 0, residual = 0;
  final milestones = List.filled(4, 0);
  Solver(this.name, this.omega, int n, double initial)
    : field = List.filled(n, initial);
}

Solver iterate(
  Plate plate,
  String name,
  double omega,
  double initial,
  double tolerance,
  int maximum,
) {
  final out = Solver(name, omega, plate.c.length, initial);
  for (var k = 1; k <= maximum; k++) {
    final before = List<double>.of(out.field);
    if (name == 'jacobi') {
      for (var p = 0; p < out.field.length; p++) {
        out.field[p] = iterationValue(plate, before, p);
      }
    } else {
      for (var p = 0; p < out.field.length; p++) {
        final y = iterationValue(plate, out.field, p);
        out.field[p] = name == 'gauss_seidel'
            ? y
            : out.field[p] + omega * (y - out.field[p]);
      }
    }
    final delta = maxDifference(out.field, before);
    out.deltas.add(delta);
    const factors = [1000, 100, 10, 1];
    for (var i = 0; i < 4; i++) {
      if (out.milestones[i] == 0 && delta < tolerance * factors[i])
        out.milestones[i] = k;
    }
    if (delta < tolerance) {
      out.converged = true;
      break;
    }
  }
  final k = out.deltas.length;
  out.rate = sqrt(out.deltas[k - 1] / out.deltas[k - 3]);
  return out;
}

double residual(Plate plate, List<double> x, List<double> b) {
  var maximum = 0.0;
  for (var p = 0; p < x.length; p++) {
    var v = b[p];
    for (final f in plate.faces[p]) {
      if (f.neighbor >= 0) v += f.g * x[f.neighbor];
    }
    v -= plate.a[p] * x[p];
    maximum = max(maximum, v.abs());
  }
  return maximum;
}
