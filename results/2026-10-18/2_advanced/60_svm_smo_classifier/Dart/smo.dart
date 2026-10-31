part of 'main.dart';

class Pass {
  final bool full;
  final int examined, changed;
  final List<double> alpha;
  Pass(this.full, this.examined, this.changed, this.alpha);
}

class Model {
  final List<Example> data;
  final Kernel kernel;
  final List<List<double>> q;
  final double c, tolerance, epsilon;
  double b = 0;
  final List<double> alpha, errors;
  int full = 0, nonbound = 0, examined = 0, steps = 0;
  final choice = List.filled(3, 0),
      clipping = List.filled(3, 0),
      passes = <Pass>[];
  bool converged = false;
  Model(this.data, this.q, this.kernel, this.c, Params p)
    : tolerance = p.tolerance,
      epsilon = p.epsilon,
      alpha = List.filled(data.length, 0),
      errors = data.map((e) => -e.label.toDouble()).toList();
  bool isNonbound(int i) => alpha[i] > 0 && alpha[i] < c;
  double snap(double a) => a < .00000001
      ? 0
      : a > c - .00000001
      ? c
      : a;
  bool take(int i1, int i2) {
    if (i1 == i2) return false;
    final alpha1 = alpha[i1],
        alpha2 = alpha[i2],
        y1 = data[i1].label,
        y2 = data[i2].label,
        e1 = errors[i1],
        e2 = errors[i2];
    var lo = max(0.0, alpha2 + alpha1 - c), hi = min(c, alpha2 + alpha1);
    if (y1 != y2) {
      lo = max(0.0, alpha2 - alpha1);
      hi = min(c, c + alpha2 - alpha1);
    }
    if (lo == hi) return false;
    final k11 = q[i1][i1],
        k12 = q[i1][i2],
        k22 = q[i2][i2],
        eta = k11 + k22 - 2 * k12;
    if (eta <= 0) return false;
    var a2 = alpha2 + y2 * (e1 - e2) / eta, clip = 0;
    if (a2 < lo) {
      a2 = lo;
      clip = 1;
    } else if (a2 > hi) {
      a2 = hi;
      clip = 2;
    }
    a2 = snap(a2);
    if ((a2 - alpha2).abs() < epsilon * (a2 + alpha2 + epsilon)) return false;
    final a1 = snap(alpha1 + y1 * y2 * (alpha2 - a2)),
        t1 = y1 * (a1 - alpha1),
        t2 = y2 * (a2 - alpha2),
        b1 = e1 + t1 * k11 + t2 * k12 + b,
        b2 = e2 + t1 * k12 + t2 * k22 + b;
    final next = a1 > 0 && a1 < c
            ? b1
            : a2 > 0 && a2 < c
            ? b2
            : (b1 + b2) / 2,
        delta = next - b;
    for (var i = 0; i < errors.length; i++) {
      errors[i] = errors[i] + (t1 * q[i1][i] + t2 * q[i2][i] - delta);
    }
    if (a1 > 0 && a1 < c) errors[i1] = 0;
    if (a2 > 0 && a2 < c) errors[i2] = 0;
    alpha[i1] = a1;
    alpha[i2] = a2;
    b = next;
    steps++;
    clipping[clip]++;
    return true;
  }

  int examine(int i2) {
    examined++;
    final r2 = errors[i2] * data[i2].label;
    if (!((r2 < -tolerance && alpha[i2] < c) ||
        (r2 > tolerance && alpha[i2] > 0)))
      return 0;
    var partner = -1, largest = -1.0;
    for (var i = 0; i < alpha.length; i++) {
      if (i != i2 && isNonbound(i)) {
        final v = (errors[i] - errors[i2]).abs();
        if (v > largest) {
          partner = i;
          largest = v;
        }
      }
    }
    if (partner >= 0 && take(partner, i2)) {
      choice[0]++;
      return 1;
    }
    for (var i = 0; i < alpha.length; i++) {
      if (isNonbound(i) && take(i, i2)) {
        choice[1]++;
        return 1;
      }
    }
    for (var i = 0; i < alpha.length; i++) {
      if (take(i, i2)) {
        choice[2]++;
        return 1;
      }
    }
    return 0;
  }

  double decision(Point z) {
    var s = 0.0;
    for (var j = 0; j < alpha.length; j++) {
      if (alpha[j] > 0)
        s += alpha[j] * data[j].label * kernel.value(data[j].point, z);
    }
    return s - b;
  }

  List<double> trainingValues() => List.generate(data.length, (i) {
    var s = 0.0;
    for (var j = 0; j < alpha.length; j++) {
      if (alpha[j] > 0) s += alpha[j] * data[j].label * q[i][j];
    }
    return s - b;
  });
  (int, int, int) counts() {
    var total = 0, bound = 0;
    for (final a in alpha) {
      if (a > 0) {
        total++;
        if (a == c) bound++;
      }
    }
    return (total, bound, total - bound);
  }
}

Model train(
  List<Example> data,
  List<List<double>> q,
  Kernel k,
  double c,
  Params p,
) {
  final m = Model(data, q, k, c, p);
  var all = true;
  while (true) {
    final examined = m.examined;
    var changed = 0;
    for (var i = 0; i < data.length; i++) {
      if (all || m.isNonbound(i)) changed += m.examine(i);
    }
    m.passes.add(
      Pass(all, m.examined - examined, changed, all ? List.of(m.alpha) : []),
    );
    if (all) {
      m.full++;
    } else {
      m.nonbound++;
    }
    if (all && changed == 0) {
      m.converged = true;
      break;
    }
    if (m.passes.length == p.maxPasses) break;
    if (all) {
      all = false;
    } else if (changed == 0) {
      all = true;
    }
  }
  return m;
}

(double, double) objective(
  List<double> alpha,
  List<Example> data,
  List<List<double>> q,
) {
  var quadratic = 0.0, total = 0.0;
  for (var i = 0; i < alpha.length; i++) {
    var s = 0.0;
    for (var j = 0; j < alpha.length; j++) {
      if (alpha[j] > 0) s += alpha[j] * data[j].label * q[i][j];
    }
    quadratic += alpha[i] * data[i].label * s;
    total += alpha[i];
  }
  return (quadratic, total - quadratic / 2);
}
