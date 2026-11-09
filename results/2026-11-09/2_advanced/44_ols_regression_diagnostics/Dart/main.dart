import 'dart:io';
import 'dart:math' as math;

part 'dataframe.dart';
part 'formula.dart';
part 'qr_solver.dart';
part 'inference.dart';
part 'diagnostics.dart';

class Statistics {
  final int df;
  final double sigma,
      weightSum,
      tss,
      r2,
      adjusted,
      f,
      p,
      ll,
      aic,
      bic,
      press,
      predicted,
      critical;
  final List<double> quantiles;
  Statistics(
    this.df,
    this.sigma,
    this.weightSum,
    this.tss,
    this.r2,
    this.adjusted,
    this.f,
    this.p,
    this.ll,
    this.aic,
    this.bic,
    this.press,
    this.predicted,
    this.critical,
    this.quantiles,
  );
}

class Coefficient {
  final double estimate, se, t, p, lower, upper, robustSE, robustT, robustP;
  Coefficient(
    this.estimate,
    this.se,
    this.t,
    this.p,
    this.lower,
    this.upper,
    this.robustSE,
    this.robustT,
    this.robustP,
  );
}

class Anova {
  final int index, df;
  final String name;
  final double ss, ms, rss, f, p;
  Anova({
    this.index = -1,
    required this.name,
    required this.df,
    required this.ss,
    this.ms = 0,
    this.rss = 0,
    required this.f,
    required this.p,
  });
}

class VIFResult {
  final String name;
  final double value;
  final bool high;
  VIFResult(this.name, this.value, this.high);
}

class ResetResult {
  final double f, p;
  final int addedDF, residualDF;
  ResetResult(this.f, this.addedDF, this.residualDF, this.p);
}

class PredictionCheck {
  int predicted = 0, actual = 0, covered = 0;
  double rmse = double.nan;
}

class Report {
  final int number;
  final Design design;
  late final Fit fit;
  late final Statistics stats;
  late final List<Coefficient> coefficients;
  late final List<Anova> anova, marginal;
  late final List<VIFResult> vif;
  late final Diagnostic diagnostic;
  late final ResetResult reset;
  late final List<String> predictions;
  late final PredictionCheck check;
  Report(this.number, this.design, Params p, DataFrame predict) {
    fit = Fit(design.matrix, design.response, design.weights, p.tolerance);
    stats = modelStatistics(fit, p.confidence);
    coefficients = coefficientInference(fit, stats);
    anova = sequentialANOVA(design, fit);
    marginal = marginalTests(design, fit, allTerms(design.model), p.tolerance);
    vif = varianceInflation(design, fit, stats, p);
    diagnostic = calculateDiagnostics(fit, p);
    reset = resetTest(fit, p.tolerance);
    final result = predictionReport(number, design, fit, stats, predict);
    predictions = result.$1;
    check = result.$2;
  }
}

List<String> table(
  List<String> header,
  List<List<String>> rows, [
  List<String> marks = const [],
]) {
  final all = [header, ...rows], widths = List.filled(header.length, 0);
  for (final row in all) {
    for (var c = 0; c < row.length; c++) {
      widths[c] = math.max(widths[c], row[c].length);
    }
  }
  final lines = <String>[];
  for (var i = 0; i < all.length; i++) {
    final row = all[i];
    var line = row.first.padRight(widths.first);
    for (var c = 1; c < row.length; c++) {
      line += '  ${row[c].padLeft(widths[c])}';
    }
    if (i > 0 && i - 1 < marks.length && marks[i - 1].isNotEmpty)
      line += ' ${marks[i - 1]}';
    lines.add(line.replaceFirst(RegExp(r' +$'), ''));
  }
  return lines;
}

double orderedSum(Iterable<double> values) {
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return sum;
}

(double, double, double) informationCriteria(Fit f) {
  var logs = 0.0;
  for (final w in f.weights) {
    logs += math.log(w);
  }
  final n = f.n,
      ll =
          0.5 *
          (logs -
              n * (math.log(2 * math.pi) + 1 - math.log(n) + math.log(f.rss))),
      aic = -2 * ll + 2 * (f.rank + 1),
      bic = -2 * ll + math.log(n) * (f.rank + 1);
  return (ll, aic, bic);
}

Statistics modelStatistics(Fit f, double confidence) {
  final n = f.n, r = f.rank, df = n - r, weightSum = orderedSum(f.weights);
  var sumY = 0.0;
  for (var i = 0; i < n; i++) {
    sumY += f.weights[i] * f.response[i];
  }
  final mean = sumY / weightSum;
  var tss = 0.0;
  for (var i = 0; i < n; i++) {
    final y = f.response[i];
    tss += f.weights[i] * (y - mean) * (y - mean);
  }
  final r2 = 1 - f.rss / tss,
      adjusted = 1 - (1 - r2) * (n - 1) / df,
      stat = ((tss - f.rss) / (r - 1)) / (f.rss / df);
  final (ll, aic, bic) = informationCriteria(f);
  var press = 0.0;
  for (var i = 0; i < n; i++) {
    final v = f.weightedResidual[i] / (1 - f.leverage[i]);
    press += v * v;
  }
  final residuals = [...f.weightedResidual]..sort(), quantiles = <double>[];
  for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
    final g = (n - 1) * p, k = g.floor();
    var q = residuals[k];
    if (k + 1 < n) q = q + (g - k) * (residuals[k + 1] - q);
    quantiles.add(q);
  }
  return Statistics(
    df,
    math.sqrt(f.rss / df),
    weightSum,
    tss,
    r2,
    adjusted,
    stat,
    fP(stat, r - 1, df),
    ll,
    aic,
    bic,
    press,
    1 - press / tss,
    tQuantile(confidence, df),
    quantiles,
  );
}

List<Coefficient> coefficientInference(Fit f, Statistics s) {
  final omega = [
        for (var i = 0; i < f.n; i++)
          f.weightedResidual[i] *
              f.weightedResidual[i] /
              ((1 - f.leverage[i]) * (1 - f.leverage[i])),
      ],
      indices = {for (var k = 0; k < f.rank; k++) f.accepted[k]: k},
      out = <Coefficient>[];
  for (var j = 0; j < f.p; j++) {
    final estimate = f.beta[j];
    if (estimate.isNaN) {
      const v = double.nan;
      out.add(Coefficient(v, v, v, v, v, v, v, v, v));
      continue;
    }
    final k = indices[j]!,
        se = s.sigma * math.sqrt(f.variance[k]),
        t = estimate / se,
        half = s.critical * se;
    var sum = 0.0;
    for (var i = 0; i < f.n; i++) {
      sum += omega[i] * f.g[i][k] * f.g[i][k];
    }
    final robust = math.sqrt(sum), rt = estimate / robust;
    out.add(
      Coefficient(
        estimate,
        se,
        t,
        tP(t, s.df),
        estimate - half,
        estimate + half,
        robust,
        rt,
        tP(rt, s.df),
      ),
    );
  }
  return out;
}

List<int> allTerms(Model model) => List.generate(model.terms.length, (i) => i);
Fit fitSubset(Design d, List<int> terms, double tolerance) =>
    Fit(d.subsetMatrix(terms), d.response, d.weights, tolerance);
List<int> removeTerm(List<int> terms, int index) =>
    terms.where((i) => i != index).toList();
List<Anova> marginalTests(Design d, Fit f, List<int> terms, double tolerance) {
  final out = <Anova>[];
  for (final i in d.model.removable(terms)) {
    final reduced = fitSubset(d, removeTerm(terms, i), tolerance),
        df = f.rank - reduced.rank,
        ss = reduced.rss - f.rss;
    var stat = double.nan, p = double.nan;
    if (df > 0) {
      stat = (ss / df) / (f.rss / (f.n - f.rank));
      p = fP(stat, df, f.n - f.rank);
    }
    out.add(
      Anova(
        index: i,
        name: d.model.terms[i].name,
        df: df,
        ss: ss,
        rss: reduced.rss,
        f: stat,
        p: p,
      ),
    );
  }
  return out;
}

List<Anova> sequentialANOVA(Design d, Fit f) {
  final out = <Anova>[];
  for (var i = 0; i < d.model.terms.length; i++) {
    var ss = 0.0, df = 0;
    for (var k = 0; k < f.rank; k++) {
      final j = f.accepted[k];
      if (d.columns[j].term == i) {
        ss += f.effects[k] * f.effects[k];
        df++;
      }
    }
    if (df == 0) continue;
    final ms = ss / df, stat = ms / (f.rss / (f.n - f.rank));
    out.add(
      Anova(
        name: d.model.terms[i].name,
        df: df,
        ss: ss,
        ms: ms,
        f: stat,
        p: fP(stat, df, f.n - f.rank),
      ),
    );
  }
  return out;
}

List<VIFResult> varianceInflation(Design d, Fit f, Statistics s, Params p) {
  final out = <VIFResult>[];
  for (final column in f.accepted.skip(1)) {
    final response = [for (final row in f.matrix) row[column]],
        x = [
          for (final row in f.matrix)
            [
              for (final j in f.accepted)
                if (j != column) row[j],
            ],
        ],
        aux = Fit(x, response, f.weights, p.tolerance);
    var sum = 0.0;
    for (var i = 0; i < f.n; i++) {
      sum += f.weights[i] * response[i];
    }
    final mean = sum / s.weightSum;
    var tss = 0.0;
    for (var i = 0; i < f.n; i++) {
      final v = response[i];
      tss += f.weights[i] * (v - mean) * (v - mean);
    }
    final r2 = 1 - aux.rss / tss, vif = 1 / (1 - r2);
    out.add(VIFResult(d.columns[column].name, vif, vif > p.vif));
  }
  return out;
}

ResetResult resetTest(Fit f, double tolerance) {
  final x = [
        for (var i = 0; i < f.n; i++)
          [
            for (final j in f.accepted) f.matrix[i][j],
            f.fitted[i] * f.fitted[i],
            f.fitted[i] * f.fitted[i] * f.fitted[i],
          ],
      ],
      aug = Fit(x, f.response, f.weights, tolerance),
      q = aug.rank - f.rank,
      df = f.n - aug.rank,
      stat = ((f.rss - aug.rss) / q) / (aug.rss / df);
  return ResetResult(stat, q, df, fP(stat, q, df));
}

(List<String>, PredictionCheck) predictionReport(
  int number,
  Design d,
  Fit f,
  Statistics s,
  DataFrame data,
) {
  final lines = <String>[], check = PredictionCheck();
  var squared = 0.0;
  for (var i = 0; i < data.rows.length; i++) {
    final row = data.rows[i], fields = ['$number', '${i + 1}'];
    if (!d.predictable(row)) {
      fields.addAll(List.filled(9, 'NA'));
      lines.add(fields.join(','));
      continue;
    }
    check.predicted++;
    final values = d.values(row);
    var predicted = 0.0;
    for (final j in f.accepted) {
      predicted += values[j] * f.beta[j];
    }
    var sum = 0.0;
    for (var k = 0; k < f.rank; k++) {
      var u = 0.0;
      for (var m = 0; m < f.rank; m++) {
        u += values[f.accepted[m]] * f.inverse[m][k];
      }
      sum += u * u;
    }
    final se = s.sigma * math.sqrt(sum),
        cw = s.critical * se,
        pw = s.critical * math.sqrt(s.sigma * s.sigma + se * se),
        lower = predicted - pw,
        upper = predicted + pw;
    fields.addAll(
      [predicted, se, predicted - cw, predicted + cw, lower, upper].map(four),
    );
    final actual = row[d.model.response]?.number;
    if (actual == null) {
      fields.addAll(['NA', 'NA', 'NA']);
    } else {
      check.actual++;
      final error = actual - predicted;
      squared += error * error;
      final covered = lower <= actual && actual <= upper;
      if (covered) check.covered++;
      fields.addAll([four(actual), four(error), covered ? 'yes' : 'no']);
    }
    lines.add(fields.join(','));
  }
  if (check.actual > 0) check.rmse = math.sqrt(squared / check.actual);
  return (lines, check);
}

List<String> dataSummary(DataFrame data) {
  final numeric = <String>[], rows = <List<String>>[];
  for (final c in data.columns) {
    if (data.categorical[c]!) continue;
    numeric.add(c);
    final values = [
          for (final row in data.rows)
            if (row[c]!.present) row[c]!.number!,
        ],
        n = values.length,
        mean = orderedSum(values) / n;
    var sum = 0.0, lo = values.first, hi = values.first;
    for (final v in values) {
      sum += (v - mean) * (v - mean);
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    rows.add([
      c,
      '$n',
      '${data.rows.length - n}',
      four(mean),
      four(math.sqrt(sum / (n - 1))),
      four(lo),
      four(hi),
    ]);
  }
  final lines = [
    'Data: ${data.rows.length} rows, ${data.columns.length} columns',
    '',
    'Numeric columns:',
    ...table(['column', 'n', 'missing', 'Mean', 'SD', 'Min', 'Max'], rows),
    '',
    'Categorical columns:',
  ];
  for (final c in data.columns) {
    if (!data.categorical[c]!) continue;
    final counts = <String, int>{};
    var present = 0;
    for (final row in data.rows) {
      final v = row[c]!;
      if (v.present) {
        present++;
        counts[v.label!] = (counts[v.label!] ?? 0) + 1;
      }
    }
    final levels = counts.keys.toList()..sort();
    lines.add(
      '$c: $present values, ${data.rows.length - present} missing, ${levels.length} levels: ${levels.map((label) => '$label ${counts[label]}').join(', ')}',
    );
  }
  lines.addAll(['', 'Correlations (pairwise complete observations):']);
  final correlations = <List<String>>[];
  for (final a in numeric) {
    final fields = [a];
    for (final b in numeric) {
      final pairs = <(double, double)>[];
      var sx = 0.0, sy = 0.0;
      for (final row in data.rows) {
        final x = row[a]!, y = row[b]!;
        if (x.present && y.present) {
          pairs.add((x.number!, y.number!));
          sx += x.number!;
          sy += y.number!;
        }
      }
      final mx = sx / pairs.length, my = sy / pairs.length;
      var cross = 0.0, xx = 0.0, yy = 0.0;
      for (final pair in pairs) {
        final x = pair.$1 - mx, y = pair.$2 - my;
        cross += x * y;
        xx += x * x;
        yy += y * y;
      }
      fields.add(four(cross / math.sqrt(xx * yy)));
    }
    correlations.add(fields);
  }
  lines.addAll([
    ...table(['column', ...numeric], correlations),
    '',
  ]);
  return lines;
}

(List<String>, List<String>, List<String>) coefficientTables(
  Report r,
  double confidence,
) {
  final ordinary = <List<String>>[],
      intervals = <List<String>>[],
      robust = <List<String>>[],
      marks = <String>[],
      robustMarks = <String>[];
  for (var j = 0; j < r.coefficients.length; j++) {
    final c = r.coefficients[j], name = r.design.columns[j].name;
    ordinary.add([
      name,
      four(c.estimate),
      four(c.se),
      four(c.t),
      probability(c.p),
    ]);
    intervals.add([name, four(c.lower), four(c.upper)]);
    robust.add([
      name,
      four(c.robustSE),
      four(c.robustT),
      probability(c.robustP),
    ]);
    marks.add(significance(c.p));
    robustMarks.add(significance(c.robustP));
  }
  return (
    table(
      ['term', 'Estimate', 'Std. Error', 't value', 'Pr(>|t|)'],
      ordinary,
      marks,
    ),
    [
      'Confidence intervals (level ${four(confidence)}, t ${four(r.stats.critical)}):',
      ...table(['term', 'Lower', 'Upper'], intervals),
    ],
    table(['term', 'Std. Error', 't value', 'Pr(>|t|)'], robust, robustMarks),
  );
}

(List<String>, List<String>) anovaTables(Report r) {
  final rows = [
        for (final t in r.anova)
          [
            t.name,
            '${t.df}',
            four(t.ss),
            four(t.ms),
            four(t.f),
            probability(t.p),
          ],
        [
          'Residuals',
          '${r.stats.df}',
          four(r.fit.rss),
          four(r.fit.rss / r.stats.df),
        ],
      ],
      marks = [for (final t in r.anova) significance(t.p), ''];
  return (
    table(
      ['term', 'Df', 'Sum Sq', 'Mean Sq', 'F value', 'Pr(>F)'],
      rows,
      marks,
    ),
    table(
      ['term', 'Df', 'Sum Sq', 'RSS', 'F value', 'Pr(>F)'],
      [
        for (final t in r.marginal)
          [
            t.name,
            '${t.df}',
            four(t.ss),
            four(t.rss),
            four(t.f),
            probability(t.p),
          ],
      ],
      [for (final t in r.marginal) significance(t.p)],
    ),
  );
}

List<String> diagnosticSummary(Report r, Params p) {
  final f = r.fit,
      d = r.diagnostic,
      design = r.design,
      dwLabel = d.dw < p.dw
          ? 'positive autocorrelation'
          : d.dw > 4 - p.dw
          ? 'negative autocorrelation'
          : 'no autocorrelation',
      bpLabel = d.bpP < p.bp ? 'heteroscedastic' : 'homoscedastic',
      jbLabel = d.jbP < p.normal ? 'non-normal' : 'normal',
      counts = {for (final flag in 'HOCF'.split('')) flag: 0};
  var outlier = 0, any = 0;
  final order = List.generate(f.n, (i) => i);
  for (var i = 0; i < f.n; i++) {
    final row = d.rows[i];
    if (row.studentized.abs() > d.rows[outlier].studentized.abs()) outlier = i;
    if (row.flags != '-') {
      any++;
      for (final flag in row.flags.split('')) {
        counts[flag] = counts[flag]! + 1;
      }
    }
  }
  final unadjusted = tP(d.rows[outlier].studentized, f.n - f.rank - 1),
      bonferroni = math.min(1.0, f.n * unadjusted),
      reset = r.reset;
  order.sort((i, j) {
    final result = d.rows[j].cooks.compareTo(d.rows[i].cooks);
    return result != 0 ? result : i.compareTo(j);
  });
  final lines = [
    'Diagnostics:',
    'Durbin-Watson: ${four(d.dw)} ($dwLabel)',
    'Breusch-Pagan: ${four(d.bp)} on ${d.bpDF} DF, p-value: ${probability(d.bpP)} ($bpLabel)',
    'Jarque-Bera: ${four(d.jb)} on 2 DF, p-value: ${probability(d.jbP)}, skewness ${four(d.skewness)}, kurtosis ${four(d.kurtosis)} ($jbLabel)',
    'RESET (powers 2 and 3): F ${four(reset.f)} on ${reset.addedDF} and ${reset.residualDF} DF, p-value: ${probability(reset.p)}',
    'Outlier test: row ${design.rowNumbers[outlier]}, studentized ${four(d.rows[outlier].studentized)}, unadjusted p-value: ${probability(unadjusted)}, Bonferroni p-value: ${probability(bonferroni)}',
    'Flagged rows: leverage ${counts['H']}, outlier ${counts['O']}, cooks ${counts['C']}, dffits ${counts['F']}, any $any',
    "Largest Cook's distances:",
  ];
  for (final i in order.take(3)) {
    final row = d.rows[i];
    lines.add(
      'row ${design.rowNumbers[i]}: cooks_d ${four(row.cooks)}, leverage ${four(f.leverage[i])}, studentized ${four(row.studentized)}, flags ${row.flags}',
    );
  }
  lines.add('Largest absolute DFBETAS:');
  final rows = <List<String>>[];
  for (var k = 0; k < f.rank; k++) {
    var best = 0;
    for (var i = 1; i < f.n; i++) {
      if (d.rows[i].dfbetas[k].abs() > d.rows[best].dfbetas[k].abs()) best = i;
    }
    rows.add([
      design.columns[f.accepted[k]].name,
      '${design.rowNumbers[best]}',
      four(d.rows[best].dfbetas[k]),
    ]);
  }
  lines.addAll(table(['column', 'row', 'DFBETAS'], rows));
  return lines;
}

List<String> modelSummary(Report r, int total, Params p) {
  final d = r.design,
      f = r.fit,
      s = r.stats,
      aliases = [for (final j in f.aliases) d.columns[j].name],
      aliasText = aliases.isEmpty ? 'none' : aliases.join(', '),
      terms = [for (final t in d.model.terms) t.name],
      weight = d.model.weight.isEmpty ? 'none' : d.model.weight,
      q = s.quantiles;
  final (coef, intervals, robust) = coefficientTables(r, p.confidence);
  final (seq, marginal) = anovaTables(r);
  final lines = [
    'Model ${r.number}: ${d.model.original}',
    'Terms: ${terms.join(', ')}',
    'Weights: $weight',
    'Observations: ${f.n} used, ${total - f.n} dropped',
    'Columns: ${f.p}, rank ${f.rank}, aliased: $aliasText',
    '',
    'Residuals: Min ${four(q[0])}, 1Q ${four(q[1])}, Median ${four(q[2])}, 3Q ${four(q[3])}, Max ${four(q[4])}',
    '',
    'Coefficients:',
    ...coef,
    '---',
    "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1",
    '',
    'Residual standard error: ${four(s.sigma)} on ${s.df} degrees of freedom',
    'Multiple R-squared: ${four(s.r2)}, Adjusted R-squared: ${four(s.adjusted)}',
    'F-statistic: ${four(s.f)} on ${f.rank - 1} and ${s.df} DF, p-value: ${probability(s.p)}',
    'Log-likelihood: ${four(s.ll)}, AIC: ${four(s.aic)}, BIC: ${four(s.bic)}',
    'PRESS: ${four(s.press)}, Predicted R-squared: ${four(s.predicted)}',
    '',
    ...intervals,
    '',
    'Robust standard errors (HC3):',
    ...robust,
    '',
    'Analysis of variance (sequential):',
    ...seq,
    '',
    'Marginal F tests (drop one term):',
    ...marginal,
    '',
    'Variance inflation factors:',
    ...table(
      ['column', 'VIF'],
      [
        for (final v in r.vif) [v.name, four(v.value)],
      ],
      [for (final v in r.vif) v.high ? 'high' : ''],
    ),
    '',
    ...diagnosticSummary(r, p),
  ];
  return lines;
}

List<String> summaryReport(DataFrame data, List<Report> reports, Params p) {
  final lines = dataSummary(data);
  for (var i = 0; i < reports.length; i++) {
    if (i > 0) lines.add('');
    lines.addAll(modelSummary(reports[i], data.rows.length, p));
  }
  lines.addAll([
    '',
    'Model comparison:',
    ...table(
      [
        'model',
        'n',
        'rank',
        'sigma',
        'R-squared',
        'Adj. R-squared',
        'Pred. R-squared',
        'AIC',
        'BIC',
      ],
      [
        for (final r in reports)
          [
            '${r.number}',
            '${r.fit.n}',
            '${r.fit.rank}',
            four(r.stats.sigma),
            four(r.stats.r2),
            four(r.stats.adjusted),
            four(r.stats.predicted),
            four(r.stats.aic),
            four(r.stats.bic),
          ],
      ],
    ),
    '',
    'Prediction check:',
  ]);
  for (final r in reports) {
    final c = r.check;
    lines.add(
      'model ${r.number}: ${c.predicted} predicted, ${c.actual} with actual values, RMSE ${four(c.rmse)}, inside prediction interval ${c.covered}',
    );
  }
  return lines;
}

List<String> diagnosticsCSV(List<Report> reports) => [
  'model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags',
  for (final r in reports)
    for (var i = 0; i < r.fit.n; i++)
      [
        '${r.number}',
        '${r.design.rowNumbers[i]}',
        four(r.fit.fitted[i]),
        four(r.fit.residual[i]),
        four(r.fit.leverage[i]),
        four(r.diagnostic.rows[i].studentized),
        four(r.diagnostic.rows[i].cooks),
        four(r.diagnostic.rows[i].dffits),
        r.diagnostic.rows[i].flags,
      ].join(','),
];
List<String> backwardSelection(Report r, Params p) {
  final d = r.design,
      lines = [
        'Backward elimination (model 1, alpha ${four(p.alpha)}, rows ${d.rows.length})',
      ];
  var terms = allTerms(d.model), step = 1, f = r.fit;
  while (true) {
    final (_, aic, _) = informationCriteria(f);
    final df = f.n - f.rank;
    lines.add(
      'Step $step: ${d.model.format(terms)} (RSS ${four(f.rss)}, df $df, AIC ${four(aic)})',
    );
    if (terms.isEmpty) {
      lines.add('  stop: no removable terms');
      break;
    }
    final tests = marginalTests(d, f, terms, p.tolerance);
    var best = 0;
    for (var i = 0; i < tests.length; i++) {
      final t = tests[i];
      lines.add(
        '  - ${t.name}: F ${four(t.f)} on ${t.df} and $df DF, p-value ${probability(t.p)}',
      );
      if (t.p > tests[best].p) best = i;
    }
    final largest = tests[best];
    if (largest.p <= p.alpha) {
      lines.add(
        '  stop: largest p-value ${probability(largest.p)} is not above ${four(p.alpha)}',
      );
      break;
    }
    lines.add('  remove ${largest.name}');
    terms = removeTerm(terms, largest.index);
    f = fitSubset(d, terms, p.tolerance);
    step++;
  }
  lines.add('Final model: ${d.model.format(terms)}');
  return lines;
}

List<int> addTerm(List<int> terms, int index) => [...terms, index]..sort();
List<String> forwardSelection(Report r, Params p) {
  final d = r.design,
      lines = ['Forward selection by AIC (model 1, rows ${d.rows.length})'];
  var terms = <int>[], step = 1;
  while (true) {
    final f = fitSubset(d, terms, p.tolerance);
    final (_, aic, _) = informationCriteria(f);
    lines.add('Step $step: ${d.model.format(terms)} (AIC ${four(aic)})');
    final candidates = d.model.candidates(terms);
    if (candidates.isEmpty) {
      lines.add('  stop: no candidate terms remain');
      break;
    }
    var best = -1, bestAIC = double.infinity;
    for (final i in candidates) {
      final candidate = fitSubset(d, addTerm(terms, i), p.tolerance);
      final (_, value, _) = informationCriteria(candidate);
      lines.add('  + ${d.model.terms[i].name}: AIC ${four(value)}');
      if (value < bestAIC) {
        best = i;
        bestAIC = value;
      }
    }
    if (bestAIC >= aic) {
      lines.add('  stop: no candidate lowers the AIC');
      break;
    }
    lines.add('  add ${d.model.terms[best].name}');
    terms = addTerm(terms, best);
    step++;
  }
  lines.add('Final model: ${d.model.format(terms)}');
  return lines;
}

class SubsetResult {
  final double bic, aic;
  final int mask, rank;
  final List<int> terms;
  SubsetResult(this.bic, this.aic, this.mask, this.rank, this.terms);
}

List<String> bestSubsets(Report r, Params p) {
  final d = r.design, subsets = <SubsetResult>[];
  for (var mask = 0; mask < 1 << d.model.terms.length; mask++) {
    final terms = [
      for (var j = 0; j < d.model.terms.length; j++)
        if ((mask & (1 << j)) != 0) j,
    ];
    if (!d.model.hierarchical(terms)) continue;
    final f = fitSubset(d, terms, p.tolerance);
    final (_, aic, bic) = informationCriteria(f);
    subsets.add(SubsetResult(bic, aic, mask, f.rank, terms));
  }
  subsets.sort((a, b) {
    final result = a.bic.compareTo(b.bic);
    return result != 0 ? result : a.mask.compareTo(b.mask);
  });
  return [
    'Best subsets by BIC (model 1, rows ${d.rows.length}, subsets ${subsets.length})',
    for (var i = 0; i < math.min(p.best, subsets.length); i++)
      '${i + 1}. BIC ${four(subsets[i].bic)}, AIC ${four(subsets[i].aic)}, rank ${subsets[i].rank}: ${d.model.format(subsets[i].terms)}',
  ];
}

List<String> selectionReport(Report r, Params p) => [
  ...backwardSelection(r, p),
  '',
  ...forwardSelection(r, p),
  '',
  ...bestSubsets(r, p),
];
List<List<int>> plotGrid(
  List<double> horizontal,
  List<double> vertical,
  double lo,
  double hi,
  Params p,
) {
  final grid = List.generate(p.height, (_) => List.filled(p.width, 0));
  for (var i = 0; i < horizontal.length; i++) {
    final c = math.min(
          ((horizontal[i] - lo) / (hi - lo) * p.width).floor(),
          p.width - 1,
        ),
        r = ((p.limit - vertical[i]) / (2 * p.limit) * p.height)
            .floor()
            .clamp(0, p.height - 1)
            .toInt();
    grid[r][c]++;
  }
  return grid;
}

List<String> plotFrame(List<List<int>> grid) {
  final border = '+${'-' * grid.first.length}+';
  return [
    border,
    for (var r = 0; r < grid.length; r++)
      '|${[for (final n in grid[r]) n >= 10
            ? '*'
            : n > 0
            ? '$n'
            : r == grid.length ~/ 2
            ? '-'
            : '.'].join()}|',
    border,
  ];
}

(double, double) minMax(List<double> values) {
  var lo = values.first, hi = values.first;
  for (final v in values.skip(1)) {
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  return (lo, hi);
}

List<String> residualPlot(Report r, Params p) {
  final f = r.fit,
      vertical = [for (final d in r.diagnostic.rows) d.studentized];
  var above = 0, below = 0, outside = 0;
  for (final v in vertical) {
    if (v > 2) above++;
    if (v < -2) below++;
    if (v.abs() > p.limit) outside++;
  }
  final (lo, hi) = minMax(f.fitted);
  final grid = plotGrid(f.fitted, vertical, lo, hi, p),
      lines = [
        'Model ${r.number}: studentized residuals vs fitted values',
        'fitted ${four(lo)} to ${four(hi)}, studentized ${four(-p.limit)} to ${four(p.limit)}',
        ...plotFrame(grid),
        'points: ${f.n}, above +2: $above, below -2: $below, outside range: $outside',
        'Histogram of studentized residuals:',
      ],
      counts = [for (final row in grid) row.fold(0, (a, b) => a + b)],
      maximum = counts.reduce(math.max);
  for (var i = 0; i < counts.length; i++) {
    final n = counts[i],
        lower = p.limit - 2 * p.limit * (i + 1) / p.height,
        upper = p.limit - 2 * p.limit * i / p.height,
        length = (n * 40 + maximum - 1) ~/ maximum;
    lines.add(
      '${four(lower)} to ${four(upper)}: $n${length > 0 ? ' ${'#' * length}' : ''}',
    );
  }
  final (_, leverageHi) = minMax(f.leverage);
  lines.addAll([
    'Model ${r.number}: studentized residuals vs leverage',
    'leverage 0.0000 to ${four(leverageHi)}, studentized ${four(-p.limit)} to ${four(p.limit)}',
    ...plotFrame(plotGrid(f.leverage, vertical, 0, leverageHi, p)),
  ]);
  return lines;
}

void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
void main() {
  final data = readCSV('input/data.csv'),
      predict = readCSV('input/predict.csv', data.categorical),
      p = readParams(),
      models = readLines('input/model.txt'),
      reports = [
        for (var i = 0; i < models.length; i++)
          Report(i + 1, Design(Model(models[i]), data), p, predict),
      ];
  Directory('output').createSync(recursive: true);
  writeLines('summary.txt', summaryReport(data, reports, p));
  writeLines('diagnostics.csv', diagnosticsCSV(reports));
  writeLines('selection.txt', selectionReport(reports.first, p));
  writeLines('predictions.csv', [
    'model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered',
    for (final r in reports) ...r.predictions,
  ]);
  writeLines('residual_plot.txt', [
    for (var i = 0; i < reports.length; i++) ...[
      if (i > 0) '',
      ...residualPlot(reports[i], p),
    ],
  ]);
}
