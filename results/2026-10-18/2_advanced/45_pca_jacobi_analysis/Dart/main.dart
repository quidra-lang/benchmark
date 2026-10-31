import 'dart:io';
import 'dart:math' as math;

part 'dataset.dart';
part 'matrix.dart';
part 'eigen.dart';
part 'pca.dart';
part 'plot.dart';

const criteria = ['kaiser', 'broken_stick', 'parallel', 'cumulative'];
String realText(double value, [int digits = 4]) {
  final text = value.toStringAsFixed(digits);
  return text.startsWith('-') && double.parse(text) == 0
      ? text.substring(1)
      : text;
}

String real(double value) => realText(value);
List<String> reals(Iterable<double> values) => values.map(real).toList();
List<String> componentNames(String prefix, int count) => [
  for (var k = 1; k <= count; k++) '$prefix$k',
];
bool hasMissing(List<double?> row) => row.contains(null);
int largestIndex(List<double> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[best]) best = i;
  }
  return best;
}

int smallestIndex(List<double> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] < values[best]) best = i;
  }
  return best;
}

List<int> topIndices(List<double> values, int count) {
  final order = List.generate(values.length, (i) => i)
    ..sort((i, j) {
      final result = values[j].compareTo(values[i]);
      return result != 0 ? result : i.compareTo(j);
    });
  return order.take(count).toList();
}

double congruence(List<double> a, List<double> b) =>
    dot(a, b) / math.sqrt(dot(a, a) * dot(b, b));
List<double> ratios(List<double> values) {
  final total = sum(values);
  return [for (final v in values) v / total];
}

List<double> cumulativeRatios(List<double> values) {
  final out = <double>[];
  var running = 0.0;
  for (final v in values) {
    running += v;
    out.add(running);
  }
  return out;
}

class VariableSummary {
  final int observed, missing;
  final double mean, sd, minimum, maximum;
  VariableSummary(
    this.observed,
    this.missing,
    this.mean,
    this.sd,
    this.minimum,
    this.maximum,
  );
}

class AnalysisData {
  final ids = <String>[], values = <List<double>>[];
  AnalysisData(Table table, String strategy, List<double> means) {
    for (var i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      if (strategy == 'listwise' && hasMissing(row)) continue;
      ids.add(table.ids[i]);
      values.add([for (var j = 0; j < row.length; j++) row[j] ?? means[j]]);
    }
  }
}

class Decomposition {
  final AnalysisData data;
  late final List<double> means, deviations, scales;
  late final List<List<double>> covariance, correlation, matrix;
  late final EigenSystem eigen;
  Decomposition(this.data, String scaling) {
    means = columnMeans(data.values);
    covariance = covarianceMatrix(data.values, means);
    deviations = standardDeviations(covariance);
    correlation = correlationMatrix(covariance, deviations);
    matrix = scaling == 'correlation' ? correlation : covariance;
    scales = scaling == 'correlation'
        ? deviations
        : List.filled(means.length, 1.0);
    eigen = jacobi(matrix);
  }
}

class Adequacy {
  final List<double> msa;
  final double kmo, determinant, bartlett;
  final int df;
  Adequacy(this.msa, this.kmo, this.determinant, this.bartlett, this.df);
}

Adequacy samplingAdequacy(List<List<double>> correlation, int rows) {
  final p = correlation.length;
  final (inverse, det) = gaussJordan(correlation);
  final msa = List.filled(p, 0.0),
      rr = List.filled(p, 0.0),
      pp = List.filled(p, 0.0);
  for (var j = 0; j < p; j++) {
    for (var k = 0; k < p; k++) {
      if (j == k) continue;
      final r = correlation[j][k],
          pr = -inverse[j][k] / math.sqrt(inverse[j][j] * inverse[k][k]);
      rr[j] += r * r;
      pp[j] += pr * pr;
    }
    msa[j] = rr[j] / (rr[j] + pp[j]);
  }
  final totalR = sum(rr),
      totalP = sum(pp),
      bartlett = -(rows - 1 - (2 * p + 5) / 6) * math.log(det);
  return Adequacy(
    msa,
    totalR / (totalR + totalP),
    det,
    bartlett,
    p * (p - 1) ~/ 2,
  );
}

List<double> parallelAnalysis(int n, int p, int iterations, int seed) {
  final totals = List.filled(p, 0.0);
  var state = seed;
  for (var iteration = 0; iteration < iterations; iteration++) {
    final values = zeros(n, p);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < p; j++) {
        state = 48271 * state % 2147483647;
        values[i][j] = state / 2147483647;
      }
    }
    final cov = covarianceMatrix(values, columnMeans(values)),
        corr = correlationMatrix(cov, standardDeviations(cov)),
        r = ratios(jacobi(corr).values);
    for (var k = 0; k < p; k++) {
      totals[k] += r[k];
    }
  }
  return [for (final value in totals) value / iterations];
}

int firstCrossing(List<double> ratios, List<double> thresholds) {
  for (var k = 0; k < ratios.length; k++) {
    if (ratios[k] <= thresholds[k]) return k;
  }
  return ratios.length;
}

class VarianceTable {
  late final double total, average;
  late final List<double> ratiosList, cumulative, broken, parallel, errors;
  late final List<bool> separated;
  final retention = <String, int>{};
  VarianceTable(List<double> values, int rows, this.parallel, double target) {
    final p = values.length;
    total = sum(values);
    average = total / p;
    ratiosList = ratios(values);
    cumulative = cumulativeRatios(ratiosList);
    broken = List.filled(p, 0.0);
    errors = List.filled(p, 0.0);
    separated = List.filled(p, true);
    retention['kaiser'] = 0;
    for (var k = 0; k < p; k++) {
      for (var i = k + 1; i <= p; i++) {
        broken[k] += 1 / i;
      }
      broken[k] /= p;
      errors[k] = values[k] * math.sqrt(2 / rows);
      for (final h in [k - 1, k + 1]) {
        if (h >= 0 && h < p && !((values[k] - values[h]).abs() > errors[k]))
          separated[k] = false;
      }
      if (values[k] > average) retention['kaiser'] = retention['kaiser']! + 1;
    }
    retention['broken_stick'] = firstCrossing(ratiosList, broken);
    retention['parallel'] = firstCrossing(ratiosList, parallel);
    retention['cumulative'] = p;
    for (var k = 0; k < p; k++) {
      if (cumulative[k] >= target) {
        retention['cumulative'] = k + 1;
        break;
      }
    }
  }
}

double varimaxCriterion(List<List<double>> g) {
  final p = g.length;
  var total = 0.0;
  for (var k = 0; k < g.first.length; k++) {
    var q4 = 0.0, q2 = 0.0;
    for (final row in g) {
      q4 += (row[k] * row[k]) * (row[k] * row[k]);
      q2 += row[k] * row[k];
    }
    total += q4 / p - (q2 / p) * (q2 / p);
  }
  return total;
}

void rotatePair(List<List<double>> g, int a, int b) {
  final p = g.length;
  var sa = 0.0, sb = 0.0, sc = 0.0, sd = 0.0;
  for (final row in g) {
    final phi = row[a] * row[a] - row[b] * row[b], psi = 2 * row[a] * row[b];
    sa += phi;
    sb += psi;
    sc += phi * phi - psi * psi;
    sd += 2 * phi * psi;
  }
  final num = sd - 2 * sa * sb / p,
      den = sc - (sa * sa - sb * sb) / p,
      omega = math.sqrt(num * num + den * den);
  if (omega == 0) return;
  final cos4 = den / omega,
      sin4 = num / omega,
      cos2 = math.sqrt((1 + cos4) / 2),
      sin2 = cos2 == 0 ? 1.0 : sin4 / (2 * cos2),
      cos1 = math.sqrt((1 + cos2) / 2),
      sin1 = sin2 / (2 * cos1);
  for (final row in g) {
    final x = row[a], y = row[b];
    row[a] = cos1 * x + sin1 * y;
    row[b] = -sin1 * x + cos1 * y;
  }
}

class Varimax {
  final criteria = <double>[],
      squares = <double>[],
      congruences = <double>[],
      columns = <List<double>>[],
      closest = <int>[];
  Varimax(List<List<double>> loadings, int components, int cycles) {
    final p = loadings.length,
        etas = [
          for (final row in loadings)
            math.sqrt(
              sum([for (var k = 0; k < components; k++) row[k] * row[k]]),
            ),
        ],
        g = [
          for (var j = 0; j < p; j++)
            [for (var k = 0; k < components; k++) loadings[j][k] / etas[j]],
        ];
    criteria.add(varimaxCriterion(g));
    for (var cycle = 0; cycle < cycles; cycle++) {
      for (var a = 0; a < components - 1; a++) {
        for (var b = a + 1; b < components; b++) {
          rotatePair(g, a, b);
        }
      }
      criteria.add(varimaxCriterion(g));
    }
    final raw = [
          for (var k = 0; k < components; k++)
            orient([for (var j = 0; j < p; j++) g[j][k] * etas[j]]),
        ],
        ss = [for (final v in raw) dot(v, v)];
    for (final k in topIndices(ss, components)) {
      columns.add(raw[k]);
      squares.add(ss[k]);
    }
    for (final v in columns) {
      final matches = [
            for (var k = 0; k < components; k++)
              congruence(v, column(loadings, k)).abs(),
          ],
          best = largestIndex(matches);
      closest.add(best);
      congruences.add(matches[best]);
    }
  }
}

class Observation {
  final String id, flag;
  final List<double> z, scores, residualsList;
  final double t2, spe;
  Observation(
    this.id,
    this.z,
    this.scores,
    this.residualsList,
    this.t2,
    this.spe,
    this.flag,
  );
}

class Sensitivity {
  final String strategy, scaling;
  final int rows, sweeps;
  final List<double> eigenvalues, agreement;
  final double cumulative;
  Sensitivity(
    this.strategy,
    this.scaling,
    this.rows,
    this.sweeps,
    this.eigenvalues,
    this.agreement,
    this.cumulative,
  );
}

String flagText(double t2, double spe, Settings settings) {
  var flag = '';
  if (t2 > settings.t2Limit) flag += 'T';
  if (spe > settings.speLimit) flag += 'Q';
  return flag.isEmpty ? '-' : flag;
}

void drawAxes(List<List<String>> grid, Cell center) {
  for (var c = 0; c < grid[center.$1].length; c++) {
    grid[center.$1][c] = '-';
  }
  for (final row in grid) {
    row[center.$2] = '|';
  }
  grid[center.$1][center.$2] = '+';
}

void markCells(
  List<List<String>> grid,
  Iterable<Cell> cells,
  String character,
) {
  for (final (row, col) in cells) {
    grid[row][col] = character;
  }
}

void drawPoints(List<List<String>> grid, Iterable<Cell> cells) {
  final counts = <Cell, int>{};
  for (final c in cells) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  for (final entry in counts.entries) {
    final (row, col) = entry.key;
    final n = entry.value;
    grid[row][col] = n == 1
        ? '.'
        : n <= 3
        ? 'o'
        : '@';
  }
}

bool insideCircle(int row, int col, Cell center, int radius) {
  final x = col - center.$2, y = 2 * (row - center.$1);
  return x * x + y * y <= radius * radius;
}

class PcaReport {
  final Dataset dataset;
  late final List<String> names, ids;
  final incomplete = <String>[],
      summaries = <VariableSummary>[],
      observedMeans = <double>[],
      strongest = <(int, int)>[],
      observations = <Observation>[],
      projections = <Observation>[],
      sensitivity = <Sensitivity>[];
  late final int size, rows, components;
  late final Decomposition fit;
  late final Adequacy adequacy;
  late final List<PowerComponent> power;
  late final VarianceTable variance;
  late final List<List<double>> loadings, circle;
  late final List<double> communalities;
  late final Varimax varimax;
  PcaReport(this.dataset) {
    names = dataset.data.names;
    size = names.length;
    final p = size, s = dataset.settings;
    for (var j = 0; j < p; j++) {
      final values = [
            for (final row in dataset.data.rows)
              if (row[j] != null) row[j]!,
          ],
          mean = sum(values) / values.length;
      var squares = 0.0, lo = values.first, hi = values.first;
      for (final x in values) {
        squares += (x - mean) * (x - mean);
        lo = math.min(lo, x);
        hi = math.max(hi, x);
      }
      summaries.add(
        VariableSummary(
          values.length,
          dataset.data.rows.length - values.length,
          mean,
          math.sqrt(squares / (values.length - 1)),
          lo,
          hi,
        ),
      );
      observedMeans.add(mean);
    }
    for (var i = 0; i < dataset.data.rows.length; i++) {
      if (hasMissing(dataset.data.rows[i])) incomplete.add(dataset.data.ids[i]);
    }
    final main = AnalysisData(dataset.data, s.missing, observedMeans);
    fit = Decomposition(main, s.scaling);
    ids = main.ids;
    rows = ids.length;
    adequacy = samplingAdequacy(fit.correlation, rows);
    power = powerIteration(fit.matrix, fit.eigen.vectors);
    final parallel = parallelAnalysis(rows, p, s.parallel, s.seed);
    variance = VarianceTable(fit.eigen.values, rows, parallel, s.target);
    components = variance.retention.containsKey(s.components)
        ? math.max(1, variance.retention[s.components]!)
        : int.parse(s.components);
    loadings = zeros(p, p);
    circle = zeros(p, 2);
    communalities = List.filled(p, 0.0);
    for (var j = 0; j < p; j++) {
      for (var k = 0; k < p; k++) {
        loadings[j][k] =
            fit.eigen.vectors[k][j] * math.sqrt(fit.eigen.values[k]);
      }
      var sq = 0.0;
      for (var k = 0; k < components; k++) {
        sq += loadings[j][k] * loadings[j][k];
      }
      communalities[j] = sq / fit.matrix[j][j];
      for (var k = 0; k < 2; k++) {
        circle[j][k] = loadings[j][k] / math.sqrt(fit.matrix[j][j]);
      }
    }
    final pairs = <(int, int)>[], strength = <double>[];
    for (var j = 0; j < p; j++) {
      for (var k = j + 1; k < p; k++) {
        pairs.add((j, k));
        strength.add(fit.correlation[j][k].abs());
      }
    }
    for (final i in topIndices(strength, s.top)) {
      strongest.add(pairs[i]);
    }
    varimax = Varimax(loadings, components, s.cycles);
    for (var i = 0; i < main.values.length; i++) {
      observations.add(observation(main.ids[i], main.values[i]));
    }
    for (var i = 0; i < dataset.supplementary.rows.length; i++) {
      projections.add(
        observation(
          dataset.supplementary.ids[i],
          dataset.supplementary.rows[i],
        ),
      );
    }
    for (final strategy in ['listwise', 'mean']) {
      for (final scaling in ['covariance', 'correlation']) {
        final alternate = Decomposition(
              AnalysisData(dataset.data, strategy, observedMeans),
              scaling,
            ),
            agreement = [
              for (var k = 0; k < components; k++)
                dot(alternate.eigen.vectors[k], fit.eigen.vectors[k]).abs(),
            ];
        sensitivity.add(
          Sensitivity(
            strategy,
            scaling,
            alternate.data.ids.length,
            alternate.eigen.sweeps,
            alternate.eigen.values.take(components).toList(),
            agreement,
            cumulativeRatios(ratios(alternate.eigen.values))[components - 1],
          ),
        );
      }
    }
  }
  Observation observation(String id, List<double?> values) {
    final z = standardize(values, fit.means, fit.scales),
        scores = componentScores(z, fit.eigen.vectors),
        res = residuals(z, scores, fit.eigen.vectors, components),
        t2 = hotelling(scores, fit.eigen.values, components),
        spe = dot(res, res);
    return Observation(
      id,
      z,
      scores,
      res,
      t2,
      spe,
      flagText(t2, spe, dataset.settings),
    );
  }

  List<String> eigenFile() {
    final s = dataset.settings,
        incompleteText = incomplete.isEmpty
            ? '0 -'
            : '${incomplete.length} ${incomplete.join(' ')}',
        sections = <List<String>>[
          [
            'pca rows ${dataset.data.rows.length} used $rows variables $size missing ${s.missing} scaling ${s.scaling}',
            'incomplete $incompleteText',
          ],
        ];
    var lines = ['variable observed missing mean sd min max msa'];
    for (var j = 0; j < size; j++) {
      final v = summaries[j];
      lines.add(
        '${names[j]} ${v.observed} ${v.missing} ${reals([v.mean, v.sd, v.minimum, v.maximum, adequacy.msa[j]]).join(' ')}',
      );
    }
    final a = adequacy;
    lines.add(
      'adequacy kmo ${real(a.kmo)} determinant ${realText(a.determinant, 6)} bartlett ${real(a.bartlett)} df ${a.df}',
    );
    sections.add(lines);
    lines = [
      'matrix ${s.scaling}',
      for (var j = 0; j < size; j++)
        '${names[j]} ${reals(fit.matrix[j]).join(' ')}',
      'strongest ${[for (final (j, k) in strongest) '${names[j]}:${names[k]}:${real(fit.correlation[j][k])}'].join(' ')}',
    ];
    sections.add(lines);
    final v = variance;
    lines = [
      'jacobi sweeps ${fit.eigen.sweeps}',
      'eigenvalues total ${real(v.total)} average ${real(v.average)}',
      'k eigenvalue ratio cumulative broken_stick parallel se separated',
    ];
    for (var k = 0; k < size; k++) {
      lines.add(
        '${k + 1} ${reals([fit.eigen.values[k], v.ratiosList[k], v.cumulative[k], v.broken[k], v.parallel[k], v.errors[k]]).join(' ')} ${v.separated[k] ? 'yes' : 'no'}',
      );
    }
    lines.addAll([
      'retention ${[for (final name in criteria) '$name ${v.retention[name]}'].join(' ')} target ${real(s.target)}',
      'components $components rule ${s.components}',
    ]);
    sections.add(lines);
    lines = [
      'eigenvectors',
      'variable ${componentNames('pc', size).join(' ')}',
      for (var j = 0; j < size; j++)
        '${names[j]} ${reals(fit.eigen.vectors.map((v) => v[j])).join(' ')}',
    ];
    sections.add(lines);
    lines = [
      'power_iteration iterations 1000',
      'k jacobi power agree_at match',
    ];
    var matches = 0;
    for (var k = 0; k < size; k++) {
      final p = power[k],
          match =
              (p.value - fit.eigen.values[k]).abs() <=
                  1e-8 * fit.eigen.values[0] &&
              maxDifference(p.vector, fit.eigen.vectors[k]) <= 0.000001;
      if (match) matches++;
      lines.add(
        '${k + 1} ${real(fit.eigen.values[k])} ${real(p.value)} ${p.agreement > 0 ? p.agreement : '-'} ${match ? 'yes' : 'no'}',
      );
    }
    lines.add('cross_check $matches/$size');
    sections.add(lines);
    lines = ['scores', 'component sd min min_id max max_id contributors'];
    for (var k = 0; k < components; k++) {
      final scores = [for (final o in observations) o.scores[k]],
          contributions = [
            for (final x in scores) x * x / ((rows - 1) * fit.eigen.values[k]),
          ],
          low = smallestIndex(scores),
          high = largestIndex(scores),
          squares = dot(scores, scores);
      final fields = [
        'pc${k + 1}',
        real(math.sqrt(squares / (rows - 1))),
        real(scores[low]),
        ids[low],
        real(scores[high]),
        ids[high],
        for (final i in topIndices(contributions, s.top))
          '${ids[i]}:${real(contributions[i])}',
      ];
      lines.add(fields.join(' '));
    }
    sections.add(lines);
    lines = [
      'varimax components $components cycles ${s.cycles}',
      for (var c = 0; c < varimax.criteria.length; c++)
        'cycle $c criterion ${realText(varimax.criteria[c], 6)}',
      for (var k = 0; k < components; k++)
        'rc${k + 1} ss ${real(varimax.squares[k])} ratio ${real(varimax.squares[k] / variance.total)} closest pc${varimax.closest[k] + 1} congruence ${real(varimax.congruences[k])}',
    ];
    sections.add(lines);
    lines = [
      'sensitivity',
      'missing scaling rows sweeps eigenvalues cumulative congruence',
      for (final v in sensitivity)
        '${v.strategy} ${v.scaling} ${v.rows} ${v.sweeps} ${reals(v.eigenvalues).join(' ')} ${real(v.cumulative)} ${reals(v.agreement).join(' ')}',
    ];
    sections.add(lines);
    return joinSections(sections);
  }

  List<String> loadingsFile() {
    final header = [
      'variable',
      ...componentNames('pc', components),
      'communality',
      ...componentNames('rc', components),
    ];
    return [
      header.join(','),
      for (var j = 0; j < size; j++)
        [
          names[j],
          ...reals([
            ...loadings[j].take(components),
            communalities[j],
            for (final v in varimax.columns) v[j],
          ]),
        ].join(','),
    ];
  }

  List<String> scoresFile() => [
    ['id', 'set', ...componentNames('pc', components)].join(','),
    for (final o in observations)
      [o.id, 'data', ...reals(o.scores.take(components))].join(','),
    for (final o in projections)
      [o.id, 'supplementary', ...reals(o.scores.take(components))].join(','),
  ];
  List<double> t2Contributions(Observation o) {
    final out = <double>[];
    for (var j = 0; j < size; j++) {
      var w = 0.0;
      for (var k = 0; k < components; k++) {
        w += o.scores[k] / fit.eigen.values[k] * fit.eigen.vectors[k][j];
      }
      out.add(o.z[j] * w);
    }
    return out;
  }

  List<String> topSection(
    String label,
    List<double> values,
    List<List<double>> contributions,
  ) {
    final lines = ['top $label', 'rank id $label variable contribution'],
        order = topIndices(values, dataset.settings.top);
    for (var rank = 0; rank < order.length; rank++) {
      final i = order[rank], j = largestIndex(contributions[i]);
      lines.add(
        '${rank + 1} ${ids[i]} ${real(values[i])} ${names[j]} ${real(contributions[i][j])}',
      );
    }
    return lines;
  }

  List<String> outliersFile() {
    final s = dataset.settings;
    var lines = [
      'diagnostics components $components t2_limit ${real(s.t2Limit)} spe_limit ${real(s.speLimit)}',
      'id t2 spe quality flag',
    ];
    var tCount = 0, qCount = 0, both = 0, any = 0;
    final t2 = <double>[],
        spe = <double>[],
        tc = <List<double>>[],
        qc = <List<double>>[];
    for (final o in observations) {
      final retained = o.scores.take(components).toList(),
          quality = dot(retained, retained) / dot(o.z, o.z);
      lines.add('${o.id} ${reals([o.t2, o.spe, quality]).join(' ')} ${o.flag}');
      if (o.flag.contains('T')) tCount++;
      if (o.flag.contains('Q')) qCount++;
      if (o.flag == 'TQ') both++;
      if (o.flag != '-') any++;
      t2.add(o.t2);
      spe.add(o.spe);
      tc.add(t2Contributions(o));
      qc.add([for (final e in o.residualsList) e * e]);
    }
    lines.add('flagged t2 $tCount spe $qCount both $both any $any');
    final sections = [
      lines,
      topSection('t2', t2, tc),
      topSection('spe', spe, qc),
    ];
    lines = ['reconstruction', 'k mean_spe max_spe max_id'];
    for (var k = 1; k < size; k++) {
      final errors = <double>[];
      for (final o in observations) {
        final e = residuals(o.z, o.scores, fit.eigen.vectors, k);
        errors.add(dot(e, e));
      }
      final worst = largestIndex(errors);
      lines.add(
        '$k ${real(sum(errors) / rows)} ${real(errors[worst])} ${ids[worst]}',
      );
    }
    sections.add(lines);
    final header = [
      'id',
      ...componentNames('pc', components),
      't2',
      'spe',
      'flag',
      'nearest',
      'distance',
    ];
    lines = ['supplementary', header.join(' ')];
    for (final o in projections) {
      final distances = <double>[];
      for (final other in observations) {
        final d = [
          for (var k = 0; k < components; k++) o.scores[k] - other.scores[k],
        ];
        distances.add(dot(d, d));
      }
      final nearest = smallestIndex(distances),
          values = [...o.scores.take(components), o.t2, o.spe];
      lines.add(
        '${o.id} ${reals(values).join(' ')} ${o.flag} ${ids[nearest]} ${real(math.sqrt(distances[nearest]))}',
      );
    }
    sections.add(lines);
    return joinSections(sections);
  }

  List<String> screeSection() {
    final width = dataset.settings.screeWidth,
        first = fit.eigen.values.first,
        kaiser = roundedPosition(variance.average / first, width.toDouble()),
        lines = ['scree width $width kaiser_column $kaiser'];
    for (var k = 0; k < size; k++) {
      final value = fit.eigen.values[k],
          length = roundedPosition(value / first, width.toDouble()),
          broken = roundedPosition(
            variance.broken[k] * variance.total / first,
            width.toDouble(),
          );
      lines.add(
        '${screeLine(length, kaiser, broken, width)} pc${k + 1} ${real(value)}',
      );
    }
    return lines;
  }

  List<String> biplotSection() {
    final w = dataset.settings.biplotWidth,
        h = dataset.settings.biplotHeight,
        points = [...observations, ...projections];
    var xLimit = 0.0, yLimit = 0.0;
    for (final o in points) {
      xLimit = math.max(xLimit, o.scores[0].abs());
      yLimit = math.max(yLimit, o.scores[1].abs());
    }
    var xLoading = 0.0, yLoading = 0.0;
    for (final v in loadings) {
      xLoading = math.max(xLoading, v[0].abs());
      yLoading = math.max(yLoading, v[1].abs());
    }
    final scale = 0.9 * math.min(xLimit / xLoading, yLimit / yLoading),
        origin = biplotCell(0, 0, xLimit, yLimit, w, h),
        tips = [
          for (final v in loadings)
            biplotCell(scale * v[0], scale * v[1], xLimit, yLimit, w, h),
        ],
        cells = [
          for (final o in points)
            biplotCell(o.scores[0], o.scores[1], xLimit, yLimit, w, h),
        ],
        grid = newGrid(h, w);
    drawAxes(grid, origin);
    for (final tip in tips) {
      markCells(grid, shaftCells(origin, tip), shaftCharacter(origin, tip));
    }
    drawPoints(grid, cells.take(rows));
    for (var i = 0; i < rows; i++) {
      if (observations[i].flag != '-') markCells(grid, [cells[i]], 'X');
    }
    markCells(grid, cells.skip(rows), '*');
    for (var j = 0; j < size; j++) {
      markCells(grid, [tips[j]], String.fromCharCode(65 + j));
    }
    return [
      'biplot pc1 pc2 width $w height $h',
      'x ${real(-xLimit)} ${real(xLimit)} y ${real(-yLimit)} ${real(yLimit)} arrow_scale ${real(scale)}',
      ...framed(grid),
      for (var j = 0; j < size; j++)
        '${String.fromCharCode(65 + j)} ${names[j]} ${real(loadings[j][0])} ${real(loadings[j][1])}',
    ];
  }

  List<String> circleSection() {
    final radius = dataset.settings.radius,
        center = (radius ~/ 2 + 1, radius + 1),
        grid = newGrid(radius + 3, 2 * radius + 3);
    drawAxes(grid, center);
    for (var row = 0; row < grid.length; row++) {
      for (var col = 0; col < grid[row].length; col++) {
        if (!insideCircle(row, col, center, radius)) continue;
        for (final d in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
          if (!insideCircle(row + d.$1, col + d.$2, center, radius)) {
            grid[row][col] = '.';
            break;
          }
        }
      }
    }
    for (var j = 0; j < size; j++) {
      markCells(grid, [
        circleCell(circle[j][0], circle[j][1], radius),
      ], String.fromCharCode(65 + j));
    }
    return [
      'circle radius $radius',
      ...framed(grid),
      for (var j = 0; j < size; j++)
        '${String.fromCharCode(65 + j)} ${names[j]} ${reals([circle[j][0], circle[j][1], circle[j][0] * circle[j][0] + circle[j][1] * circle[j][1]]).join(' ')}',
    ];
  }

  List<String> diagnosticSection() {
    final s = dataset.settings,
        w = s.diagnosticWidth,
        h = s.diagnosticHeight,
        x = 2 * s.t2Limit,
        y = 2 * s.speLimit,
        grid = newGrid(h, w);
    drawAxes(grid, diagnosticCell(s.t2Limit, s.speLimit, x, y, w, h));
    drawPoints(grid, [
      for (final o in observations) diagnosticCell(o.t2, o.spe, x, y, w, h),
    ]);
    markCells(grid, [
      for (final o in projections) diagnosticCell(o.t2, o.spe, x, y, w, h),
    ], '*');
    return [
      'diagnostic width $w height $h t2_max ${real(x)} spe_max ${real(y)}',
      ...framed(grid),
    ];
  }
}

List<String> joinSections(List<List<String>> sections) => [
  for (var i = 0; i < sections.length; i++) ...[if (i > 0) '', ...sections[i]],
];
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
void main() {
  final r = PcaReport(readDataset());
  Directory('output').createSync(recursive: true);
  writeLines('eigen.txt', r.eigenFile());
  writeLines('loadings.csv', r.loadingsFile());
  writeLines('scores.csv', r.scoresFile());
  writeLines('outliers.txt', r.outliersFile());
  writeLines(
    'plots.txt',
    joinSections([
      r.screeSection(),
      r.biplotSection(),
      r.circleSection(),
      r.diagnosticSection(),
    ]),
  );
}
