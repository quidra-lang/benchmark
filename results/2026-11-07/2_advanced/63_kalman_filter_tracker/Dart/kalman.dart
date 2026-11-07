part of 'main.dart';

class State {
  final List<double> x;
  final Matrix p;
  State(this.x, this.p);
}

class Innovation {
  final List<double> nu;
  final Matrix s, inverse;
  final double distance;
  Innovation(this.nu, this.s, this.inverse, this.distance);
}

Matrix transition(String kind, double t) {
  final n = kind == 'CA' ? 6 : 4, f = identity(kind == 'CA' ? 6 : 4);
  f[0][2] = t;
  f[1][3] = t;
  if (n == 6) {
    f[0][4] = t * t / 2;
    f[1][5] = t * t / 2;
    f[2][4] = t;
    f[3][5] = t;
  }
  return f;
}

Matrix processNoise(String kind, double t, double q) {
  final n = kind == 'CA' ? 6 : 4,
      out = zeros(kind == 'CA' ? 6 : 4, kind == 'CA' ? 6 : 4);
  for (var axis = 0; axis < 2; axis++) {
    void put(int i, int j, double v) {
      out[axis + 2 * i][axis + 2 * j] = v;
      out[axis + 2 * j][axis + 2 * i] = v;
    }

    if (n == 4) {
      put(0, 0, q * t * t * t / 3);
      put(0, 1, q * t * t / 2);
      put(1, 1, q * t);
    } else {
      put(0, 0, q * t * t * t * t * t / 20);
      put(0, 1, q * t * t * t * t / 8);
      put(0, 2, q * t * t * t / 6);
      put(1, 1, q * t * t * t / 3);
      put(1, 2, q * t * t / 2);
      put(2, 2, q * t);
    }
  }
  return out;
}

Matrix measurementMatrix(int n) {
  final h = zeros(2, n);
  h[0][0] = 1;
  h[1][1] = 1;
  return h;
}

State initialize(String kind, Point z, Params p) {
  final x = [z.$1, z.$2, 0.0, 0.0],
      d = [p.sigma * p.sigma, p.sigma * p.sigma, p.velocity, p.velocity];
  if (kind == 'CA') {
    x.addAll([0, 0]);
    d.addAll([p.acceleration, p.acceleration]);
  }
  return State(x, diagonal(d));
}

(State, Matrix) predict(State state, String kind, double t, double q) {
  final f = transition(kind, t),
      x = matrixVector(f, state.x),
      cov = matrixAdd(
        product(product(f, state.p), transpose(f)),
        processNoise(kind, t, q),
        1,
      );
  return (State(x, cov), f);
}

Innovation innovation(State state, Point z, double sigma) {
  final nu = [z.$1 - state.x[0], z.$2 - state.x[1]],
      s = matrixAdd(
        positionCovariance(state.p),
        diagonal([sigma * sigma, sigma * sigma]),
        1,
      ),
      si = inverse(s);
  return Innovation(nu, s, si, quadratic(nu, si));
}

(State, Innovation, double) update(State state, Point z, double sigma) {
  final v = innovation(state, z, sigma),
      n = state.x.length,
      h = measurementMatrix(n),
      r = diagonal([sigma * sigma, sigma * sigma]),
      k = product(product(state.p, transpose(h)), v.inverse),
      j = matrixAdd(identity(n), product(k, h), -1),
      x = vectorAdd(state.x, matrixVector(k, v.nu), 1),
      p = matrixAdd(
        product(product(j, state.p), transpose(j)),
        product(product(k, r), transpose(k)),
        1,
      ),
      likelihood = -log(2 * pi) - log(determinant(v.s)) / 2 - v.distance / 2;
  return (State(x, p), v, likelihood);
}

List<List<double>> smooth(
  List<State> states,
  List<State?> predicted,
  List<Matrix?> transitions,
) {
  final n = states.length,
      out = List.generate(states.length, (_) => <double>[]);
  out[n - 1] = List.of(states.last.x);
  for (var i = n - 2; i >= 0; i--) {
    final c = product(
      product(states[i].p, transpose(transitions[i + 1]!)),
      inverse(predicted[i + 1]!.p),
    );
    out[i] = vectorAdd(
      states[i].x,
      matrixVector(c, vectorAdd(out[i + 1], predicted[i + 1]!.x, -1)),
      1,
    );
  }
  return out;
}
