part of 'main.dart';

class EigenSystem {
  final List<double> values;
  final List<List<double>> vectors;
  final int sweeps;
  EigenSystem(this.values, this.vectors, this.sweeps);
}

double offDiagonal(List<List<double>> a) {
  var s = 0.0;
  for (var p = 0; p < a.length - 1; p++) {
    for (var q = p + 1; q < a.length; q++) {
      s += a[p][q] * a[p][q];
    }
  }
  return s;
}

void rotate(List<List<double>> a, List<List<double>> v, int p, int q) {
  if (a[p][q] == 0) return;
  final theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
  var t = 1 / (theta.abs() + math.sqrt(theta * theta + 1));
  if (theta < 0) t = -t;
  final c = 1 / math.sqrt(t * t + 1), s = t * c;
  for (var r = 0; r < a.length; r++) {
    if (r == p || r == q) continue;
    final x = a[r][p], y = a[r][q];
    a[r][p] = a[p][r] = c * x - s * y;
    a[r][q] = a[q][r] = s * x + c * y;
  }
  final w = a[p][q];
  a[p][p] = a[p][p] - t * w;
  a[q][q] = a[q][q] + t * w;
  a[p][q] = a[q][p] = 0;
  for (final row in v) {
    final x = row[p], y = row[q];
    row[p] = c * x - s * y;
    row[q] = s * x + c * y;
  }
}

EigenSystem jacobi(List<List<double>> matrix) {
  final a = copyMatrix(matrix),
      v = identity(matrix.length),
      initial = offDiagonal(a);
  var count = 0;
  if (initial > 0) {
    for (var number = 1; number <= 100; number++) {
      for (var p = 0; p < a.length - 1; p++) {
        for (var q = p + 1; q < a.length; q++) {
          rotate(a, v, p, q);
        }
      }
      final remaining = offDiagonal(a);
      if (count == 0 && remaining < 1e-16 * initial) count = number;
      if (remaining < 1e-22 * initial) break;
    }
  }
  final order = List.generate(a.length, (i) => i)
    ..sort((i, j) {
      final result = a[j][j].compareTo(a[i][i]);
      return result != 0 ? result : i.compareTo(j);
    });
  return EigenSystem(
    [for (final k in order) a[k][k]],
    [for (final k in order) orient(normalize(column(v, k)))],
    count,
  );
}

class PowerComponent {
  final double value;
  final List<double> vector;
  final int agreement;
  PowerComponent(this.value, this.vector, this.agreement);
}

List<PowerComponent> powerIteration(
  List<List<double>> matrix,
  List<List<double>> references,
) {
  final b = copyMatrix(matrix), out = <PowerComponent>[];
  for (final reference in references) {
    final opposite = [for (final v in reference) -v];
    var x = List.filled(reference.length, 1.0), agreement = 0;
    for (var step = 1; step <= 1000; step++) {
      x = normalize(multiply(b, x));
      final d = math.min(
        maxDifference(x, reference),
        maxDifference(x, opposite),
      );
      if (agreement == 0 && d < 0.000001) agreement = step;
    }
    final value = dot(x, multiply(b, x)), vector = orient(normalize(x));
    deflate(b, value, vector);
    out.add(PowerComponent(value, vector, agreement));
  }
  return out;
}
