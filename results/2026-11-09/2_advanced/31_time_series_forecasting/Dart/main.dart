import 'dart:io';
import 'dart:math' as math;
part 'series_io.dart';
part 'decomposition.dart';
part 'smoothing.dart';
part 'autoregression.dart';
part 'evaluation.dart';

const methods = [
  'naive',
  'snaive',
  'drift',
  'ses',
  'holt',
  'damped',
  'hw_add',
  'hw_mult',
  'decomp_add',
  'decomp_mult',
  'ar',
];
const accuracyFields = [
  'me',
  'mae',
  'rmse',
  'mape',
  'smape',
  'mase',
  'fva',
  'cv_rmse',
  'cover80',
  'cover95',
  'winkler80',
  'winkler95',
  'rank',
];
String line(List<Object> parts) => parts.join(' ');
String realList(Iterable<double> values) => values.map(real).join(' ');
double squaredTotal(List<double> values) =>
    total(values.map((value) => value * value));
double rmse(List<double> errors) =>
    math.sqrt(squaredTotal(errors) / errors.length);
List<String> smoothParameterNames(String name) => switch (name) {
  'ses' => ['alpha'],
  'holt' => ['alpha', 'beta'],
  'damped' => ['alpha', 'beta', 'phi'],
  'hw_add' || 'hw_mult' => ['alpha', 'beta', 'gamma'],
  _ => [],
};

class Model {
  final String name;
  final List<double> values;
  final int season;
  SmoothParameters parameters = SmoothParameters();
  List<SmoothState> states = [];
  List<double> residuals = [],
      seasonal = [],
      differenced = [],
      variances = [],
      aic = [],
      coefficients = [],
      correlations = [],
      partial = [];
  List<Model> members = [];
  double intercept = 0, slope = 0, average = 0, sigma2 = 0;
  String kind = '';
  int offset = 0, order = 0;
  Model(this.name, this.values, this.season);
  double decompositionPrediction(int t) {
    final base = intercept + slope * (t + 1), component = seasonal[t % season];
    return name == 'decomp_add' ? base + component : base * component;
  }
}

Model fit(String name, List<double> values, Settings settings) {
  final n = values.length,
      season = settings.integer('season'),
      model = Model(name, values, settings.integer('season'));
  switch (name) {
    case 'naive':
      model.residuals = [for (var t = 1; t < n; t++) values[t] - values[t - 1]];
    case 'snaive':
      model.residuals = [
        for (var t = season; t < n; t++) values[t] - values[t - season],
      ];
    case 'drift':
      model.slope = (values.last - values.first) / (n - 1);
      model.residuals = [
        for (var t = 1; t < n; t++) values[t] - values[t - 1] - model.slope,
      ];
    case 'ses' || 'holt' || 'damped' || 'hw_add' || 'hw_mult':
      final names = smoothParameterNames(name);
      var best = double.infinity;
      void visit(int index, SmoothParameters p) {
        if (index == names.length) {
          final (errors, states) = smoothRecurse(name, values, season, p);
          final score = squaredTotal(errors);
          if (score < best) {
            best = score;
            model.parameters = p;
            model.residuals = errors;
            model.states = states;
          }
          return;
        }
        for (final value in settings.reals(names[index])) {
          visit(index + 1, p.withValue(names[index], value));
        }
      }
      visit(0, SmoothParameters());
    case 'decomp_add' || 'decomp_mult':
      final decomposition = decompose(values, season),
          additive = name == 'decomp_add';
      final indices = additive
          ? decomposition.additive
          : decomposition.multiplicative;
      final adjusted = [
        for (var t = 0; t < n; t++)
          additive
              ? values[t] - indices[t % season]
              : values[t] / indices[t % season],
      ];
      (model.intercept, model.slope) = leastSquares(adjusted);
      model.seasonal = indices;
      model.residuals = [
        for (var t = 0; t < n; t++)
          values[t] - model.decompositionPrediction(t),
      ];
    case 'ar':
      var best = double.infinity;
      for (final kind in differenceKinds) {
        final (transformed, offset) = difference(values, season, kind);
        final (average, variance, _) = autocorrelation(transformed, 0);
        model.variances.add(variance);
        if (variance < best) {
          best = variance;
          model.kind = kind;
          model.differenced = transformed;
          model.offset = offset;
          model.average = average;
        }
      }
      final (average, variance, correlations) = autocorrelation(
        model.differenced,
        settings.integer('max_lag'),
      );
      final (coefficients, partial, variances) = durbinLevinson(correlations);
      model.average = average;
      model.correlations = correlations;
      model.partial = partial;
      best = double.infinity;
      for (var p = 0; p <= settings.integer('max_ar'); p++) {
        final aic =
            model.differenced.length * math.log(variance * variances[p]) +
            2 * p;
        model.aic.add(aic);
        if (aic < best) {
          best = aic;
          model.order = p;
        }
      }
      model.coefficients = coefficients[model.order];
      model.sigma2 = variance * variances[model.order];
      model.residuals = arResiduals(
        model.differenced,
        model.average,
        model.coefficients,
      );
  }
  return model;
}

Model combo(List<Model> members, List<double> values, int season) =>
    Model('combo', values, season)..members = members;
List<double> forecast(Model model, int origin, int steps) {
  final values = model.values, season = model.season;
  switch (model.name) {
    case 'combo':
      final predictions = model.members
          .map((member) => forecast(member, origin, steps))
          .toList();
      return [
        for (var i = 0; i < steps; i++)
          total(predictions.map((row) => row[i])) / predictions.length,
      ];
    case 'naive':
      return List.filled(steps, values[origin - 1]);
    case 'snaive':
      return [
        for (var i = 0; i < steps; i++) values[origin - season + i % season],
      ];
    case 'drift':
      final slope = (values[origin - 1] - values.first) / (origin - 1);
      return [
        for (var i = 0; i < steps; i++) values[origin - 1] + (i + 1) * slope,
      ];
    case 'ses' || 'holt' || 'damped' || 'hw_add' || 'hw_mult':
      return smoothForecast(
        model.name,
        model.states[origin],
        model.parameters,
        origin,
        steps,
        season,
      );
    case 'decomp_add' || 'decomp_mult':
      return [
        for (var i = 0; i < steps; i++)
          model.decompositionPrediction(origin + i),
      ];
    default:
      return arForecast(
        values,
        model.differenced,
        model.offset,
        model.kind,
        model.average,
        model.coefficients,
        origin,
        steps,
        season,
      );
  }
}

List<String> modelLines(Model model) {
  final common =
          'rmse ${real(rmse(model.residuals))} residuals ${model.residuals.length}',
      name = model.name;
  switch (name) {
    case 'naive' || 'snaive':
      return ['$name $common'];
    case 'drift':
      return ['drift slope ${real(model.slope)} $common'];
    case 'ses' || 'holt' || 'damped' || 'hw_add' || 'hw_mult':
      final state = model.states.last,
          parameters = smoothParameterNames(
            name,
          ).map((key) => '$key ${real(model.parameters.value(key))}').join(' ');
      final lines = [
        '$name $parameters $common level ${real(state.level)}${name == 'ses' ? '' : ' slope ${real(state.slope)}'}',
      ];
      if (state.seasonal != null)
        lines.add(
          '$name seasonal ${realList([for (var j = 0; j < model.season; j++) state.seasonal![(model.values.length + j) % model.season]])}',
        );
      return lines;
    case 'decomp_add' || 'decomp_mult':
      return [
        '$name intercept ${real(model.intercept)} slope ${real(model.slope)} $common',
        '$name seasonal ${realList(model.seasonal)}',
      ];
    default:
      return [
        'ar variance ${[for (var i = 0; i < differenceKinds.length; i++) '${differenceKinds[i]} ${real(model.variances[i])}'].join(' ')}',
        'ar difference ${model.kind} n ${model.differenced.length} mean ${real(model.average)} order ${model.order} sigma2 ${real(model.sigma2)} $common',
        'ar aic ${realList(model.aic)}',
        'ar coefficients ${model.coefficients.isEmpty ? 'none' : realList(model.coefficients)}',
      ];
  }
}

class CV {
  final List<int> counts;
  final List<double> sigma, mae;
  double rmseValue = 0;
  CV(int horizon)
    : counts = List.filled(horizon, 0),
      sigma = List.filled(horizon, 0),
      mae = List.filled(horizon, 0);
}

CV crossValidate(Model model, Settings settings) {
  final horizon = settings.integer('horizon'),
      result = CV(settings.integer('horizon')),
      squared = List.filled(settings.integer('horizon'), 0.0),
      absolute = List.filled(settings.integer('horizon'), 0.0);
  for (
    var origin = settings.integer('cv_start');
    origin < model.values.length;
    origin++
  ) {
    final predictions = forecast(
      model,
      origin,
      math.min(horizon, model.values.length - origin),
    );
    for (var i = 0; i < predictions.length; i++) {
      final error = model.values[origin + i] - predictions[i];
      result.counts[i]++;
      squared[i] += error * error;
      absolute[i] += error.abs();
    }
  }
  for (var i = 0; i < horizon; i++) {
    result.sigma[i] = math.sqrt(squared[i] / result.counts[i]);
    result.mae[i] = absolute[i] / result.counts[i];
  }
  var sum = 0.0, count = 0;
  for (var i = 0; i < settings.integer('holdout'); i++) {
    sum += squared[i];
    count += result.counts[i];
  }
  result.rmseValue = math.sqrt(sum / count);
  return result;
}

class Interval {
  final double forecast, lo80, hi80, lo95, hi95;
  Interval(this.forecast, this.lo80, this.hi80, this.lo95, this.hi95);
  String fields() => [forecast, lo80, hi80, lo95, hi95].map(real).join(',');
}

List<Interval> intervalRows(
  List<double> predicted,
  List<double> sigma,
  List<double> coefficients, [
  List<double>? multipliers,
]) => [
  for (var i = 0; i < predicted.length; i++)
    Interval(
      predicted[i] * (multipliers?[i] ?? 1),
      (predicted[i] - coefficients[0] * sigma[i]) * (multipliers?[i] ?? 1),
      (predicted[i] + coefficients[0] * sigma[i]) * (multipliers?[i] ?? 1),
      (predicted[i] - coefficients[1] * sigma[i]) * (multipliers?[i] ?? 1),
      (predicted[i] + coefficients[1] * sigma[i]) * (multipliers?[i] ?? 1),
    ),
];

class Lift {
  final String kind;
  final int occurrences;
  final double value;
  Lift(this.kind, this.occurrences, this.value);
}

class Analysis {
  final Series series;
  final Settings settings;
  late final List<double> values, corrected;
  late final int trainingCount;
  final future = <String>[],
      missing = <int>{},
      past = <int, String>{},
      outliers = <int, double>{},
      lifts = <Lift>[];
  late final Decomposition decomposition;
  late final double strengthTrend, strengthSeasonal;
  final models = <Model>[],
      cvs = <CV>[],
      members = <int>[],
      metrics = <Map<String, double>>[],
      intervals = <List<Interval>>[],
      finalFits = <Model>[];
  late final int best;
  late final Model finalModel;
  late final List<Interval> futureRows;
  Analysis(this.series, this.settings) {
    prepare();
    analyze();
  }
  String get bestName => models[best].name;
  void prepare() {
    final n = series.raw.length, season = settings.integer('season');
    trainingCount = n - settings.integer('holdout');
    values = List.filled(n, 0);
    for (var t = 0; t < n; t++) {
      final value = series.raw[t];
      if (value == null) {
        missing.add(t);
      } else {
        values[t] = value;
      }
    }
    for (var left = 0; left < n - 1;) {
      var right = left + 1;
      while (series.raw[right] == null) {
        right++;
      }
      for (var t = left + 1; t < right; t++) {
        values[t] =
            series.raw[left]! +
            (series.raw[right]! - series.raw[left]!) *
                (t - left) /
                (right - left);
      }
      left = right;
    }
    var period = series.periods.last;
    for (var i = 0; i < settings.integer('horizon'); i++) {
      period = nextMonth(period);
      future.add(period);
    }
    decomposition = decompose(values, season);
    final d = decomposition,
        residuals = <double>[],
        trendResiduals = <double>[],
        seasonResiduals = <double>[];
    for (final t in d.defined) {
      final r = d.residualAdd[t]!;
      residuals.add(r);
      trendResiduals.add(d.trend[t]! + r);
      seasonResiduals.add(d.additive[t % season] + r);
    }
    final average = mean(residuals),
        deviation = math.sqrt(sampleVariance(residuals)),
        groups = <String, List<int>>{};
    for (var t = 0; t < n; t++) {
      final kind = series.events[series.periods[t]];
      if (kind != null) {
        past[t] = kind;
        groups.putIfAbsent(kind, () => []).add(t);
      }
    }
    for (final t in d.defined) {
      if (!missing.contains(t) &&
          !past.containsKey(t) &&
          (d.residualAdd[t]! - average).abs() >
              settings.number('outlier') * deviation)
        outliers[t] = (d.residualAdd[t]! - average) / deviation;
    }
    for (final entry in groups.entries) {
      final ratios = entry.value
          .map((t) => values[t] / (d.trend[t]! + d.additive[t % season]))
          .toList();
      lifts.add(Lift(entry.key, ratios.length, mean(ratios)));
    }
    corrected = List<double>.of(values);
    for (var t = 0; t < n; t++) {
      if (past.containsKey(t) || outliers.containsKey(t))
        corrected[t] = d.trend[t]! + d.additive[t % season];
    }
    final vr = sampleVariance(residuals);
    strengthTrend = math.max(0.0, 1 - vr / sampleVariance(trendResiduals));
    strengthSeasonal = math.max(0.0, 1 - vr / sampleVariance(seasonResiduals));
  }

  void analyze() {
    final training = corrected.take(trainingCount).toList(),
        cvScores = <double>[];
    for (final name in methods) {
      final model = fit(name, training, settings);
      final cv = crossValidate(model, settings);
      models.add(model);
      cvs.add(cv);
      cvScores.add(cv.rmseValue);
    }
    final selected = rankValues(
      cvScores,
    ).take(settings.integer('combo')).toSet();
    for (var i = 0; i < models.length; i++) {
      if (selected.contains(i)) members.add(i);
    }
    final combined = combo(
      members.map((i) => models[i]).toList(),
      training,
      settings.integer('season'),
    );
    models.add(combined);
    cvs.add(crossValidate(combined, settings));
    final actual = values.sublist(trainingCount),
        scale = seasonalScale(training, settings.integer('season')),
        scores = <double>[];
    for (var i = 0; i < models.length; i++) {
      final predicted = forecast(models[i], training.length, actual.length),
          cv = cvs[i];
      final rows = intervalRows(
            predicted,
            cv.sigma,
            settings.reals('interval'),
          ),
          measures = accuracy(actual, predicted, scale);
      intervals.add(rows);
      measures['cv_rmse'] = cv.rmseValue;
      var cover80 = 0, cover95 = 0, w80 = 0.0, w95 = 0.0;
      for (var j = 0; j < actual.length; j++) {
        final value = actual[j], row = rows[j];
        if (row.lo80 <= value && value <= row.hi80) cover80++;
        if (row.lo95 <= value && value <= row.hi95) cover95++;
        w80 += winkler(value, row.lo80, row.hi80, 10);
        w95 += winkler(value, row.lo95, row.hi95, 40);
      }
      measures.addAll({
        'cover80': cover80.toDouble(),
        'cover95': cover95.toDouble(),
        'winkler80': w80 / actual.length,
        'winkler95': w95 / actual.length,
      });
      metrics.add(measures);
      scores.add(measures['rmse']!);
    }
    final naiveMAE = metrics.first['mae']!;
    for (final measures in metrics) {
      measures['fva'] = 100 * (naiveMAE - measures['mae']!) / naiveMAE;
    }
    final ranking = rankValues(scores);
    for (var i = 0; i < ranking.length; i++) {
      metrics[ranking[i]]['rank'] = (i + 1).toDouble();
    }
    best = ranking.first;
    for (final i in best == 11 ? members : [best]) {
      finalFits.add(fit(methods[i], corrected, settings));
    }
    finalModel = best == 11
        ? combo(finalFits, corrected, settings.integer('season'))
        : finalFits.single;
    final cv = crossValidate(finalModel, settings), multipliers = <double>[];
    for (final period in future) {
      final kind = series.events[period];
      multipliers.add(
        kind == null ? 1 : lifts.firstWhere((lift) => lift.kind == kind).value,
      );
    }
    futureRows = intervalRows(
      forecast(finalModel, values.length, settings.integer('horizon')),
      cv.sigma,
      settings.reals('interval'),
      multipliers,
    );
  }

  List<String> decompositionLines() {
    final d = decomposition,
        season = decomposition.additive.length,
        lines = <String>[];
    for (var t = 0; t < values.length; t++) {
      final flag =
          past[t] ??
          (missing.contains(t)
              ? 'missing'
              : outliers.containsKey(t)
              ? 'outlier'
              : 'ok');
      lines.add(
        [
          series.name,
          series.periods[t],
          real(values[t]),
          real(corrected[t]),
          real(d.trend[t]),
          real(d.additive[t % season]),
          real(d.residualAdd[t]),
          real(d.multiplicative[t % season]),
          real(d.residualMult[t]),
          flag,
        ].join(','),
      );
    }
    return lines;
  }

  List<String> fittedLines() {
    final lines = [
      'series ${series.name}',
      'data observations ${values.length} train $trainingCount holdout ${settings.integer('holdout')} missing ${missing.length} outliers ${outliers.length} events ${past.length}',
    ];
    for (final lift in lifts) {
      lines.add(
        'event ${lift.kind} occurrences ${lift.occurrences} lift ${real(lift.value)}',
      );
    }
    for (var t = 0; t < values.length; t++) {
      final score = outliers[t];
      if (score != null)
        lines.add(
          'outlier ${series.periods[t]} value ${real(values[t])} expected ${real(corrected[t])} score ${real(score)}',
        );
    }
    lines.add(
      'strength trend ${real(strengthTrend)} seasonal ${real(strengthSeasonal)}',
    );
    for (final model in models.take(11)) {
      lines.addAll(modelLines(model));
    }
    lines.addAll([
      'combo members ${members.map((i) => methods[i]).join(' ')}',
      'best $bestName rmse ${real(metrics[best]['rmse'])}',
    ]);
    for (final model in finalFits) {
      lines.addAll(modelLines(model).map((text) => 'final $text'));
    }
    return lines;
  }

  List<String> forecastLines() {
    final lines = <String>[];
    for (var i = 0; i < models.length; i++) {
      for (var j = 0; j < intervals[i].length; j++) {
        final t = trainingCount + j;
        lines.add(
          '${series.name},holdout,${models[i].name},${series.periods[t]},${series.raw[t]!.toInt()},${intervals[i][j].fields()}',
        );
      }
    }
    for (var i = 0; i < futureRows.length; i++) {
      lines.add(
        '${series.name},future,$bestName,${future[i]},NA,${futureRows[i].fields()}',
      );
    }
    return lines;
  }

  List<String> accuracyLines() => [
    for (var i = 0; i < models.length; i++)
      [
        series.name,
        models[i].name,
        for (final key in accuracyFields)
          ['cover80', 'cover95', 'rank'].contains(key)
              ? '${metrics[i][key]!.toInt()}'
              : real(metrics[i][key]),
      ].join(','),
  ];
  List<String> cvLines() => [
    for (var i = 0; i < models.length; i++)
      for (var j = 0; j < cvs[i].counts.length; j++)
        '${series.name},${models[i].name},${j + 1},${cvs[i].counts[j]},${real(cvs[i].mae[j])},${real(cvs[i].sigma[j])}',
  ];
  List<String> correlogramLines() {
    final ar = models[10],
        band = 2 / math.sqrt(models[10].differenced.length),
        lines = <String>[];
    lines.add(
      'series ${series.name} difference ${ar.kind} n ${ar.differenced.length} band ${real(band)}',
    );
    for (final (label, sequence) in [
      ('acf', ar.correlations),
      ('pacf', ar.partial),
    ]) {
      for (var lag = 1; lag < sequence.length; lag++) {
        final value = sequence[lag];
        lines.add(
          '$label ${lag.toString().padLeft(2)} ${real(value).padLeft(7)} [${correlationBar(value, band)}]${value.abs() > band ? ' *' : ''}',
        );
      }
    }
    final lags = settings.fields['ljung_box']!.map(int.parse).toList();
    for (final model in models.take(11)) {
      final errors = model.residuals,
          n = model.residuals.length,
          average = mean(model.residuals);
      var squared = 0.0, m3 = 0.0, m4 = 0.0, differences = 0.0;
      for (var i = 0; i < n; i++) {
        final difference = errors[i] - average;
        squared += difference * difference;
        m3 += difference * difference * difference;
        m4 += difference * difference * difference * difference;
        if (i > 0) {
          final delta = errors[i] - errors[i - 1];
          differences += delta * delta;
        }
      }
      final m2 = squared / n;
      m3 /= n;
      m4 /= n;
      final sd = math.sqrt(squared / (n - 1)),
          dw = differences / squaredTotal(errors),
          skewness = m3 / (m2 * math.sqrt(m2)),
          kurtosis = m4 / (m2 * m2) - 3;
      final jb = n / 6 * (skewness * skewness + kurtosis * kurtosis / 4);
      lines.add(
        'residuals ${model.name} n $n mean ${real(average)} sd ${real(sd)} dw ${real(dw)} skewness ${real(skewness)} kurtosis ${real(kurtosis)} jb ${real(jb)}',
      );
      lines.add(
        'ljung_box ${model.name} ${ljungBox(errors, lags).map((result) => 'lag ${result.$1} q ${real(result.$2)} p ${real(result.$3)}').join(' ')}',
      );
    }
    return lines;
  }

  List<String> chartLines() {
    final rows = [...intervals[best], ...futureRows],
        periods = [...series.periods.skip(trainingCount), ...future],
        actual = values.sublist(trainingCount);
    var low = double.infinity, high = double.negativeInfinity;
    for (final row in rows) {
      low = math.min(low, row.lo95);
      high = math.max(high, row.hi95);
    }
    for (final value in actual) {
      low = math.min(low, value);
      high = math.max(high, value);
    }
    final lines = [
      'chart ${series.name} method $bestName',
      'scale low ${real(low)} high ${real(high)}',
    ];
    for (var i = 0; i < rows.length; i++) {
      lines.add(
        '${periods[i]} |${chartRow(rows[i], i < actual.length ? actual[i] : null, low, high)}|',
      );
    }
    final peak = decomposition.multiplicative
        .map((value) => (value - 1).abs())
        .reduce(math.max);
    lines.add('profile peak ${real(peak)}');
    for (var j = 0; j < decomposition.multiplicative.length; j++) {
      final value = decomposition.multiplicative[j],
          width =
              ((decomposition.multiplicative[j] - 1).abs() / peak * 30 + 0.5)
                  .floor(),
          cells = List.filled(61, ' ');
      cells[30] = '|';
      if (value > 1) {
        for (var i = 31; i < 31 + width; i++) {
          cells[i] = '#';
        }
      } else if (value < 1) {
        for (var i = 30 - width; i < 30; i++) {
          cells[i] = '#';
        }
      }
      lines.add(
        'season ${(j + 1).toString().padLeft(2)} ${real(value)} [${cells.join()}]',
      );
    }
    return lines;
  }

  List<String> planLines() {
    final policy = series.policy,
        protection = series.policy.lead + series.policy.review,
        demands = futureRows.map((row) => row.forecast).toList(),
        errors = <double>[];
    for (
      var origin = settings.integer('cv_start');
      origin <= corrected.length - protection;
      origin++
    ) {
      final predicted = forecast(finalModel, origin, protection);
      var sum = 0.0;
      for (var i = 0; i < predicted.length; i++) {
        sum += corrected[origin + i] - predicted[i];
      }
      errors.add(sum);
    }
    final safety = policy.service * rmse(errors);
    final lines = [
          'series ${series.name} method $bestName',
          'policy on_hand ${policy.onHand} lead_time ${policy.lead} review ${policy.review} service ${real(policy.service)} safety_stock ${real(safety)}',
        ],
        reviews = <int>{},
        receipts = <int, int>{};
    var end = 0;
    for (var k = 1; k - 1 + protection <= demands.length; k += policy.review) {
      reviews.add(k);
      end = k - 1 + protection;
    }
    var onHand = policy.onHand.toDouble(),
        outstanding = 0,
        orders = 0,
        ordered = 0,
        short = 0,
        lowest = double.infinity,
        totalStock = 0.0;
    for (var k = 1; k <= end; k++) {
      final receipt = receipts[k] ?? 0;
      onHand += receipt;
      outstanding -= receipt;
      final period = future[k - 1];
      if (reviews.contains(k)) {
        final position = onHand + outstanding,
            target = total(demands.sublist(k - 1, k - 1 + protection)) + safety;
        final quantity = math.max(0, (target - position).ceil());
        if (quantity > 0) {
          orders++;
          ordered += quantity;
          outstanding += quantity;
          receipts[k + policy.lead] = quantity;
        }
        lines.add(
          'review $period position ${real(position)} target ${real(target)} order $quantity',
        );
      }
      onHand -= demands[k - 1];
      final status = onHand < 0
          ? 'short'
          : onHand < safety
          ? 'low'
          : 'ok';
      if (status == 'short') short++;
      lowest = math.min(lowest, onHand);
      totalStock += onHand;
      lines.add(
        'period $period demand ${real(demands[k - 1])} receipt $receipt on_hand ${real(onHand)} status $status',
      );
    }
    lines.add(
      'summary orders $orders ordered $ordered short_periods $short lowest ${real(lowest)} average ${real(totalStock / end)}',
    );
    final years = <String, Year>{};
    void add(String period, double value, bool isFuture) {
      final year = years.putIfAbsent(period.substring(0, 4), Year.new);
      if (isFuture) {
        year.forecastMonths++;
        year.forecast += value;
      } else {
        year.actualMonths++;
        year.actual += value;
      }
    }

    for (var i = 0; i < values.length; i++) {
      add(series.periods[i], values[i], false);
    }
    for (var i = 0; i < future.length; i++) {
      add(future[i], demands[i], true);
    }
    Year? previous;
    for (final name in years.keys.toList()..sort()) {
      final year = years[name]!,
          sum = years[name]!.actual + years[name]!.forecast;
      double? growth;
      if (previous != null &&
          year.actualMonths + year.forecastMonths == 12 &&
          previous.actualMonths + previous.forecastMonths == 12) {
        final before = previous.actual + previous.forecast;
        growth = 100 * (sum - before) / before;
      }
      lines.add(
        'year $name actual_months ${year.actualMonths} actual ${real(year.actual)} forecast_months ${year.forecastMonths} forecast ${real(year.forecast)} total ${real(sum)} growth ${real(growth)}',
      );
      previous = year;
    }
    return lines;
  }
}

class Year {
  int actualMonths = 0, forecastMonths = 0;
  double actual = 0, forecast = 0;
}

String correlationBar(double value, double band) {
  final width = (value.abs() * 20 + 0.5).floor(),
      threshold = (band * 20 + 0.5).floor(),
      cells = List.filled(41, ' ');
  cells[20 - threshold] = ':';
  cells[20 + threshold] = ':';
  cells[20] = '|';
  if (value > 0) {
    for (var i = 21; i < 21 + width; i++) {
      cells[i] = '#';
    }
  } else if (value < 0) {
    for (var i = 20 - width; i < 20; i++) {
      cells[i] = '#';
    }
  }
  return cells.join();
}

String chartRow(Interval row, double? actual, double low, double high) {
  int column(double value) => ((value - low) / (high - low) * 60 + 0.5).floor();
  final cells = List.filled(61, ' ');
  for (var i = column(row.lo95); i <= column(row.hi95); i++) {
    cells[i] = '-';
  }
  for (var i = column(row.lo80); i <= column(row.hi80); i++) {
    cells[i] = '=';
  }
  cells[column(row.forecast)] = 'o';
  if (actual != null) cells[column(actual)] = '*';
  return cells.join();
}

void main() {
  final (series, settings) = readInputs();
  final decomposition = [
        'series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag',
      ],
      models = <String>[],
      forecasts = [
        'series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95',
      ],
      accuracies = ['series,method,${accuracyFields.join(',')}'],
      cv = ['series,method,step,origins,mae,rmse'],
      correlogram = <String>[],
      chart = <String>[],
      plan = <String>[];
  for (final record in series) {
    final analysis = Analysis(record, settings);
    decomposition.addAll(analysis.decompositionLines());
    models.addAll(analysis.fittedLines());
    forecasts.addAll(analysis.forecastLines());
    accuracies.addAll(analysis.accuracyLines());
    cv.addAll(analysis.cvLines());
    correlogram.addAll(analysis.correlogramLines());
    chart.addAll(analysis.chartLines());
    plan.addAll(analysis.planLines());
  }
  writeLines('decomposition.csv', decomposition);
  writeLines('models.txt', models);
  writeLines('forecasts.csv', forecasts);
  writeLines('accuracy.csv', accuracies);
  writeLines('cv.csv', cv);
  writeLines('correlogram.txt', correlogram);
  writeLines('chart.txt', chart);
  writeLines('plan.txt', plan);
}
