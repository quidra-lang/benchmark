part of 'main.dart';

class IMM {
  final List<State> states;
  final List<double> mu;
  IMM(Point z, Params p)
    : states = [initialize('CV', z, p), initialize('CV', z, p)],
      mu = List.of(p.immInitial);
  List<double> estimate() =>
      List.generate(4, (r) => mu[0] * states[0].x[r] + mu[1] * states[1].x[r]);
  void step(double t, Point? z, Params p) {
    final c = List.generate(
          2,
          (j) => p.immTransition[0][j] * mu[0] + p.immTransition[1][j] * mu[1],
        ),
        mixed = <State>[];
    for (var j = 0; j < 2; j++) {
      final weights = [
            p.immTransition[0][j] * mu[0] / c[j],
            p.immTransition[1][j] * mu[1] / c[j],
          ],
          x = List.generate(
            4,
            (r) => weights[0] * states[0].x[r] + weights[1] * states[1].x[r],
          ),
          cov = zeros(4, 4);
      for (var r = 0; r < 4; r++) {
        for (var s = 0; s < 4; s++) {
          cov[r][s] =
              weights[0] *
                  (states[0].p[r][s] +
                      (states[0].x[r] - x[r]) * (states[0].x[s] - x[s])) +
              weights[1] *
                  (states[1].p[r][s] +
                      (states[1].x[r] - x[r]) * (states[1].x[s] - x[s]));
        }
      }
      mixed.add(State(x, cov));
    }
    final likelihood = [1.0, 1.0];
    for (var j = 0; j < 2; j++) {
      var (state, _) = predict(mixed[j], 'CV', t, p.immQ[j]);
      if (z != null) {
        final (next, v, _) = update(state, z, p.sigma);
        state = next;
        likelihood[j] =
            exp(-v.distance / 2) / (2 * pi * sqrt(determinant(v.s)));
      }
      states[j] = state;
    }
    final den = likelihood[0] * c[0] + likelihood[1] * c[1];
    for (var j = 0; j < 2; j++) {
      mu[j] = likelihood[j] * c[j] / den;
    }
  }
}
