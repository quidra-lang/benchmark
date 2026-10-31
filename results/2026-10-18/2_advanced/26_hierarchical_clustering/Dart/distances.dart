import 'dart:math' as math;

const distanceTypes = ['euclidean', 'manhattan', 'correlation'];
double sequentialSum(Iterable<double> values) {
  var total = 0.0;
  for (final value in values) { total += value; }
  return total;
}
double squaredDistance(List<double> u, List<double> w) {
  var total = 0.0;
  for (var f = 0; f < u.length; f++) {
    final difference = u[f] - w[f];
    total += difference * difference;
  }
  return total;
}
List<List<double>> floatMatrix(int rows, int columns) => List.generate(rows, (_) => List.filled(columns, 0.0));
(List<double>, List<double>) featureStatistics(List<List<double>> rows) {
  final means = <double>[];
  final deviations = <double>[];
  for (var f = 0; f < rows[0].length; f++) {
    final mean = sequentialSum(rows.map((row) => row[f])) / rows.length;
    var squares = 0.0;
    for (final row in rows) {
      final difference = row[f] - mean;
      squares += difference * difference;
    }
    means.add(mean);
    deviations.add(math.sqrt(squares / (rows.length - 1)));
  }
  return (means, deviations);
}
List<List<double>> standardizeData(List<List<double>> rows, List<double> means, List<double> deviations) =>
    [for (final row in rows) [for (var f = 0; f < row.length; f++) (row[f] - means[f]) / deviations[f]];
double distance(List<double> u, List<double> w, String kind) {
  if (kind == 'euclidean') return math.sqrt(squaredDistance(u, w));
  if (kind == 'manhattan') return sequentialSum([for (var f = 0; f < u.length; f++) (u[f] - w[f]).abs()]);
  final mu = sequentialSum(u) / u.length;
  final mw = sequentialSum(w) / w.length;
  var cross = 0.0;
  var first = 0.0;
  var second = 0.0;
  for (var f = 0; f < u.length; f++) {
    final du = u[f] - mu;
    final dw = w[f] - mw;
    cross += du * dw;
    first += du * du;
    second += dw * dw;
  }
  return 1 - cross / math.sqrt(first * second);
}
List<List<double>> distanceMatrix(List<List<double>> vectors, String kind) {
  final matrix = floatMatrix(vectors.length, vectors.length);
  for (var i = 0; i < vectors.length; i++) {
    for (var j = i + 1; j < vectors.length; j++) {
      final value = distance(vectors[i], vectors[j], kind);
      matrix[i][j] = value;
      matrix[j][i] = value;
    }
  }
  return matrix;
}
