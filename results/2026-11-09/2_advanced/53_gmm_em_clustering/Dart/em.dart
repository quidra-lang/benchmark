part of 'main.dart';

Model adjustType(Model initial, String kind) {
  var shared = const Covariance(0, 0, 0);
  if (kind == 'TIED') {
    var a = 0.0, b = 0.0, c = 0.0;
    for (final component in initial) {
      a += component.weight * component.cov.a;
      b += component.weight * component.cov.b;
      c += component.weight * component.cov.c;
    }
    shared = Covariance(a, b, c);
  }
  final model = <Component>[];
  for (final component in initial) {
    final s = component.cov, v = (s.a + s.c) / 2;
    final covariance = switch (kind) {
      'DIAG' => Covariance(s.a, 0, s.c),
      'SPHERICAL' => Covariance(v, 0, v),
      'TIED' => shared,
      _ => s,
    };
    model.add(Component(component.weight, component.mean, covariance));
  }
  return model;
}

class ERecord {
  final List<double> responsibilities, scores;
  final double logDensity;
  ERecord(this.responsibilities, this.scores, this.logDensity);
}

(List<ERecord>, double) expectation(List<DataPoint> points, Model model) {
  final records = <ERecord>[];
  var loglik = 0.0;
  for (final point in points) {
    final scores = [for (final c in model) weightedLogDensity(point.point, c)],
        maximum = scores.reduce(max),
        exponentials = [for (final score in scores) exp(score - maximum)];
    var total = 0.0;
    for (final value in exponentials) {
      total += value;
    }
    for (var k = 0; k < exponentials.length; k++) {
      exponentials[k] /= total;
    }
    final density = maximum + log(total);
    records.add(ERecord(exponentials, scores, density));
    loglik += density;
  }
  return (records, loglik);
}

Model maximization(
  List<DataPoint> points,
  List<ERecord> records,
  String kind,
  double epsilon,
) {
  final n = points.length,
      kCount = records.first.responsibilities.length,
      counts = List.filled(records.first.responsibilities.length, 0.0),
      means = <Point>[],
      scatter = <Covariance>[];
  for (var k = 0; k < kCount; k++) {
    var count = 0.0, x = 0.0, y = 0.0;
    for (var i = 0; i < n; i++) {
      final r = records[i].responsibilities[k];
      count += r;
      x += r * points[i].point.x;
      y += r * points[i].point.y;
    }
    counts[k] = count;
    final mean = Point(x / count, y / count);
    means.add(mean);
    var a = 0.0, b = 0.0, c = 0.0;
    for (var i = 0; i < n; i++) {
      final r = records[i].responsibilities[k],
          dx = points[i].point.x - mean.x,
          dy = points[i].point.y - mean.y;
      a += r * dx * dx;
      b += r * dx * dy;
      c += r * dy * dy;
    }
    scatter.add(Covariance(a, b, c));
  }
  var shared = const Covariance(0, 0, 0);
  if (kind == 'TIED') {
    var a = 0.0, b = 0.0, c = 0.0;
    for (final s in scatter) {
      a += s.a;
      b += s.b;
      c += s.c;
    }
    shared = Covariance(a / n + epsilon, b / n, c / n + epsilon);
  }
  final model = <Component>[];
  for (var k = 0; k < kCount; k++) {
    final s = scatter[k],
        count = counts[k],
        v = (s.a / count + s.c / count) / 2 + epsilon;
    final covariance = switch (kind) {
      'FULL' => Covariance(
        s.a / count + epsilon,
        s.b / count,
        s.c / count + epsilon,
      ),
      'DIAG' => Covariance(s.a / count + epsilon, 0, s.c / count + epsilon),
      'SPHERICAL' => Covariance(v, 0, v),
      _ => shared,
    };
    model.add(Component(count / n, means[k], covariance));
  }
  return model;
}

class EMRun {
  final Model model;
  final List<ERecord> records;
  final List<double> trace;
  final double loglik;
  int settledAt, largestIteration = 1;
  double largestIncrease;
  final violations = <int>[];
  EMRun(this.model, this.records, this.trace, this.loglik)
    : settledAt = trace.length - 1,
      largestIncrease = trace[1] - trace[0];
}

EMRun runEM(List<DataPoint> points, Model initial, String kind, Params p) {
  var model = adjustType(initial, kind);
  var (records, loglik) = expectation(points, model);
  final trace = <double>[loglik];
  for (var t = 0; t < p.iterations; t++) {
    model = maximization(points, records, kind, p.epsilon);
    (records, loglik) = expectation(points, model);
    trace.add(loglik);
  }
  final result = EMRun(model, records, trace, loglik);
  for (var t = trace.length - 1; t >= 0; t--) {
    if ((trace[t] - loglik).abs() > p.tolerance) {
      break;
    }
    result.settledAt = t;
  }
  for (var t = 1; t < trace.length; t++) {
    final increase = trace[t] - trace[t - 1];
    if (increase > result.largestIncrease) {
      result.largestIncrease = increase;
      result.largestIteration = t;
    }
    if (trace[t] < trace[t - 1] - 0.000001 * trace[t - 1].abs()) {
      result.violations.add(t);
    }
  }
  return result;
}
