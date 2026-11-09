part of 'main.dart';

class Model {
  final String kind;
  final double beta, gamma, sigma, n, fatality;
  final List<Group> groups;
  final List<List<double>> w;
  Model(
    this.kind,
    this.beta,
    this.gamma,
    this.sigma,
    this.n,
    this.fatality,
    this.groups,
    this.w,
  );
  List<double> rate(List<double> y, double multiplier) {
    switch (kind) {
      case 'generation':
        final e = y[0], i = y[1];
        return [-sigma * e, sigma * e - gamma * i, gamma * i];
      case 'sir':
        final s = y[0], i = y[1], f = beta * multiplier * s * i / n;
        return [-f, f - gamma * i, gamma * i, f];
      case 'age':
        final out = List.filled(y.length, 0.0);
        for (var g = 0; g < groups.length; g++) {
          final group = groups[g];
          var pressure = 0.0;
          for (var h = 0; h < groups.length; h++) {
            pressure += w[g][h] * y[6 * h + 2] / groups[h].population;
          }
          final lambda = beta * multiplier * pressure,
              offset = 6 * g,
              s = y[offset],
              e = y[offset + 1],
              i = y[offset + 2],
              f = lambda * s;
          out[offset] = -f;
          out[offset + 1] = f - sigma * e;
          out[offset + 2] = sigma * e - gamma * i;
          out[offset + 3] = (1 - group.fatality) * gamma * i;
          out[offset + 4] = group.fatality * gamma * i;
          out[offset + 5] = sigma * e;
        }
        return out;
      default:
        final s = y[0], e = y[1], i = y[2], f = beta * multiplier * s * i / n;
        return [
          -f,
          f - sigma * e,
          sigma * e - gamma * i,
          (1 - fatality) * gamma * i,
          fatality * gamma * i,
          sigma * e,
        ];
    }
  }

  List<int> get inflowIndices => kind == 'generation'
      ? [2]
      : kind == 'sir'
      ? [3]
      : kind == 'age'
      ? [for (var g = 0; g < groups.length; g++) 6 * g + 5]
      : [5];
}

List<double> initial(Data data, String kind) {
  final p = data.params, n = data.population.toDouble();
  switch (kind) {
    case 'generation':
      return [1, 0, 0];
    case 'sir':
      return [n - p.e0 - p.i0, p.e0 + p.i0, 0, 0];
    case 'age':
      final out = <double>[];
      for (final g in data.groups) {
        final ng = g.population.toDouble(),
            e = p.e0 * ng / n,
            i = p.i0 * ng / n;
        out.addAll([ng - e - i, e, i, 0, 0, 0]);
      }
      return out;
    default:
      return [n - p.e0 - p.i0, p.e0, p.i0, 0, 0, 0];
  }
}
