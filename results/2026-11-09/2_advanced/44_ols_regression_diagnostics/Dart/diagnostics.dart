part of 'main.dart';

class RowDiagnostic {
  final double standardized, studentized, cooks, dffits;
  final String flags;
  final List<double> dfbetas;
  RowDiagnostic(
    this.standardized,
    this.studentized,
    this.cooks,
    this.dffits,
    this.flags,
    this.dfbetas,
  );
}

class Diagnostic {
  final rows = <RowDiagnostic>[];
  late double dw, bp, bpP, jb, jbP, skewness, kurtosis;
  late int bpDF;
}

Diagnostic calculateDiagnostics(Fit f, Params p) {
  final n = f.n,
      r = f.rank,
      df = n - r,
      sigma = math.sqrt(f.rss / df),
      leverageLimit = p.leverage * r / n,
      cookLimit = p.cook / n,
      dffitsLimit = p.dffits * math.sqrt(r / n),
      result = Diagnostic();
  for (var i = 0; i < n; i++) {
    final h = f.leverage[i],
        eps = f.weightedResidual[i],
        z = eps / (sigma * math.sqrt(1 - h)),
        t = z * math.sqrt((df - 1) / (df - z * z)),
        cook = z * z * h / (r * (1 - h)),
        dffits = t * math.sqrt(h / (1 - h));
    var flags = '';
    if (h > leverageLimit) flags += 'H';
    if (t.abs() > p.studentized) flags += 'O';
    if (cook > cookLimit) flags += 'C';
    if (dffits.abs() > dffitsLimit) flags += 'F';
    if (flags.isEmpty) flags = '-';
    final deleted = sigma * math.sqrt((df - z * z) / (df - 1)),
        db = [
          for (var k = 0; k < r; k++)
            f.g[i][k] * eps / (1 - h) / (deleted * math.sqrt(f.variance[k])),
        ];
    result.rows.add(RowDiagnostic(z, t, cook, dffits, flags, db));
  }
  var numerator = 0.0;
  for (var i = 1; i < n; i++) {
    final d = f.weightedResidual[i] - f.weightedResidual[i - 1];
    numerator += d * d;
  }
  result.dw = numerator / f.rss;
  final squared = [for (final v in f.weightedResidual) v * v],
      accepted = [
        for (final row in f.matrix) [for (final j in f.accepted) row[j]],
      ],
      aux = Fit(accepted, squared, List.filled(n, 1.0), p.tolerance),
      mean = squared.fold(0.0, (a, b) => a + b) / n;
  var tss = 0.0;
  for (final v in squared) {
    tss += (v - mean) * (v - mean);
  }
  result.bp = n * (1 - aux.rss / tss);
  result.bpDF = aux.rank - 1;
  result.bpP = chiP(result.bp, result.bpDF);
  final epsMean = f.weightedResidual.fold(0.0, (a, b) => a + b) / n;
  var m2 = 0.0, m3 = 0.0, m4 = 0.0;
  for (final v in f.weightedResidual) {
    final d = v - epsMean;
    m2 += d * d;
    m3 += d * d * d;
    m4 += d * d * d * d;
  }
  m2 /= n;
  m3 /= n;
  m4 /= n;
  result.skewness = m3 / (m2 * math.sqrt(m2));
  result.kurtosis = m4 / (m2 * m2);
  final s = result.skewness, k = result.kurtosis;
  result.jb = n / 6 * (s * s + (k - 3) * (k - 3) / 4);
  result.jbP = chiP(result.jb, 2);
  return result;
}
