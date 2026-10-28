part of 'main.dart';

class Extremum {
  final int minute;
  final double mu, height;
  final bool high;
  String label = '';
  Extremum(this.minute, this.mu, this.height, this.high);
}

double predict(Model model, List<Constituent> c, double t) {
  var h = model.coefficients[0];
  for (var k = 0; k < model.selected.length; k++) {
    final a = angle(c[model.selected[k]].speed, t);
    h +=
        model.coefficients[2 * k + 1] * cos(a) +
        model.coefficients[2 * k + 2] * sin(a);
  }
  return h;
}

List<Extremum> extrema(Model model, List<Constituent> c, Settings p) {
  final n = p.hours * 60 ~/ p.grid,
      y = [
        for (var j = 0; j <= p.hours * 60 ~/ p.grid; j++)
          predict(model, c, (60 * p.start + j * p.grid) / 60),
      ];
  final a = <Extremum>[];
  for (var j = 1; j < n; j++) {
    final high = y[j - 1] < y[j] && y[j] > y[j + 1],
        low = y[j - 1] > y[j] && y[j] < y[j + 1];
    if (high || low) {
      final delta =
          (y[j - 1] - y[j + 1]) / (2 * (y[j - 1] - 2 * y[j] + y[j + 1]));
      final mu = 60 * p.start + j * p.grid + delta * p.grid,
          height = y[j] - (y[j - 1] - y[j + 1]) * delta / 4;
      a.add(Extremum((mu + 0.5).floor(), mu, height, high));
    }
  }
  return a;
}
