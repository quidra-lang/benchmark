import 'dart:io';
import 'dart:math' hide Point;

part 'dataset.dart';
part 'gaussian.dart';
part 'em.dart';
part 'kmeans.dart';
part 'report.dart';

bool listEqual<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

int parameterCount(int k, String kind) => switch (kind) {
  'FULL' => 6 * k - 1,
  'TIED' => 3 * k + 2,
  'DIAG' => 5 * k - 1,
  _ => 4 * k - 1,
};
int argmax(List<double> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[best]) {
      best = i;
    }
  }
  return best;
}

class Summary {
  final int k, typePosition, parameters;
  final String kind;
  final EMRun run;
  final assigned = <int>[],
      sizes = <int>[],
      maxResponsibilities = <double>[],
      entropies = <double>[];
  double entropy = 0;
  late final double bic, aic, icl;
  Summary(this.run, this.kind, this.typePosition, int n)
    : k = run.model.length,
      parameters = parameterCount(run.model.length, kind) {
    sizes.addAll(List.filled(k, 0));
    for (final record in run.records) {
      final component = argmax(record.responsibilities);
      assigned.add(component);
      sizes[component]++;
      maxResponsibilities.add(record.responsibilities[component]);
      var pointEntropy = 0.0;
      for (final r in record.responsibilities) {
        if (r > 0) {
          pointEntropy -= r * log(r);
        }
      }
      entropies.add(pointEntropy);
      entropy += pointEntropy;
    }
    bic = -2 * run.loglik + parameters * log(n);
    aic = -2 * run.loglik + 2 * parameters;
    icl = bic + 2 * entropy;
  }
}

double criterion(Summary s, String name) => name == 'aic'
    ? s.aic
    : name == 'icl'
    ? s.icl
    : s.bic;
List<Summary> rankModels(List<Summary> models, String name) =>
    List<Summary>.of(models)..sort((a, b) {
      final x = rounded4(
            criterion(a, name),
          ).compareTo(rounded4(criterion(b, name))),
          p = a.parameters.compareTo(b.parameters),
          k = a.k.compareTo(b.k);
      return x != 0
          ? x
          : p != 0
          ? p
          : k != 0
          ? k
          : a.typePosition.compareTo(b.typePosition);
    });
List<List<int>> contingency(List<int> a, List<int> b, int rows, int columns) {
  final result = List.generate(rows, (_) => List.filled(columns, 0));
  for (var i = 0; i < a.length; i++) {
    result[a[i]][b[i]]++;
  }
  return result;
}

class Fraction {
  final int numerator, denominator;
  Fraction(this.numerator, this.denominator);
}

int gcd(int a, int b) {
  a = a.abs();
  b = b.abs();
  while (b != 0) {
    final old = b;
    b = a % b;
    a = old;
  }
  return a;
}

Fraction ari(List<List<int>> table) {
  final columns = List.filled(table.first.length, 0);
  var s = 0, a = 0, b = 0, n = 0;
  int c2(int value) => value * (value - 1) ~/ 2;
  for (final row in table) {
    var total = 0;
    for (var j = 0; j < row.length; j++) {
      final value = row[j];
      s += c2(value);
      total += value;
      columns[j] += value;
    }
    a += c2(total);
    n += total;
  }
  for (final value in columns) {
    b += c2(value);
  }
  final z = c2(n);
  var numerator = 2 * (z * s - a * b), denominator = z * (a + b) - 2 * a * b;
  if (denominator == 0) {
    return Fraction(1, 1);
  }
  if (denominator < 0) {
    numerator = -numerator;
    denominator = -denominator;
  }
  final d = gcd(numerator, denominator);
  return Fraction(numerator ~/ d, denominator ~/ d);
}

String fractionText(Fraction value) =>
    '${value.numerator}/${value.denominator} ${number(value.numerator / value.denominator)}';
List<List<double>> distanceMatrix(List<DataPoint> points) => [
  for (final a in points) [for (final b in points) distance(a.point, b.point)],
];

class PartitionMetrics {
  double silhouette = double.nan, ch = double.nan, db = double.nan;
  final List<double> clusterSilhouette;
  PartitionMetrics(int k) : clusterSilhouette = List.filled(k, double.nan);
}

PartitionMetrics partitionMetrics(
  List<DataPoint> points,
  List<int> assigned,
  int k,
  List<List<double>> distances,
) {
  final result = PartitionMetrics(k),
      groups = List.generate(k, (_) => <int>[]),
      xs = List.filled(k, 0.0),
      ys = List.filled(k, 0.0);
  var overallX = 0.0, overallY = 0.0;
  for (var i = 0; i < points.length; i++) {
    final c = assigned[i], point = points[i].point;
    groups[c].add(i);
    xs[c] += point.x;
    ys[c] += point.y;
    overallX += point.x;
    overallY += point.y;
  }
  final overall = Point(overallX / points.length, overallY / points.length),
      nonempty = [
        for (var c = 0; c < k; c++)
          if (groups[c].isNotEmpty) c,
      ],
      centers = [
        for (var c = 0; c < k; c++)
          groups[c].isEmpty
              ? const Point(0, 0)
              : Point(xs[c] / groups[c].length, ys[c] / groups[c].length),
      ],
      g = nonempty.length;
  if (g < 2) {
    return result;
  }
  var silhouetteSum = 0.0;
  final clusterSums = List.filled(k, 0.0);
  for (var i = 0; i < assigned.length; i++) {
    final c = assigned[i];
    var s = 0.0;
    if (groups[c].length > 1) {
      var a = 0.0;
      for (final j in groups[c]) {
        if (i != j) {
          a += distances[i][j];
        }
      }
      a /= groups[c].length - 1;
      var b = double.infinity;
      for (final other in nonempty) {
        if (other == c) {
          continue;
        }
        var total = 0.0;
        for (final j in groups[other]) {
          total += distances[i][j];
        }
        b = min(b, total / groups[other].length);
      }
      s = (b - a) / max(a, b);
    }
    silhouetteSum += s;
    clusterSums[c] += s;
  }
  result.silhouette = silhouetteSum / points.length;
  var between = 0.0, within = 0.0;
  final scatter = List.filled(k, 0.0);
  for (final c in nonempty) {
    result.clusterSilhouette[c] = clusterSums[c] / groups[c].length;
    between += groups[c].length * distance2(centers[c], overall);
    var total = 0.0;
    for (final i in groups[c]) {
      total += distance(points[i].point, centers[c]);
    }
    scatter[c] = total / groups[c].length;
  }
  for (var i = 0; i < points.length; i++) {
    within += distance2(points[i].point, centers[assigned[i]]);
  }
  result.ch = (between / (g - 1)) / (within / (points.length - g));
  var total = 0.0;
  for (final c in nonempty) {
    var maximum = 0.0;
    for (final other in nonempty) {
      if (other != c) {
        maximum = max(
          maximum,
          (scatter[c] + scatter[other]) / distance(centers[c], centers[other]),
        );
      }
    }
    total += maximum;
  }
  result.db = total / g;
  return result;
}

(List<int>, int) matching(List<List<int>> table) {
  final k = table.length, used = List.filled(table.length, false);
  var best = <int>[], bestAgreement = -1;
  void visit(List<int> permutation) {
    if (permutation.length == k) {
      var agreement = 0;
      for (var j = 0; j < k; j++) {
        agreement += table[permutation[j]][j];
      }
      if (agreement > bestAgreement) {
        bestAgreement = agreement;
        best = List<int>.of(permutation);
      }
      return;
    }
    for (var a = 0; a < k; a++) {
      if (!used[a]) {
        used[a] = true;
        visit([...permutation, a]);
        used[a] = false;
      }
    }
  }

  visit([]);
  return (best, bestAgreement);
}

List<int> oneBased(List<int> values) => [for (final v in values) v + 1];
List<String> modelsFile(List<Summary> models, int n) {
  final lines = <String>[];
  for (var index = 0; index < models.length; index++) {
    final s = models[index];
    if (index > 0) {
      lines.add('');
    }
    lines.addAll([
      'model K=${s.k} type=${s.kind}',
      'parameters ${s.parameters}',
      'loglik ${number(s.run.loglik)}',
      'bic ${number(s.bic)}',
      'aic ${number(s.aic)}',
      'icl ${number(s.icl)}',
      'mean_entropy ${number(s.entropy / n)}',
      'settled_at ${s.run.settledAt}',
      'largest_increase iteration ${s.run.largestIteration} value ${number(s.run.largestIncrease)}',
      'violations ${s.run.violations.length}',
      'sizes ${integerList(s.sizes)}',
    ]);
    for (var k = 0; k < s.k; k++) {
      final c = s.run.model[k], e = eigenData(c.cov);
      lines.add(
        'component ${k + 1} weight ${number(c.weight)} mean ${number(c.mean.x)} ${number(c.mean.y)} cov ${number(c.cov.a)} ${number(c.cov.b)} ${number(c.cov.c)} axes ${number(e.major)} ${number(e.minor)} angle ${number(e.angle)}',
      );
    }
  }
  return lines;
}

List<String> traceFile(List<Summary> models) => [
  'K,type,iteration,loglik',
  for (final s in models)
    for (var t = 0; t < s.run.trace.length; t++)
      '${s.k},${s.kind},$t,${number(s.run.trace[t])}',
];
List<String> assignmentFile(List<DataPoint> points, Summary s, KMeans km) => [
  'id,component,max_responsibility,log_density,kmeans_cluster',
  for (var i = 0; i < points.length; i++)
    '${points[i].id},${s.assigned[i] + 1},${number(s.maxResponsibilities[i])},${number(s.run.records[i].logDensity)},${km.assignment[i] + 1}',
];
List<String> rankingLines(List<Summary> models) {
  final bic = rankModels(models, 'bic'),
      aic = rankModels(models, 'aic'),
      icl = rankModels(models, 'icl'),
      aicRanks = <Summary, int>{},
      iclRanks = <Summary, int>{};
  for (var i = 0; i < aic.length; i++) {
    aicRanks[aic[i]] = i + 1;
  }
  for (var i = 0; i < icl.length; i++) {
    iclRanks[icl[i]] = i + 1;
  }
  final selected = bic.first,
      lines = <String>[
        'ranking by bic',
        'rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank',
      ];
  for (var i = 0; i < bic.length; i++) {
    final s = bic[i],
        delta = (rounded4(s.bic) - rounded4(selected.bic)) / 10000;
    lines.add(
      '${i + 1} ${s.k} ${s.kind} ${s.parameters} ${number(s.run.loglik)} ${number(s.bic)} ${number(delta)} ${number(s.aic)} ${aicRanks[s]} ${number(s.icl)} ${iclRanks[s]}',
    );
  }
  lines.addAll([
    'selected K=${selected.k} type=${selected.kind}',
    'best_aic K=${aic.first.k} type=${aic.first.kind}',
    'best_icl K=${icl.first.k} type=${icl.first.kind}',
  ]);
  return lines;
}

List<String> bestTypeLines(List<Summary> models, Params p) {
  final lines = <String>['best K per type'];
  for (final kind in p.types) {
    final subset = models.where((s) => s.kind == kind).toList();
    lines.add(
      '$kind bic ${rankModels(subset, 'bic').first.k} aic ${rankModels(subset, 'aic').first.k} icl ${rankModels(subset, 'icl').first.k}',
    );
  }
  return lines;
}

List<String> comparisonLines(
  List<DataPoint> points,
  Summary s,
  KMeans km,
  Summary? previous,
  List<List<double>> distances,
) {
  final gmmMetrics = partitionMetrics(points, s.assigned, s.k, distances),
      kmMetrics = partitionMetrics(points, km.assignment, s.k, distances);
  final lines = <String>[
    'K=${s.k} type=${s.kind} bic ${number(s.bic)}',
    '  kmeans iterations ${km.iterations} inertia ${number(km.inertia)}',
    '  ari ${fractionText(ari(contingency(s.assigned, km.assignment, s.k, s.k)))}',
    '  silhouette gmm ${optional(gmmMetrics.silhouette)} kmeans ${optional(kmMetrics.silhouette)}',
    '  calinski_harabasz gmm ${optional(gmmMetrics.ch)} kmeans ${optional(kmMetrics.ch)}',
    '  davies_bouldin gmm ${optional(gmmMetrics.db)} kmeans ${optional(kmMetrics.db)}',
  ];
  if (previous != null) {
    final table = contingency(previous.assigned, s.assigned, previous.k, s.k),
        parents = <String>[],
        shared = <int>[];
    for (var b = 0; b < s.k; b++) {
      var parent = 0, count = 0;
      for (var a = 0; a < previous.k; a++) {
        if (table[a][b] > count) {
          parent = a + 1;
          count = table[a][b];
        }
      }
      parents.add(parent == 0 ? '-' : '$parent');
      shared.add(count);
    }
    lines.add(
      '  parents K=${previous.k} ${parents.join(' ')} shared ${integerList(shared)}',
    );
  }
  return lines;
}

List<String> violationLines(List<Summary> models) {
  final lines = <String>['violations'];
  for (final s in models) {
    for (final t in s.run.violations) {
      lines.add(
        'K=${s.k} type=${s.kind} iteration $t previous ${number(s.run.trace[t - 1])} current ${number(s.run.trace[t])}',
      );
    }
  }
  if (lines.length == 1) {
    lines.add('none');
  }
  return lines;
}

List<String> selectedComponentLines(
  List<DataPoint> points,
  Summary s,
  Params p,
  List<List<double>> distances,
) {
  final lines = <String>['selected components'],
      metrics = partitionMetrics(points, s.assigned, s.k, distances);
  for (var k = 0; k < s.k; k++) {
    final c = s.run.model[k], observed = List.filled(p.gofEdges.length + 1, 0);
    var soft = 0.0, inside1 = 0, inside2 = 0;
    for (var i = 0; i < points.length; i++) {
      soft += s.run.records[i].responsibilities[k];
      if (s.assigned[i] != k) {
        continue;
      }
      final q = mahalanobis(points[i].point, c.mean, c.cov);
      if (q <= 1) {
        inside1++;
      }
      if (q <= 4) {
        inside2++;
      }
      final radius = sqrt(q);
      var bin = 0;
      while (bin < p.gofEdges.length && radius >= p.gofEdges[bin]) {
        bin++;
      }
      observed[bin]++;
    }
    final expected = List.filled(observed.length, 0.0);
    var chi = 0.0;
    for (var bin = 0; bin < expected.length; bin++) {
      final lower = bin == 0 ? 0.0 : p.gofEdges[bin - 1],
          upperProbability = bin == p.gofEdges.length
              ? 0.0
              : exp(-p.gofEdges[bin] * p.gofEdges[bin] / 2);
      expected[bin] = s.sizes[k] * (exp(-lower * lower / 2) - upperProbability);
      final difference = observed[bin] - expected[bin];
      chi += difference * difference / expected[bin];
    }
    final e = eigenData(c.cov);
    lines.addAll([
      'component ${k + 1} weight ${number(c.weight)} size ${s.sizes[k]} soft_size ${number(soft)} mean ${number(c.mean.x)} ${number(c.mean.y)}',
      '  cov ${number(c.cov.a)} ${number(c.cov.b)} ${number(c.cov.c)} corr ${number(e.correlation)}',
      '  eigen ${number(e.leading)} ${number(e.trailing)} direction ${number(e.direction.x)} ${number(e.direction.y)} angle ${number(e.angle)}',
      '  axes_1sigma ${number(e.major)} ${number(e.minor)} axes_2sigma ${number(2 * e.major)} ${number(2 * e.minor)}',
      '  inside_1sigma $inside1 inside_2sigma $inside2 area_1sigma ${number(e.area)}',
      '  silhouette ${optional(metrics.clusterSilhouette[k])}',
      '  gof observed ${integerList(observed)} expected ${numberList(expected)} chi2 ${number(chi)}',
    ]);
  }
  return lines;
}

List<String> overlapLines(Summary s) {
  final lines = <String>['overlap'];
  for (var a = 0; a < s.k; a++) {
    for (var b = a + 1; b < s.k; b++) {
      final (d, coefficient) = bhattacharyya(s.run.model[a], s.run.model[b]);
      var shared = 0.0;
      for (final record in s.run.records) {
        shared += record.responsibilities[a] * record.responsibilities[b];
      }
      lines.add(
        '${a + 1}-${b + 1} bhattacharyya ${number(d)} coefficient ${number(coefficient)} shared ${number(shared)}',
      );
    }
  }
  if (s.k == 1) {
    lines.add('none');
  }
  return lines;
}

List<List<double>> groupedResponsibilities(
  List<ERecord> records,
  List<List<int>> groups,
) {
  final result = <List<double>>[];
  for (final record in records) {
    final row = <double>[];
    for (final group in groups) {
      var total = 0.0;
      for (final k in group) {
        total += record.responsibilities[k];
      }
      row.add(total);
    }
    result.add(row);
  }
  return result;
}

double groupEntropy(List<List<double>> values) {
  var total = 0.0;
  for (final row in values) {
    var entropy = 0.0;
    for (final value in row) {
      if (value > 0) {
        entropy -= value * log(value);
      }
    }
    total += entropy;
  }
  return total;
}

List<List<int>> mergeGroups(List<List<int>> groups, int a, int b) => [
  for (var i = 0; i < groups.length; i++)
    if (i != b)
      i == a ? ([...groups[a], ...groups[b]]..sort()) : List<int>.of(groups[i]),
];
String clusterName(List<int> group) => group.map((k) => k + 1).join('+');
List<String> mergingLines(Summary s) {
  var groups = List.generate(s.k, (k) => [k]);
  final lines = <String>[
    'merging',
    'start entropy ${number(groupEntropy(groupedResponsibilities(s.run.records, groups)))}',
  ];
  for (var step = 1; groups.length > 1; step++) {
    var aBest = 0, bBest = 1, bestEntropy = 0.0;
    List<List<int>>? bestGroups;
    for (var a = 0; a < groups.length; a++) {
      for (var b = a + 1; b < groups.length; b++) {
        final candidate = mergeGroups(groups, a, b),
            entropy = groupEntropy(
              groupedResponsibilities(s.run.records, candidate),
            );
        if (bestGroups == null || rounded4(entropy) < rounded4(bestEntropy)) {
          aBest = a;
          bBest = b;
          bestEntropy = entropy;
          bestGroups = candidate;
        }
      }
    }
    final aName = clusterName(groups[aBest]),
        bName = clusterName(groups[bBest]);
    groups = bestGroups!;
    final values = groupedResponsibilities(s.run.records, groups),
        sizes = List.filled(groups.length, 0);
    for (final row in values) {
      sizes[argmax(row)]++;
    }
    lines.add(
      'step $step merge $aName $bName entropy ${number(bestEntropy)} sizes ${integerList(sizes)}',
    );
  }
  return lines;
}

List<String> kmeansLines(List<DataPoint> points, Summary s, KMeans km) {
  final table = contingency(s.assigned, km.assignment, s.k, s.k);
  final (permutation, agreement) = matching(table);
  final lines = <String>[
    'kmeans K=${s.k}',
    'iterations ${km.iterations}',
    'inertia ${number(km.inertia)}',
    'sizes ${integerList(km.sizes)}',
  ];
  for (var j = 0; j < km.centers.length; j++) {
    final c = km.centers[j];
    lines.add('center ${j + 1} ${number(c.x)} ${number(c.y)}');
  }
  lines.addAll([
    'contingency',
    for (final row in table) integerList(row),
    'ari ${fractionText(ari(table))}',
    'matching ${integerList(oneBased(permutation))}',
    'agreement $agreement/${points.length} ${number(agreement / points.length)}',
  ]);
  var disagreements = 0;
  for (var i = 0; i < points.length; i++) {
    if (permutation[km.assignment[i]] != s.assigned[i]) {
      disagreements++;
      lines.add(
        'disagree ${points[i].id} gmm ${s.assigned[i] + 1} kmeans ${km.assignment[i] + 1} max ${number(s.maxResponsibilities[i])}',
      );
    }
  }
  lines.add('disagreements $disagreements');
  return lines;
}

List<String> refitLines(
  List<DataPoint> points,
  Summary s,
  KMeans km,
  Params p,
) {
  final initial = <Component>[];
  for (var j = 0; j < km.centers.length; j++) {
    final center = km.centers[j];
    var a = 0.0, b = 0.0, c = 0.0;
    for (var i = 0; i < points.length; i++) {
      if (km.assignment[i] == j) {
        final dx = points[i].point.x - center.x,
            dy = points[i].point.y - center.y;
        a += dx * dx;
        b += dx * dy;
        c += dy * dy;
      }
    }
    final count = km.sizes[j];
    initial.add(
      Component(
        count / points.length,
        center,
        Covariance(a / count + p.epsilon, b / count, c / count + p.epsilon),
      ),
    );
  }
  final refit = Summary(
    runEM(points, initial, s.kind, p),
    s.kind,
    s.typePosition,
    points.length,
  );
  return [
    'refit_from_kmeans K=${s.k} type=${s.kind}',
    'loglik ${number(refit.run.loglik)} bic ${number(refit.bic)} settled_at ${refit.run.settledAt}',
    'sizes ${integerList(refit.sizes)}',
    'ari_vs_selected ${fractionText(ari(contingency(s.assigned, refit.assigned, s.k, s.k)))}',
  ];
}

List<String> crossValidationLines(
  List<DataPoint> points,
  Summary s,
  Model initial,
  Params p,
) {
  final lines = <String>[
    'cross_validation K=${s.k} type=${s.kind} folds ${p.folds}',
  ];
  var total = 0.0;
  for (var f = 0; f < p.folds; f++) {
    final training = <DataPoint>[], testing = <DataPoint>[];
    for (var i = 0; i < points.length; i++) {
      (i % p.folds == f ? testing : training).add(points[i]);
    }
    final run = runEM(training, initial, s.kind, p);
    final (_, testLoglik) = expectation(testing, run.model);
    final testMean = testLoglik / testing.length;
    total += testMean;
    lines.add(
      'fold ${f + 1} train ${training.length} test ${testing.length} train_loglik ${number(run.loglik / training.length)} test_loglik ${number(testMean)}',
    );
  }
  lines.add('mean_test_loglik ${number(total / p.folds)}');
  return lines;
}

List<String> uncertainLines(
  List<DataPoint> points,
  Summary s,
  double threshold,
) {
  final indices =
      [
        for (var i = 0; i < points.length; i++)
          if (s.maxResponsibilities[i] < threshold) i,
      ]..sort((a, b) {
        final c = rounded4(
          s.maxResponsibilities[a],
        ).compareTo(rounded4(s.maxResponsibilities[b]));
        return c != 0 ? c : a.compareTo(b);
      });
  return [
    'uncertain threshold ${number(threshold)}',
    for (final i in indices)
      '${points[i].id} component ${s.assigned[i] + 1} max ${number(s.maxResponsibilities[i])} responsibilities ${numberList(s.run.records[i].responsibilities)}',
    'count ${indices.length}',
  ];
}

List<String> outlierLines(List<DataPoint> points, Summary s, double threshold) {
  final indices =
      [
        for (var i = 0; i < points.length; i++)
          if (s.run.records[i].logDensity < threshold) i,
      ]..sort((a, b) {
        final c = rounded4(
          s.run.records[a].logDensity,
        ).compareTo(rounded4(s.run.records[b].logDensity));
        return c != 0 ? c : a.compareTo(b);
      });
  final lines = <String>['outliers threshold ${number(threshold)}'];
  for (final i in indices) {
    final c = s.run.model[s.assigned[i]];
    lines.add(
      '${points[i].id} component ${s.assigned[i] + 1} log_density ${number(s.run.records[i].logDensity)} q ${number(mahalanobis(points[i].point, c.mean, c.cov))}',
    );
  }
  lines.add('count ${indices.length}');
  return lines;
}

List<String> selectionFile(
  List<DataPoint> points,
  List<Summary> models,
  Summary selected,
  Map<int, Summary> bestByK,
  Map<int, KMeans> kmeans,
  Map<int, Model> initial,
  Params p,
  List<List<double>> distances,
) {
  final parts = <List<String>>[rankingLines(models), bestTypeLines(models, p)];
  Summary? previous;
  for (final k in p.k) {
    final s = bestByK[k]!;
    parts.add(comparisonLines(points, s, kmeans[k]!, previous, distances));
    previous = s;
  }
  parts.addAll([
    violationLines(models),
    selectedComponentLines(points, selected, p, distances),
    overlapLines(selected),
    mergingLines(selected),
    kmeansLines(points, selected, kmeans[selected.k]!),
    refitLines(points, selected, kmeans[selected.k]!, p),
    crossValidationLines(points, selected, initial[selected.k]!, p),
    uncertainLines(points, selected, p.uncertain),
    outlierLines(points, selected, p.lowDensity),
  ]);
  final lines = <String>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) {
      lines.add('');
    }
    lines.addAll(parts[i]);
  }
  return lines;
}

List<List<String>> canvas(int width, int height) =>
    List.generate(height, (_) => List.filled(width, ' '));
(int, int, bool) mapCell(Point point, Params p, double stepX, double stepY) {
  final column = ((point.x - p.xmin) / stepX).floor(),
      row = ((p.ymax - point.y) / stepY).floor();
  return (
    column,
    row,
    column >= 0 && column < p.width && row >= 0 && row < p.height,
  );
}

List<String> densityMapFile(List<DataPoint> points, Summary s, Params p) {
  final stepX = (p.xmax - p.xmin) / p.width,
      stepY = (p.ymax - p.ymin) / p.height,
      centers = <DataPoint>[];
  for (var row = 0; row < p.height; row++) {
    for (var column = 0; column < p.width; column++) {
      centers.add(
        DataPoint(
          '',
          Point(p.xmin + (column + 0.5) * stepX, p.ymax - (row + 0.5) * stepY),
        ),
      );
    }
  }
  final (records, _) = expectation(centers, s.run.model);
  final densities = <double>[], q = <List<double>>[];
  var maximum = 0.0, mass = 0.0;
  for (var i = 0; i < records.length; i++) {
    var density = 0.0;
    for (final score in records[i].scores) {
      density += exp(score);
    }
    densities.add(density);
    maximum = max(maximum, density);
    mass += density;
    q.add([
      for (final c in s.run.model) mahalanobis(centers[i].point, c.mean, c.cov),
    ]);
  }
  mass *= stepX;
  mass *= stepY;
  final densityRows = canvas(p.width, p.height),
      regionRows = canvas(p.width, p.height),
      uncertaintyRows = canvas(p.width, p.height),
      pointRows = canvas(p.width, p.height),
      levelCounts = List.filled(10, 0);
  const levels = ' .:-=+*#%@';
  for (var i = 0; i < records.length; i++) {
    final r = records[i],
        row = i ~/ p.width,
        column = i % p.width,
        level = min(9, (10 * densities[i] / maximum).floor());
    levelCounts[level]++;
    densityRows[row][column] = levels[level];
    regionRows[row][column] = '${argmax(r.scores) + 1}';
    if (s.k > 1) {
      var entropy = 0.0;
      for (final value in r.responsibilities) {
        if (value > 0) {
          entropy -= value * log(value);
        }
      }
      final uncertaintyLevel = (10 * entropy / log(s.k))
          .floor()
          .clamp(0, 9)
          .toInt();
      uncertaintyRows[row][column] = levels[uncertaintyLevel];
    }
    var contour = false;
    for (var k = 0; k < s.k && !contour; k++) {
      if (q[i][k] > 4) {
        continue;
      }
      for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
        final x = column + dx, y = row + dy;
        if (x >= 0 &&
            x < p.width &&
            y >= 0 &&
            y < p.height &&
            q[y * p.width + x][k] > 4) {
          contour = true;
          break;
        }
      }
    }
    if (contour) {
      pointRows[row][column] = '.';
    }
  }
  for (var k = 0; k < s.k; k++) {
    final (column, row, inside) = mapCell(s.run.model[k].mean, p, stepX, stepY);
    if (inside) {
      densityRows[row][column] = '${k + 1}';
    }
  }
  final pointComponents = List.filled(p.width * p.height, -1);
  var outside = 0;
  for (var i = 0; i < points.length; i++) {
    final (column, row, inside) = mapCell(points[i].point, p, stepX, stepY);
    if (!inside) {
      outside++;
      continue;
    }
    final index = row * p.width + column, old = pointComponents[index];
    if (old == -1) {
      pointComponents[index] = s.assigned[i];
    } else if (old != s.assigned[i]) {
      pointComponents[index] = -2;
    }
  }
  for (var index = 0; index < pointComponents.length; index++) {
    final c = pointComponents[index];
    if (c != -1) {
      pointRows[index ~/ p.width][index % p.width] = c == -2 ? '*' : '${c + 1}';
    }
  }
  final lines = <String>[
    'density K=${s.k} type=${s.kind}',
    'x ${number(p.xmin)} ${number(p.xmax)} y ${number(p.ymin)} ${number(p.ymax)} grid ${p.width}x${p.height}',
    'max_density ${numberDigits(maximum, 6)} mass_in_map ${number(mass)}',
    ...framed(densityRows),
  ];
  for (var level = 0; level < 10; level++) {
    lines.add(
      'level $level "${levels[level]}" from ${numberDigits(level * maximum / 10, 6)} cells ${levelCounts[level]}',
    );
  }
  lines.addAll([
    '',
    'regions',
    ...framed(regionRows),
    '',
    'uncertainty',
    ...framed(uncertaintyRows),
    '',
    'points',
    ...framed(pointRows),
    'outside $outside',
  ]);
  return lines;
}

void main() {
  final (points, initial, p) = readDataset();
  final models = <Summary>[],
      kmeans = <int, KMeans>{},
      bestByK = <int, Summary>{};
  for (final k in p.k) {
    final subset = <Summary>[];
    for (var typePosition = 0; typePosition < p.types.length; typePosition++) {
      final kind = p.types[typePosition],
          run = runEM(points, initial[k]!, kind, p),
          summary = Summary(run, kind, typePosition, points.length);
      models.add(summary);
      subset.add(summary);
    }
    bestByK[k] = rankModels(subset, 'bic').first;
    kmeans[k] = runKMeans(points, [
      for (final c in initial[k]!) c.mean,
    ], p.kmeansMax);
  }
  final selected = rankModels(models, 'bic').first,
      distances = distanceMatrix(points);
  writeLines('models.txt', modelsFile(models, points.length));
  writeLines('loglik_trace.csv', traceFile(models));
  writeLines(
    'assignments.csv',
    assignmentFile(points, selected, kmeans[selected.k]!),
  );
  writeLines(
    'selection.txt',
    selectionFile(
      points,
      models,
      selected,
      bestByK,
      kmeans,
      initial,
      p,
      distances,
    ),
  );
  writeLines('density_map.txt', densityMapFile(points, selected, p));
}
