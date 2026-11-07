part of 'main.dart';

class Optimizer {
  final RunConfig config;
  final List<double> m, v;
  double pi1 = 1, pi2 = 1;
  Optimizer(this.config, int n) : m = List.filled(n, 0), v = List.filled(n, 0);
  void update(List<double> theta, List<double> g, double eta) {
    final c = config;
    if (c.optimizer == 'ADAM') {
      pi1 *= c.beta1;
      pi2 *= c.beta2;
    }
    for (var p = 0; p < g.length; p++) {
      final value = g[p];
      switch (c.optimizer) {
        case 'SGD':
          theta[p] = theta[p] - eta * value;
        case 'MOMENTUM':
          v[p] = c.mu * v[p] + value;
          theta[p] = theta[p] - eta * v[p];
        case 'ADAM':
          m[p] = c.beta1 * m[p] + (1 - c.beta1) * value;
          v[p] = c.beta2 * v[p] + (1 - c.beta2) * value * value;
          final mh = m[p] / (1 - pi1), vh = v[p] / (1 - pi2);
          theta[p] = theta[p] - eta * mh / (sqrt(vh) + c.epsilon);
      }
    }
  }
}

double learningRate(RunConfig config, Params params, int epoch) {
  var eta = config.eta;
  for (var i = 0; i < (epoch - 1) ~/ params.step; i++) {
    eta *= params.gamma;
  }
  return eta;
}
