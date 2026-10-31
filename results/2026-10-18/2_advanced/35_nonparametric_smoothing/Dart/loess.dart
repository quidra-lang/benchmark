part of 'main.dart';

double median(List<double> values) {
  final ordered = [...values]..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2;
}

List<List<double>> cholesky(List<List<double>> matrix) {
  final n = matrix.length,
      lower = List.generate(
        matrix.length,
        (_) => List.filled(matrix.length, 0.0),
      );
  for (var k = 0; k < n; k++) {
    for (var l = 0; l <= k; l++) {
      var sigma = matrix[k][l];
      for (var j = 0; j < l; j++) {
        sigma -= lower[k][j] * lower[l][j];
      }
      lower[k][l] = l == k ? math.sqrt(sigma) : sigma / lower[l][l];
    }
  }
  return lower;
}

List<double> solve(List<List<double>> lower, List<double> right) {
  final n = right.length,
      eta = List.filled(right.length, 0.0),
      solution = List.filled(right.length, 0.0);
  for (var k = 0; k < n; k++) {
    var v = right[k];
    for (var j = 0; j < k; j++) {
      v -= lower[k][j] * eta[j];
    }
    eta[k] = v / lower[k][k];
  }
  for (var k = n - 1; k >= 0; k--) {
    var v = eta[k];
    for (var j = k + 1; j < n; j++) {
      v -= lower[j][k] * solution[j];
    }
    solution[k] = v / lower[k][k];
  }
  return solution;
}

typedef LocalFit = (double, double, List<double>);

class LoessFit extends Fit {
  final List<int> positions;
  final List<double> x, y, rho;
  final int span, degree;
  final records = <(int, double, int, double)>[];
  final cache = <int, LocalFit>{};
  LoessFit(
    this.positions,
    this.y,
    this.span,
    this.degree,
    int iterations,
    bool diagnostics,
  ) : x = positions.map((p) => p / 100).toList(),
      rho = List.filled(positions.length, 1.0) {
    if (!diagnostics) return;
    var fits = positions.map(local).toList();
    for (var iteration = 1; iteration <= iterations; iteration++) {
      final residuals = [for (var i = 0; i < y.length; i++) y[i] - fits[i].$1],
          scale = median([
            for (var i = 0; i < y.length; i++) (y[i] - fits[i].$1).abs(),
          ]);
      var zeros = 0;
      for (var i = 0; i < y.length; i++) {
        final u = residuals[i] / (6 * scale), v = 1 - u * u;
        rho[i] = u.abs() < 1 ? v * v : 0.0;
        if (rho[i] == 0) zeros++;
      }
      final updated = positions.map(local).toList();
      var change = 0.0;
      for (var i = 0; i < y.length; i++) {
        change = math.max(change, (updated[i].$1 - fits[i].$1).abs());
      }
      records.add((iteration, scale, zeros, change));
      fits = updated;
    }
    fitted = [for (final fit in fits) fit.$1];
    leverage = [for (var i = 0; i < y.length; i++) rho[i] * fits[i].$2];
    edf = orderedSum(leverage!);
    for (var i = 0; i < y.length; i++) {
      cache[positions[i]] = fits[i];
    }
  }
  LocalFit local(int position) {
    final n = positions.length,
        order = List.generate(positions.length, (i) => i)
          ..sort((a, b) {
            final cmp = (positions[a] - position).abs().compareTo(
              (positions[b] - position).abs(),
            );
            return cmp != 0 ? cmp : a.compareTo(b);
          });
    final neighbors = order.take(span * n ~/ 100).toList();
    final distance = neighbors
        .map((i) => (positions[i] - position).abs())
        .reduce(math.max);
    neighbors.sort();
    final size = degree + 1,
        matrix = List.generate(degree + 1, (_) => List.filled(degree + 1, 0.0)),
        right = List.filled(degree + 1, 0.0),
        rows = <(int, double, List<double>)>[];
    for (final i in neighbors) {
      final a = (positions[i] - position).abs() / distance,
          s = 1 - a * a * a,
          v = s * s * s * rho[i],
          d = x[i] - position / 100,
          basis = [1.0, d, if (degree == 2) d * d];
      rows.add((i, v, basis));
      for (var k = 0; k < size; k++) {
        right[k] += v * basis[k] * y[i];
        for (var l = 0; l < size; l++) {
          matrix[k][l] += v * basis[k] * basis[l];
        }
      }
    }
    final lower = cholesky(matrix);
    final beta = solve(lower, right);
    final zeta = solve(lower, [1.0, for (var k = 0; k < degree; k++) 0.0]),
        weights = List.filled(n, 0.0);
    for (final (i, v, basis) in rows) {
      var total = 0.0;
      for (var k = 0; k < size; k++) {
        total += zeta[k] * basis[k];
      }
      weights[i] = v * total;
    }
    return (beta[0], zeta[0], weights);
  }

  LocalFit evaluate(int position) =>
      cache.putIfAbsent(position, () => local(position));
  @override
  double estimate(int position) => evaluate(position).$1;
  @override
  List<double> weights(int position) => evaluate(position).$3;
}
