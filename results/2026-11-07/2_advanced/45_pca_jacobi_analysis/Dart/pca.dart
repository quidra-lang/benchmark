part of 'main.dart';

List<double> columnMeans(List<List<double>> rows) {
  final out = List.filled(rows.first.length, 0.0);
  for (var j = 0; j < out.length; j++) {
    var s = 0.0;
    for (final row in rows) {
      s += row[j];
    }
    out[j] = s / rows.length;
  }
  return out;
}

List<List<double>> covarianceMatrix(
  List<List<double>> rows,
  List<double> means,
) {
  final p = means.length,
      dev = [
        for (final row in rows)
          [for (var j = 0; j < means.length; j++) row[j] - means[j]],
      ],
      cov = zeros(p, p);
  for (var j = 0; j < p; j++) {
    for (var k = j; k < p; k++) {
      var s = 0.0;
      for (final row in dev) {
        s += row[j] * row[k];
      }
      cov[j][k] = cov[k][j] = s / (rows.length - 1);
    }
  }
  return cov;
}

List<double> standardDeviations(List<List<double>> cov) => [
  for (var j = 0; j < cov.length; j++) math.sqrt(cov[j][j]),
];
List<List<double>> correlationMatrix(List<List<double>> cov, List<double> sd) =>
    [
      for (var j = 0; j < cov.length; j++)
        [
          for (var k = 0; k < cov.length; k++)
            j == k ? 1.0 : cov[j][k] / (sd[j] * sd[k]),
        ],
    ];
List<double> standardize(
  List<double?> values,
  List<double> means,
  List<double> scales,
) => [
  for (var j = 0; j < values.length; j++)
    values[j] == null ? 0.0 : (values[j]! - means[j]) / scales[j],
];
List<double> componentScores(List<double> z, List<List<double>> vectors) => [
  for (final v in vectors) dot(z, v),
];
List<double> residuals(
  List<double> z,
  List<double> scores,
  List<List<double>> vectors,
  int count,
) {
  final out = <double>[];
  for (var j = 0; j < z.length; j++) {
    var s = 0.0;
    for (var k = 0; k < count; k++) {
      s += scores[k] * vectors[k][j];
    }
    out.add(z[j] - s);
  }
  return out;
}

double hotelling(List<double> scores, List<double> eigenvalues, int count) {
  var s = 0.0;
  for (var k = 0; k < count; k++) {
    s += scores[k] * scores[k] / eigenvalues[k];
  }
  return s;
}
