part of 'main.dart';

double total(Iterable<double> values) {
  var result = 0.0;
  for (final value in values) {
    result += value;
  }
  return result;
}

double mean(List<double> values) => total(values) / values.length;
double sampleVariance(List<double> values) {
  final average = mean(values);
  return total(values.map((value) => (value - average) * (value - average))) /
      (values.length - 1);
}

class Decomposition {
  final List<double?> trend, residualAdd, residualMult;
  final additive = <double>[], multiplicative = <double>[], defined = <int>[];
  Decomposition(int count)
    : trend = List.filled(count, null),
      residualAdd = List.filled(count, null),
      residualMult = List.filled(count, null);
}

Decomposition decompose(List<double> values, int season) {
  final n = values.length,
      half = season ~/ 2,
      result = Decomposition(values.length);
  for (var t = half; t < n - half; t++) {
    result.defined.add(t);
    var value = 0.5 * values[t - half];
    for (var i = t - half + 1; i < t + half; i++) {
      value += values[i];
    }
    value += 0.5 * values[t + half];
    result.trend[t] = value / season;
  }
  for (var j = 0; j < season; j++) {
    final times = result.defined.where((t) => t % season == j).toList();
    result.additive.add(
      mean(times.map((t) => values[t] - result.trend[t]!).toList()),
    );
    result.multiplicative.add(
      mean(times.map((t) => values[t] / result.trend[t]!).toList()),
    );
  }
  final averageAdd = mean(result.additive),
      averageMult = mean(result.multiplicative);
  for (var j = 0; j < season; j++) {
    result.additive[j] -= averageAdd;
    result.multiplicative[j] /= averageMult;
  }
  for (final t in result.defined) {
    result.residualAdd[t] =
        values[t] - result.trend[t]! - result.additive[t % season];
    result.residualMult[t] =
        values[t] / (result.trend[t]! * result.multiplicative[t % season]);
  }
  return result;
}

(double, double) leastSquares(List<double> values) {
  final center = (values.length + 1) / 2, average = mean(values);
  var numerator = 0.0, denominator = 0.0;
  for (var t = 0; t < values.length; t++) {
    final u = t + 1 - center;
    numerator += u * (values[t] - average);
    denominator += u * u;
  }
  final slope = numerator / denominator;
  return (average - slope * center, slope);
}
