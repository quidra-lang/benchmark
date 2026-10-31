part of 'main.dart';

const differenceKinds = ['none', 'first', 'seasonal', 'both'];
(List<double>, int) difference(List<double> values, int season, String kind) {
  final offset = switch (kind) {
    'first' => 1,
    'seasonal' => season,
    'both' => season + 1,
    _ => 0,
  };
  return (
    [
      for (var t = offset; t < values.length; t++)
        switch (kind) {
          'first' => values[t] - values[t - 1],
          'seasonal' => values[t] - values[t - season],
          'both' =>
            (values[t] - values[t - 1]) -
                (values[t - season] - values[t - season - 1]),
          _ => values[t],
        },
    ],
    offset,
  );
}

(double, double, List<double>) autocorrelation(
  List<double> values,
  int maxLag,
) {
  final average = mean(values);
  final centered = values.map((value) => value - average).toList();
  final variance =
          total(centered.map((value) => value * value)) / values.length,
      correlations = <double>[1];
  for (var lag = 1; lag <= maxLag; lag++) {
    var numerator = 0.0;
    for (var i = 0; i < values.length - lag; i++) {
      numerator += centered[i] * centered[i + lag];
    }
    correlations.add(numerator / values.length / variance);
  }
  return (average, variance, correlations);
}

(List<List<double>>, List<double>, List<double>) durbinLevinson(
  List<double> r,
) {
  final coefficients = <List<double>>[[]],
      partial = <double>[0],
      variances = <double>[1];
  for (var order = 1; order < r.length; order++) {
    final previous = coefficients.last;
    var correction = 0.0;
    for (var j = 1; j < order; j++) {
      correction += previous[j - 1] * r[order - j];
    }
    final theta = (r[order] - correction) / variances.last;
    coefficients.add([
      for (var j = 1; j < order; j++)
        previous[j - 1] - theta * previous[order - j - 1],
      theta,
    ]);
    partial.add(theta);
    variances.add(variances.last * (1 - theta * theta));
  }
  return (coefficients, partial, variances);
}

List<double> arResiduals(
  List<double> values,
  double average,
  List<double> coefficients,
) {
  final errors = <double>[];
  for (var i = coefficients.length; i < values.length; i++) {
    var correction = 0.0;
    for (var j = 0; j < coefficients.length; j++) {
      correction += coefficients[j] * (values[i - j - 1] - average);
    }
    errors.add(values[i] - average - correction);
  }
  return errors;
}

List<double> arForecast(
  List<double> values,
  List<double> transformedValues,
  int offset,
  String kind,
  double average,
  List<double> coefficients,
  int origin,
  int steps,
  int season,
) {
  final transformed = transformedValues.take(origin - offset).toList(),
      extended = values.take(origin).toList(),
      result = <double>[];
  for (var k = 0; k < steps; k++) {
    var correction = 0.0;
    for (var j = 0; j < coefficients.length; j++) {
      correction +=
          coefficients[j] * (transformed[transformed.length - j - 1] - average);
    }
    var predicted = average + correction;
    transformed.add(predicted);
    final n = extended.length;
    predicted = switch (kind) {
      'first' => predicted + extended[n - 1],
      'seasonal' => predicted + extended[n - season],
      'both' =>
        predicted +
            extended[n - 1] +
            extended[n - season] -
            extended[n - season - 1],
      _ => predicted,
    };
    extended.add(predicted);
    result.add(predicted);
  }
  return result;
}

List<(int, double, double)> ljungBox(List<double> errors, List<int> lags) {
  final (_, _, r) = autocorrelation(errors, lags.reduce(math.max));
  final n = errors.length, result = <(int, double, double)>[];
  for (final lag in lags) {
    var sum = 0.0;
    for (var k = 1; k <= lag; k++) {
      sum += r[k] * r[k] / (n - k);
    }
    final q = n * (n + 2) * sum;
    final x = q / 2;
    var term = 1.0, terms = 1.0;
    for (var i = 1; i < lag ~/ 2; i++) {
      term = term * x / i;
      terms += term;
    }
    result.add((lag, q, math.exp(-x) * terms));
  }
  return result;
}
