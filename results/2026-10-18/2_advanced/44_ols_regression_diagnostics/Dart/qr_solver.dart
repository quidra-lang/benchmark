part of 'main.dart';

List<List<double>> zeros(int rows, int cols) =>
    List.generate(rows, (_) => List.filled(cols, 0.0));

class Fit {
  final List<List<double>> matrix;
  final List<double> response, weights;
  late final int n, p, rank;
  final accepted = <int>[], aliases = <int>[];
  late final List<List<double>> triangular, inverse, g;
  late final List<double> effects,
      beta,
      variance,
      leverage,
      fitted,
      residual,
      weightedResidual;
  double rss = 0;
  Fit(this.matrix, this.response, this.weights, double tolerance) {
    n = matrix.length;
    p = matrix.first.length;
    beta = List.filled(p, double.nan);
    final roots = weights.map(math.sqrt).toList(),
        weighted = [
          for (var i = 0; i < n; i++) [for (final x in matrix[i]) roots[i] * x],
        ],
        work = [
          for (final row in weighted) [...row],
        ],
        b = [for (var i = 0; i < n; i++) roots[i] * response[i]],
        lengths = List.filled(p, 0.0),
        fullR = zeros(p, p);
    for (var j = 0; j < p; j++) {
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        sum += weighted[i][j] * weighted[i][j];
      }
      lengths[j] = math.sqrt(sum);
    }
    for (var j = 0; j < p; j++) {
      final k = accepted.length;
      var sum = 0.0;
      for (var i = k; i < n; i++) {
        sum += work[i][j] * work[i][j];
      }
      final eta = math.sqrt(sum);
      if (eta <= tolerance * lengths[j]) {
        aliases.add(j);
        continue;
      }
      accepted.add(j);
      final alpha = work[k][j] >= 0 ? -eta : eta,
          v = [work[k][j] - alpha, for (var i = k + 1; i < n; i++) work[i][j]];
      var squared = 0.0;
      for (final x in v) {
        squared += x * x;
      }
      for (var l = 0; l < k; l++) {
        fullR[l][k] = work[l][j];
      }
      fullR[k][k] = alpha;
      for (var l = j + 1; l < p; l++) {
        var dot = 0.0;
        for (var i = k; i < n; i++) {
          dot += v[i - k] * work[i][l];
        }
        final delta = 2 * dot / squared;
        for (var i = k; i < n; i++) {
          work[i][l] = work[i][l] - delta * v[i - k];
        }
      }
      var dot = 0.0;
      for (var i = k; i < n; i++) {
        dot += v[i - k] * b[i];
      }
      final delta = 2 * dot / squared;
      for (var i = k; i < n; i++) {
        b[i] = b[i] - delta * v[i - k];
      }
    }
    rank = accepted.length;
    final r = rank;
    triangular = [for (final row in fullR.take(r)) row.take(r).toList()];
    effects = b.take(r).toList();
    for (var k = r - 1; k >= 0; k--) {
      var tail = 0.0;
      for (var l = k + 1; l < r; l++) {
        tail += triangular[k][l] * beta[accepted[l]];
      }
      beta[accepted[k]] = (effects[k] - tail) / triangular[k][k];
    }
    inverse = zeros(r, r);
    for (var m = 0; m < r; m++) {
      for (var l = r - 1; l >= 0; l--) {
        final diagonal = l == m ? 1.0 : 0.0;
        var tail = 0.0;
        for (var q = l + 1; q < r; q++) {
          tail += triangular[l][q] * inverse[q][m];
        }
        inverse[l][m] = (diagonal - tail) / triangular[l][l];
      }
    }
    variance = List.filled(r, 0.0);
    for (var k = 0; k < r; k++) {
      for (final v in inverse[k]) {
        variance[k] += v * v;
      }
    }
    g = zeros(n, r);
    leverage = List.filled(n, 0.0);
    fitted = List.filled(n, 0.0);
    residual = List.filled(n, 0.0);
    weightedResidual = List.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      final u = List.filled(r, 0.0);
      for (var k = 0; k < r; k++) {
        for (var m = 0; m < r; m++) {
          u[k] += weighted[i][accepted[m]] * inverse[m][k];
        }
        leverage[i] += u[k] * u[k];
      }
      for (var k = 0; k < r; k++) {
        for (var m = 0; m < r; m++) {
          g[i][k] += inverse[k][m] * u[m];
        }
      }
      for (final j in accepted) {
        fitted[i] += matrix[i][j] * beta[j];
      }
      residual[i] = response[i] - fitted[i];
      weightedResidual[i] = roots[i] * residual[i];
    }
    for (final v in weightedResidual) {
      rss += v * v;
    }
  }
}
