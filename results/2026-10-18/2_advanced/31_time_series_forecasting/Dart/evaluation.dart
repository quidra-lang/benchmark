part of 'main.dart';

double seasonalScale(List<double> values, int season) =>
    total([
      for (var t = season; t < values.length; t++)
        (values[t] - values[t - season]).abs(),
    ]) /
    (values.length - season);
Map<String, double> accuracy(
  List<double> actual,
  List<double> predicted,
  double scale,
) {
  var me = 0.0, absolute = 0.0, squares = 0.0, mape = 0.0, smape = 0.0;
  for (var i = 0; i < actual.length; i++) {
    final a = actual[i], f = predicted[i], error = actual[i] - predicted[i];
    me += error;
    absolute += error.abs();
    squares += error * error;
    mape += error.abs() / a;
    smape += 2 * error.abs() / (a.abs() + f.abs());
  }
  final n = actual.length, mae = absolute / actual.length;
  return {
    'me': me / n,
    'mae': mae,
    'rmse': math.sqrt(squares / n),
    'mape': 100 * mape / n,
    'smape': 100 * smape / n,
    'mase': mae / scale,
  };
}

double winkler(double actual, double low, double high, double multiplier) =>
    actual < low
    ? high - low + multiplier * (low - actual)
    : actual > high
    ? high - low + multiplier * (actual - high)
    : high - low;
List<int> rankValues(List<double> values) =>
    List.generate(values.length, (i) => i)..sort((a, b) {
      final order = values[a].compareTo(values[b]);
      return order == 0 ? a.compareTo(b) : order;
    });
