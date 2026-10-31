import 'dart:io';
import 'dart:math' as math;
part 'dataset.dart';
part 'kernels.dart';
part 'loess.dart';
part 'spline.dart';
part 'selection.dart';

abstract class Fit {
  List<double> fitted = [];
  List<double>? leverage;
  double edf = double.nan;
  double estimate(int position);
  List<double>? weights(int position);
}

class LinearFit extends Fit {
  final List<double> x;
  late final double xbar, sxx, slope, intercept;
  LinearFit(List<Point> points) : x = points.map((p) => p.$1 / 100).toList() {
    final y = points.map((p) => p.$2 / 100).toList(), n = points.length;
    xbar = orderedSum(x) / n;
    final ybar = orderedSum(y) / n;
    var xx = 0.0, xy = 0.0;
    for (var i = 0; i < n; i++) {
      final d = x[i] - xbar;
      xx += d * d;
      xy += d * (y[i] - ybar);
    }
    sxx = xx;
    slope = xy / sxx;
    intercept = ybar - slope * xbar;
    fitted = x.map((v) => intercept + slope * v).toList();
    leverage = x.map((v) => 1 / n + (v - xbar) * (v - xbar) / sxx).toList();
    edf = 2;
  }
  @override
  double estimate(int position) => intercept + slope * (position / 100);
  @override
  List<double> weights(int position) => x
      .map((v) => 1 / x.length + (position / 100 - xbar) * (v - xbar) / sxx)
      .toList();
}

class RunningFit extends Fit {
  final List<int> positions;
  final windows = <(int, int)>[];
  RunningFit(List<Point> points, int width, bool useMedian)
    : positions = points.map((p) => p.$1).toList() {
    final diagonal = <double>[];
    for (var i = 0; i < points.length; i++) {
      final radius = math.min(
            (width - 1) ~/ 2,
            math.min(i, points.length - 1 - i),
          ),
          left = i - radius,
          right = i + radius + 1;
      final ys = points.sublist(left, right).map((p) => p.$2).toList();
      windows.add((left, right));
      var total = 0;
      for (final y in ys) {
        total += y;
      }
      if (useMedian) ys.sort();
      fitted.add(useMedian ? ys[radius] / 100 : total / (100 * ys.length));
      diagonal.add(1 / ys.length);
    }
    if (!useMedian) {
      leverage = diagonal;
      edf = orderedSum(diagonal);
    }
  }
  int nearest(int position) {
    var best = 0;
    for (var i = 1; i < positions.length; i++) {
      if ((positions[i] - position).abs() < (positions[best] - position).abs())
        best = i;
    }
    return best;
  }

  @override
  double estimate(int position) => fitted[nearest(position)];
  @override
  List<double> weights(int position) {
    final (left, right) = windows[nearest(position)];
    return [
      for (var i = 0; i < positions.length; i++)
        left <= i && i < right ? 1 / (right - left) : 0.0,
    ];
  }
}

typedef IsoBlock = (int, int, int, int);
(List<double>, List<IsoBlock>) isotonicDirection(
  List<Point> points,
  String direction,
) {
  final blocks = <IsoBlock>[];
  for (var i = 0; i < points.length; i++) {
    blocks.add((i, i, points[i].$2, 1));
    while (blocks.length >= 2) {
      final a = blocks[blocks.length - 2],
          b = blocks.last,
          left = blocks[blocks.length - 2].$3 * blocks.last.$4,
          right = blocks.last.$3 * blocks[blocks.length - 2].$4;
      if (!(direction == 'increasing' ? left > right : left < right)) break;
      blocks.removeRange(blocks.length - 2, blocks.length);
      blocks.add((a.$1, b.$2, a.$3 + b.$3, a.$4 + b.$4));
    }
  }
  final fitted = List.filled(points.length, 0.0);
  for (final (start, stop, total, count) in blocks) {
    final value = total / (100 * count);
    for (var i = start; i <= stop; i++) {
      fitted[i] = value;
    }
  }
  return (fitted, blocks);
}

class IsotonicFit extends Fit {
  final List<int> positions;
  final String mode;
  late final String direction;
  late final List<IsoBlock> blocks;
  double rssIncreasing = double.nan, rssDecreasing = double.nan;
  IsotonicFit(List<Point> points, this.mode)
    : positions = points.map((p) => p.$1).toList() {
    if (mode == 'auto') {
      final increasing = isotonicDirection(points, 'increasing'),
          decreasing = isotonicDirection(points, 'decreasing'),
          observed = points.map((p) => p.$2 / 100).toList();
      rssIncreasing = residualSquare(observed, increasing.$1);
      rssDecreasing = residualSquare(observed, decreasing.$1);
      direction = rssIncreasing <= rssDecreasing ? 'increasing' : 'decreasing';
      final selected = direction == 'increasing' ? increasing : decreasing;
      fitted = selected.$1;
      blocks = selected.$2;
    } else {
      direction = mode;
      final selected = isotonicDirection(points, mode);
      fitted = selected.$1;
      blocks = selected.$2;
    }
    edf = blocks.length.toDouble();
  }
  @override
  double estimate(int position) {
    var i = 0;
    while (i + 1 < positions.length && positions[i + 1] <= position) {
      i++;
    }
    return fitted[i];
  }

  @override
  List<double>? weights(int position) => null;
}

List<String> methodsInOrder(Settings s) => [
  'linear',
  'running_mean',
  'running_median',
  for (final k in s.kernels) 'nw_$k',
  for (final k in s.kernels) 'll_$k',
  for (final degree in s.degrees) 'loess$degree',
  'spline',
  'isotonic',
];
List<String> parametersFor(String method, Settings s) {
  if (method.startsWith('running_')) return s.windows;
  if (method.startsWith('nw_') || method.startsWith('ll_')) return s.bandwidths;
  if (method.startsWith('loess')) return s.spans;
  if (method == 'spline') return s.lambdas;
  return [];
}

Fit fitModel(
  String method,
  String parameter,
  List<Point> points,
  Settings s,
  String direction, {
  bool robust = true,
  bool diagnostics = true,
}) {
  if (method == 'linear') return LinearFit(points);
  if (method.startsWith('running_'))
    return RunningFit(points, int.parse(parameter), method == 'running_median');
  if (method == 'isotonic') return IsotonicFit(points, direction);
  final (positions, values) = pointData(points);
  if (method.startsWith('nw_') || method.startsWith('ll_'))
    return KernelFit(
      positions,
      values,
      hundredths(parameter),
      method.substring(3),
      method.startsWith('ll_'),
      diagnostics,
    );
  if (method.startsWith('loess'))
    return LoessFit(
      positions,
      values,
      hundredths(parameter),
      int.parse(method.substring(5)),
      robust ? s.robustIterations : 0,
      diagnostics,
    );
  return SplineFit(positions, values, double.parse(parameter), diagnostics);
}

List<double> validationPredictions(
  String method,
  String parameter,
  List<Point> points,
  Settings s,
  String direction,
  int folds,
) {
  final predictions = List.filled(points.length, double.nan);
  for (var group = 0; group < folds; group++) {
    final training = [
      for (var i = 0; i < points.length; i++)
        if (i % folds != group) points[i],
    ];
    final model = fitModel(
      method,
      parameter,
      training,
      s,
      direction,
      robust: false,
      diagnostics: false,
    );
    for (var i = group; i < points.length; i += folds) {
      predictions[i] = model.estimate(points[i].$1);
    }
  }
  return predictions;
}

class Candidate {
  final String parameter;
  final double score, edf;
  bool selected = false;
  Candidate(this.parameter, this.score, this.edf);
}

class Entry {
  late final Fit model;
  late String parameter;
  late final double loo, kfold;
  double gcv = double.nan;
  final candidates = <Candidate>[];
  late final List<double> gridValues;
  late final Diagnostics stats;
}

Map<String, Entry> selectModels(
  List<Point> points,
  Settings s,
  List<String> methods,
  String mode,
) {
  final entries = <String, Entry>{},
      observed = points.map((p) => p.$2 / 100).toList();
  for (final method in methods) {
    final entry = Entry();
    for (final parameter in parametersFor(method, s)) {
      final candidate = fitModel(
        method,
        parameter,
        points,
        s,
        mode,
        robust: false,
      );
      final score = method == 'spline'
          ? generalizedScore(observed, candidate.fitted, candidate.edf)
          : crossValidationScore(
              observed,
              validationPredictions(
                method,
                parameter,
                points,
                s,
                mode,
                points.length,
              ),
            );
      entry.candidates.add(Candidate(parameter, score, candidate.edf));
    }
    var best = -1;
    if (entry.candidates.isNotEmpty) {
      best = chooseCandidate(entry.candidates);
      entry.candidates[best].selected = true;
      entry.parameter = entry.candidates[best].parameter;
    } else {
      entry.parameter = method == 'linear' ? '-' : mode;
    }
    entry.model = fitModel(method, entry.parameter, points, s, mode);
    final direction = method == 'isotonic'
        ? (entry.model as IsotonicFit).direction
        : mode;
    if (method == 'isotonic') entry.parameter = direction;
    entry.loo = best >= 0 && method != 'spline'
        ? entry.candidates[best].score
        : crossValidationScore(
            observed,
            validationPredictions(
              method,
              entry.parameter,
              points,
              s,
              direction,
              points.length,
            ),
          );
    if (method == 'spline') entry.gcv = entry.candidates[best].score;
    entry.kfold = crossValidationScore(
      observed,
      validationPredictions(
        method,
        entry.parameter,
        points,
        s,
        direction,
        s.folds,
      ),
    );
    entries[method] = entry;
  }
  return entries;
}

class Diagnostics {
  final residuals = <double>[], acf = <double>[], quantiles = <double>[];
  late final double rss, edf, r2, dw, runZ;
  double df = double.nan, rse = double.nan, nonlinear = double.nan;
  int runs = 0, positive = 0, negative = 0, largest = 0, turning = 0;
  Diagnostics(
    String method,
    Fit model,
    List<double> observed,
    List<double> grid,
    double linearRSS,
  ) {
    final n = observed.length;
    for (var i = 0; i < n; i++) {
      residuals.add(observed[i] - model.fitted[i]);
    }
    rss = residualSquare(observed, model.fitted);
    edf = model.edf;
    final mean = orderedSum(observed) / n,
        tss = orderedSum(observed.map((y) => (y - mean) * (y - mean)));
    r2 = 1 - rss / tss;
    if (!edf.isNaN) {
      df = n - edf;
      rse = math.sqrt(rss / df);
      if (method != 'linear' && edf > 2)
        nonlinear = ((linearRSS - rss) / (edf - 2)) / (rss / df);
    }
    final emean = orderedSum(residuals) / n,
        centered = residuals.map((e) => e - emean).toList(),
        denominator = orderedSum(
          residuals.map((e) => (e - emean) * (e - emean)),
        );
    for (var lag = 1; lag <= 5; lag++) {
      var total = 0.0;
      for (var i = 0; i < n - lag; i++) {
        total += centered[i] * centered[i + lag];
      }
      acf.add(total / denominator);
    }
    var dwTotal = 0.0, previous = 0;
    for (var i = 0; i < n; i++) {
      final e = residuals[i];
      if (i > 0) {
        final delta = e - residuals[i - 1];
        dwTotal += delta * delta;
      }
      if (e.abs() > residuals[largest].abs()) largest = i;
      final sign = e > 0
          ? 1
          : e < 0
          ? -1
          : 0;
      if (sign == 1) positive++;
      if (sign == -1) negative++;
      if (sign != 0) {
        if (sign != previous) runs++;
        previous = sign;
      }
    }
    dw = dwTotal / rss;
    final count = positive + negative,
        product = 2 * positive * negative,
        mu = 1 + product / count,
        variance = product * (product - count) / (count * count * (count - 1));
    runZ = (runs - mu) / math.sqrt(variance);
    final ordered = [...residuals]..sort();
    for (var k = 0; k < 5; k++) {
      final j = (n - 1) * k ~/ 4, r = (n - 1) * k % 4;
      quantiles.add(
        ordered[j] + (r == 0 ? 0 : r / 4 * (ordered[j + 1] - ordered[j])),
      );
    }
    final defined = grid.where((v) => !v.isNaN).toList();
    previous = 0;
    for (var i = 1; i < defined.length; i++) {
      final diff = defined[i] - defined[i - 1];
      if (diff != 0) {
        final sign = diff > 0 ? 1 : -1;
        if (previous != 0 && sign != previous) turning++;
        previous = sign;
      }
    }
  }
}

class OutlierData {
  late final String method;
  final standardized = <int, double>{},
      cooks = <int, double>{},
      outliers = <int>[],
      influential = <int>[];
  OutlierData(
    Map<String, Entry> entries,
    List<String> ranking,
    double threshold,
  ) {
    method = ranking.firstWhere(
      (name) => entries[name]!.model.leverage != null,
    );
    final entry = entries[method]!, leverage = entries[method]!.model.leverage!;
    for (var i = 0; i < leverage.length; i++) {
      final lev = leverage[i];
      if (lev < 1) {
        final t =
            entry.stats.residuals[i] / (entry.stats.rse * math.sqrt(1 - lev));
        standardized[i] = t;
        cooks[i] = t * t * lev / ((1 - lev) * entry.model.edf);
        influential.add(i);
        if (t.abs() > threshold) outliers.add(i);
      }
    }
    outliers.sort((a, b) {
      final cmp = standardized[b]!.abs().compareTo(standardized[a]!.abs());
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    influential.sort((a, b) {
      final cmp = cooks[b]!.compareTo(cooks[a]!);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    if (influential.length > 3) influential.removeRange(3, influential.length);
  }
}

double standardError(Fit model, double rse, int position) =>
    rse * math.sqrt(orderedSum(model.weights(position)!.map((w) => w * w)));
typedef Band = (double, double, double, double);
List<Band> variabilityBands(Fit model, double rse, List<int> grid, double z) =>
    [
      for (final p in grid)
        (() {
          final value = model.estimate(p);
          if (value.isNaN) return (value, value, value, value);
          final se = standardError(model, rse, p);
          return (value, se, value - z * se, value + z * se);
        })(),
    ];
(double, int) bandSummary(
  Entry entry,
  List<int> positions,
  List<Band> bands,
  double z,
) {
  final errors = bands.where((b) => !b.$1.isNaN).map((b) => b.$2).toList(),
      rse = entry.stats.rse;
  var covered = 0;
  for (var i = 0; i < positions.length; i++) {
    final se = standardError(entry.model, rse, positions[i]);
    if (entry.stats.residuals[i].abs() <= z * math.sqrt(rse * rse + se * se))
      covered++;
  }
  return (orderedSum(errors) / errors.length, covered);
}

class Minstd {
  int state;
  Minstd(this.state);
  int index(int count) {
    state = state * 48271 % 2147483647;
    return state % count;
  }
}

List<Band> bootstrapIntervals(
  Entry entry,
  List<int> grid,
  int count,
  int trim,
  Minstd g,
) {
  final model = entry.model as SplineFit,
      residuals = entry.stats.residuals,
      mean = orderedSum(entry.stats.residuals) / entry.stats.residuals.length;
  final centered = residuals.map((v) => v - mean).toList(),
      estimates = List.generate(grid.length, (_) => <double>[]);
  for (var b = 0; b < count; b++) {
    final response = [
          for (final value in model.fitted)
            value + centered[g.index(centered.length)],
        ],
        fit = model.fitValues(response);
    for (var i = 0; i < grid.length; i++) {
      estimates[i].add(model.evaluateFit(fit, grid[i]));
    }
  }
  final result = <Band>[];
  for (var i = 0; i < grid.length; i++) {
    final values = estimates[i], average = orderedSum(estimates[i]) / count;
    final se = math.sqrt(
          orderedSum(values.map((v) => (v - average) * (v - average))) /
              (count - 1),
        ),
        ordered = [...values]..sort();
    result.add((
      model.estimate(grid[i]),
      se,
      ordered[trim],
      ordered[count - trim - 1],
    ));
  }
  return result;
}

class Analysis {
  final String name;
  final List<Point> points;
  late final List<int> grid;
  late final Map<String, Entry> entries;
  late final List<String> ranking;
  final agreement = <String, (int, double, double, int)>{};
  late final (double, int, double, int) slope;
  late final OutlierData outlier;
  final bands = <String, List<Band>>{},
      bandSummaries = <String, (double, int)>{};
  Analysis(
    Series series,
    Settings s,
    List<String> methods,
    String mode,
    Minstd g,
  ) : name = series.name,
      points = series.points {
    final (positions, values) = pointData(points);
    grid = [
      for (var k = 0; k < s.gridPoints; k++)
        positions.first +
            k * (positions.last - positions.first) ~/ (s.gridPoints - 1),
    ];
    entries = selectModels(points, s, methods, mode);
    final linearRSS = residualSquare(values, entries['linear']!.model.fitted);
    for (final name in methods) {
      final entry = entries[name]!;
      entry.gridValues = grid.map(entry.model.estimate).toList();
      entry.stats = Diagnostics(
        name,
        entry.model,
        values,
        entry.gridValues,
        linearRSS,
      );
    }
    ranking = [...methods]
      ..sort((a, b) {
        final cmp = entries[a]!.loo.compareTo(entries[b]!.loo);
        return cmp != 0
            ? cmp
            : methods.indexOf(a).compareTo(methods.indexOf(b));
      });
    final best = entries[ranking.first]!.gridValues;
    for (final name in methods) {
      if (name == ranking.first) continue;
      final own = entries[name]!.gridValues;
      var count = 0, position = 0, total = 0.0, maximum = -1.0;
      for (var i = 0; i < own.length; i++) {
        if (!own[i].isNaN && !best[i].isNaN) {
          final d = (own[i] - best[i]).abs();
          count++;
          total += d * d;
          if (d > maximum) {
            maximum = d;
            position = grid[i];
          }
        }
      }
      agreement[name] = (count, math.sqrt(total / count), maximum, position);
    }
    final spline = entries['spline']!.gridValues;
    var maximum = double.negativeInfinity,
        minimum = double.infinity,
        atMax = 0,
        atMin = 0;
    for (var k = 1; k < grid.length - 1; k++) {
      final sigma =
          (spline[k + 1] - spline[k - 1]) / ((grid[k + 1] - grid[k - 1]) / 100);
      if (sigma > maximum) {
        maximum = sigma;
        atMax = grid[k];
      }
      if (sigma < minimum) {
        minimum = sigma;
        atMin = grid[k];
      }
    }
    slope = (maximum, atMax, minimum, atMin);
    outlier = OutlierData(entries, ranking, s.threshold);
    for (final method in s.bandMethods) {
      final entry = entries[method]!;
      bands[method] = variabilityBands(
        entry.model,
        entry.stats.rse,
        grid,
        s.bandZ,
      );
      bandSummaries[method] = bandSummary(
        entry,
        positions,
        bands[method]!,
        s.bandZ,
      );
    }
    bands['spline_bootstrap'] = bootstrapIntervals(
      entries['spline']!,
      grid,
      s.bootstrap,
      s.trim,
      g,
    );
  }
}

String realPlaces(double value, int places) {
  if (value.isNaN) return 'NA';
  final text = value.toStringAsFixed(places);
  return text.startsWith('-') && RegExp(r'^-0\.0+$').hasMatch(text)
      ? text.substring(1)
      : text;
}

String real(double value) => realPlaces(value, 4);
String positionText(int value) =>
    '${value < 0 ? '-' : ''}${value.abs() ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';
String realList(List<double> values) => values.map(real).join(' ');
List<String> joinBlocks(List<List<String>> blocks) {
  final lines = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) lines.add('');
    lines.addAll(blocks[i]);
  }
  return lines;
}

void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
List<String> selectionLines(List<Analysis> analyses, List<String> methods) => [
  'series,method,parameter,score,edf,selected',
  for (final a in analyses)
    for (final method in methods)
      for (final c in a.entries[method]!.candidates)
        '${a.name},$method,${c.parameter},${real(c.score)},${real(c.edf)},${c.selected ? 1 : 0}',
];
List<String> fitLines(List<Analysis> analyses, List<String> methods) => [
  'series,x,${methods.join(',')}',
  for (final a in analyses)
    for (var i = 0; i < a.grid.length; i++)
      '${a.name},${positionText(a.grid[i])},${methods.map((method) => real(a.entries[method]!.gridValues[i])).join(',')}',
];
List<String> predictionLines(
  Map<String, Analysis> table,
  List<(String, int)> tests,
  List<String> methods,
) => [
  'series,x,${methods.join(',')}',
  for (final (name, position) in tests)
    '$name,${positionText(position)},${methods.map((method) => real(table[name]!.entries[method]!.model.estimate(position))).join(',')}',
];
List<String> bandLines(List<Analysis> analyses, Settings s) => [
  'series,method,x,fit,se,lower,upper',
  for (final a in analyses)
    for (final method in [...s.bandMethods, 'spline_bootstrap'])
      for (var i = 0; i < a.grid.length; i++)
        '${a.name},$method,${positionText(a.grid[i])},${[a.bands[method]![i].$1, a.bands[method]![i].$2, a.bands[method]![i].$3, a.bands[method]![i].$4].map(real).join(',')}',
];
List<String> methodDiagnosticLines(
  String method,
  Entry entry,
  List<Point> points,
) {
  final d = entry.stats;
  final lines = [
    'method $method parameter ${entry.parameter} loo ${real(entry.loo)}${method == 'spline' ? ' gcv ${real(entry.gcv)}' : ''}',
    '  rss ${real(d.rss)} edf ${real(d.edf)} df ${real(d.df)} rse ${real(d.rse)} r2 ${real(d.r2)} f_nonlinear ${real(d.nonlinear)}',
    '  acf ${realList(d.acf)} dw ${real(d.dw)}',
    '  runs ${d.runs} positive ${d.positive} negative ${d.negative} z ${real(d.runZ)}',
    '  max_residual ${real(d.residuals[d.largest])} at ${positionText(points[d.largest].$1)} turning ${d.turning}',
    '  quantiles ${realList(d.quantiles)}',
  ];
  final model = entry.model;
  if (model is LoessFit) {
    for (final (iteration, scale, zeroCount, change) in model.records) {
      lines.add(
        '  robust $iteration scale ${real(scale)} zero_weight $zeroCount max_change ${real(change)}',
      );
    }
    final zeros = [
      for (var i = 0; i < model.rho.length; i++)
        if (model.rho[i] == 0) positionText(points[i].$1),
    ];
    lines.add(
      '  zero_weight_points ${zeros.isEmpty ? 'none' : zeros.join(' ')}',
    );
  }
  return lines;
}

List<String> diagnosticsBlock(Analysis a, List<String> methods, Settings s) {
  final points = a.points,
      low = a.points.map((p) => p.$2).reduce(math.min),
      high = a.points.map((p) => p.$2).reduce(math.max);
  final lines = [
    'series ${a.name} n ${points.length} x ${positionText(points.first.$1)} ${positionText(points.last.$1)} y ${positionText(low)} ${positionText(high)}',
  ];
  for (final method in methods) {
    lines.addAll(methodDiagnosticLines(method, a.entries[method]!, points));
  }
  lines.add('ranking');
  for (var i = 0; i < a.ranking.length; i++) {
    final name = a.ranking[i], entry = a.entries[a.ranking[i]]!;
    lines.add('  ${i + 1} $name ${real(entry.loo)} kfold ${real(entry.kfold)}');
  }
  lines.add('agreement with ${a.ranking.first}');
  for (final name in methods) {
    if (name != a.ranking.first) {
      final (count, rms, maximum, position) = a.agreement[name]!;
      lines.add(
        '  $name points $count rms ${real(rms)} max ${real(maximum)} at ${positionText(position)}',
      );
    }
  }
  final (maximum, atMax, minimum, atMin) = a.slope;
  lines.add(
    'slope spline max ${real(maximum)} at ${positionText(atMax)} min ${real(minimum)} at ${positionText(atMin)}',
  );
  final o = a.outlier, entry = a.entries[a.outlier.method]!;
  lines.add(
    'outliers method ${o.method} threshold ${realPlaces(s.threshold, 2)}',
  );
  for (final i in o.outliers) {
    lines.add(
      '  x ${positionText(points[i].$1)} y ${positionText(points[i].$2)} fit ${real(entry.model.fitted[i])} residual ${real(entry.stats.residuals[i])} standardized ${real(o.standardized[i]!)}',
    );
  }
  if (o.outliers.isEmpty) lines.add('  none');
  lines.add('influence method ${o.method}');
  for (final i in o.influential) {
    lines.add(
      '  x ${positionText(points[i].$1)} lev ${real(entry.model.leverage![i])} cook ${real(o.cooks[i]!)}',
    );
  }
  lines.add('bands');
  for (final method in s.bandMethods) {
    final (mean, covered) = a.bandSummaries[method]!;
    lines.add(
      '  $method mean_se ${real(mean)} coverage $covered of ${points.length}',
    );
  }
  return lines;
}

List<String> isotonicBlock(Analysis a) {
  final entry = a.entries['isotonic']!,
      model = a.entries['isotonic']!.model as IsotonicFit;
  return [
    'series ${a.name} direction ${model.direction} mode ${model.mode}${model.mode == 'auto' ? ' rss_increasing ${real(model.rssIncreasing)} rss_decreasing ${real(model.rssDecreasing)}' : ''}',
    'blocks ${model.blocks.length} rss ${real(entry.stats.rss)} loo ${real(entry.loo)}',
    for (var i = 0; i < model.blocks.length; i++)
      'block ${i + 1} x ${positionText(model.positions[model.blocks[i].$1])} ${positionText(model.positions[model.blocks[i].$2])} count ${model.blocks[i].$4} value ${real(model.blocks[i].$3 / (100 * model.blocks[i].$4))}',
  ];
}

List<String> framed(List<List<String>> grid) {
  final border = '+${'-' * grid.first.length}+';
  return [border, for (final row in grid) '|${row.join()}|', border];
}

List<List<String>> emptyGrid(int width, int height) =>
    List.generate(height, (_) => List.filled(width, ' '));
List<String> histogramLines(Map<int, double> standardized) {
  final counts = List.filled(14, 0);
  for (final value in standardized.values) {
    final index = value < -3
        ? 0
        : value >= 3
        ? 13
        : 1 + ((value + 3) / 0.5).floor();
    counts[index]++;
  }
  return [
    for (var i = 0; i < 14; i++)
      '${i == 0 ? '-inf' : realPlaces(-3 + 0.5 * (i - 1), 2)} ${i == 13 ? 'inf' : realPlaces(-3 + 0.5 * i, 2)} ${counts[i]} |${'#' * counts[i]}',
  ];
}

List<String> plotBlock(Analysis a, Settings s) {
  final points = a.points,
      width = s.width,
      height = s.height,
      xa = a.points.first.$1,
      xb = a.points.last.$1,
      ya = a.points.map((p) => p.$2).reduce(math.min),
      yb = a.points.map((p) => p.$2).reduce(math.max);
  final columns = [
    for (final p in points)
      math.min(width - 1, width * (p.$1 - xa) ~/ (xb - xa)),
  ];
  var grid = emptyGrid(width, height);
  for (var i = 0; i < points.length; i++) {
    final row = math.min(height - 1, height * (yb - points[i].$2) ~/ (yb - ya));
    grid[row][columns[i]] = '.';
  }
  for (var number = 0; number < s.plotMethods.length; number++) {
    final model = a.entries[s.plotMethods[number]]!.model;
    for (var column = 0; column < width; column++) {
      final position = xa + (2 * column + 1) * (xb - xa) ~/ (2 * width);
      final value = model.estimate(position);
      if (value.isNaN) continue;
      final pi = height * (yb / 100 - value) / (yb / 100 - ya / 100),
          row = pi.floor().clamp(0, height - 1).toInt(),
          digit = '${number + 1}',
          old = grid[row][column];
      grid[row][column] = old == ' ' || old == '.' || old == digit
          ? digit
          : '*';
    }
  }
  final cells = grid.expand((row) => row).toList();
  final lines = [
    'plot ${a.name} size ${width}x$height x ${positionText(xa)} ${positionText(xb)} y ${positionText(ya)} ${positionText(yb)}',
    'legend . data ${[for (var i = 0; i < s.plotMethods.length; i++) '${i + 1} ${s.plotMethods[i]}'].join(' ')}',
    ...framed(grid),
    'cells data ${cells.where((c) => c == '.').length} curve ${cells.where((c) => RegExp(r'^[1-9]$').hasMatch(c)).length} overlap ${cells.where((c) => c == '*').length}',
  ];
  final method = a.ranking.first,
      residuals = a.entries[a.ranking.first]!.stats.residuals,
      limit = a.entries[a.ranking.first]!.stats.residuals
          .map((v) => v.abs())
          .reduce(math.max);
  grid = emptyGrid(width, height);
  grid[height ~/ 2] = List.filled(width, '-');
  for (var i = 0; i < residuals.length; i++) {
    final row = (height * ((limit - residuals[i]) / (2 * limit)))
        .floor()
        .clamp(0, height - 1)
        .toInt();
    grid[row][columns[i]] = 'o';
  }
  lines.addAll([
    '',
    'residuals ${a.name} method $method limit ${real(limit)}',
    ...framed(grid),
    '',
    'histogram ${a.name} method ${a.outlier.method}',
    ...histogramLines(a.outlier.standardized),
  ]);
  return lines;
}

void main() {
  final (series, tests, s) = readDataset();
  final methods = methodsInOrder(s),
      generator = Minstd(s.seed),
      analyses = <Analysis>[],
      table = <String, Analysis>{};
  for (var i = 0; i < series.length; i++) {
    final a = Analysis(series[i], s, methods, s.isotonic[i], generator);
    analyses.add(a);
    table[a.name] = a;
  }
  Directory('output').createSync(recursive: true);
  writeLines('selection.csv', selectionLines(analyses, methods));
  writeLines('fits.csv', fitLines(analyses, methods));
  writeLines('predictions.csv', predictionLines(table, tests, methods));
  writeLines('bands.csv', bandLines(analyses, s));
  writeLines(
    'diagnostics.txt',
    joinBlocks(analyses.map((a) => diagnosticsBlock(a, methods, s)).toList()),
  );
  writeLines('isotonic.txt', joinBlocks(analyses.map(isotonicBlock).toList()));
  writeLines(
    'plots.txt',
    joinBlocks(s.plotSeries.map((name) => plotBlock(table[name]!, s)).toList()),
  );
}
