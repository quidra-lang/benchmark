part of 'main.dart';

List<double> rk4(Model model, List<double> y, double multiplier) {
  const h = .25;
  final k1 = model.rate(y, multiplier), state = List.filled(y.length, 0.0);
  for (var i = 0; i < y.length; i++) {
    state[i] = y[i] + (h / 2) * k1[i];
  }
  final k2 = model.rate(state, multiplier);
  for (var i = 0; i < y.length; i++) {
    state[i] = y[i] + (h / 2) * k2[i];
  }
  final k3 = model.rate(state, multiplier);
  for (var i = 0; i < y.length; i++) {
    state[i] = y[i] + h * k3[i];
  }
  final k4 = model.rate(state, multiplier);
  for (var i = 0; i < y.length; i++) {
    state[i] = y[i] + (h / 6) * (((k1[i] + 2 * k2[i]) + 2 * k3[i]) + k4[i]);
  }
  return state;
}

List<List<double>> simulate(
  Model model,
  List<double> start,
  List<double> multipliers,
) {
  var y = List<double>.of(start);
  final out = <List<double>>[], inflows = model.inflowIndices;
  for (final m in multipliers) {
    for (final i in inflows) {
      y[i] = 0;
    }
    for (var step = 0; step < 4; step++) {
      y = rk4(model, y, m);
    }
    out.add(List.of(y));
  }
  return out;
}
