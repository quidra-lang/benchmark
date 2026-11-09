part of 'main.dart';

const modelNames = ['NB', 'LDA', 'QDA'];

class Statistics {
  final int n, p;
  final List<int> counts;
  final List<List<double>> means;
  final List<List<List<double>>> scatter;
  final List<double> center, variances;
  Statistics(List<Row> rows, List<int> features, int c)
    : n = rows.length,
      p = features.length,
      counts = List.filled(c, 0),
      means = List.generate(c, (_) => List.filled(features.length, 0.0)),
      scatter = List.generate(c, (_) => zeros(features.length)),
      center = List.filled(features.length, 0.0),
      variances = List.filled(features.length, 0.0) {
    final groups = List.generate(c, (_) => <List<double>>[]),
        vectors = <List<double>>[];
    for (final r in rows) {
      final x = [for (final j in features) r.values[j]];
      vectors.add(x);
      groups[r.classIndex].add(x);
    }
    for (var k = 0; k < c; k++) {
      final group = groups[k];
      counts[k] = group.length;
      for (var j = 0; j < p; j++) {
        var t = 0.0;
        for (final x in group) {
          t += x[j];
        }
        means[k][j] = t / group.length;
      }
      for (var a = 0; a < p; a++) {
        for (var b = 0; b < p; b++) {
          var t = 0.0;
          for (final x in group) {
            t += (x[a] - means[k][a]) * (x[b] - means[k][b]);
          }
          scatter[k][a][b] = t;
        }
      }
    }
    for (var j = 0; j < p; j++) {
      var t = 0.0;
      for (final x in vectors) {
        t += x[j];
      }
      center[j] = t / n;
      t = 0;
      for (final x in vectors) {
        t += (x[j] - center[j]) * (x[j] - center[j]);
      }
      variances[j] = t / n;
    }
  }
  List<List<double>> pooled() {
    final result = zeros(p);
    for (var a = 0; a < p; a++) {
      for (var b = 0; b < p; b++) {
        var t = 0.0;
        for (final sk in scatter) {
          t += sk[a][b];
        }
        result[a][b] = t / (n - counts.length);
      }
    }
    return result;
  }
}

class Prediction {
  final int predicted, decision;
  final List<double> posterior, logPosterior;
  final double confidence;
  Prediction(
    this.predicted,
    this.decision,
    this.posterior,
    this.logPosterior,
    this.confidence,
  );
}

int argmax(List<double> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[best]) best = i;
  }
  return best;
}

int argmin(List<double> values) {
  var best = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] < values[best]) best = i;
  }
  return best;
}

class GaussianModel {
  final String name;
  final List<int> features;
  final Statistics stats;
  final double epsilon, gamma;
  late final List<double> priors, logPriors, logDets;
  late final List<List<List<double>>> covariances, factors;
  late final double maxVariance, added, normalizer;
  GaussianModel(
    this.name,
    List<int> features,
    this.stats,
    String prior,
    this.epsilon,
    this.gamma,
  ) : features = [...features] {
    final c = stats.counts.length;
    maxVariance = stats.variances.reduce(math.max);
    added = epsilon * maxVariance;
    normalizer = features.length * math.log(2 * math.pi) / 2;
    priors = [
      for (final count in stats.counts)
        prior == 'empirical' ? count / stats.n : 1 / c,
    ];
    logPriors = priors.map(math.log).toList();
    if (name == 'LDA') {
      final pooled = stats.pooled(), l = cholesky(pooled), ld = logDet(l);
      covariances = List.filled(c, pooled);
      factors = List.filled(c, l);
      logDets = List.filled(c, ld);
    } else {
      covariances = [];
      factors = [];
      logDets = [];
      for (var k = 0; k < c; k++) {
        final count = stats.counts[k], cov = zeros(features.length);
        for (var a = 0; a < features.length; a++) {
          for (var b = 0; b < features.length; b++) {
            if (name == 'NB') {
              if (a == b) cov[a][b] = stats.scatter[k][a][b] / count + added;
            } else {
              var value = stats.scatter[k][a][b] / (count - 1);
              if (a != b) value *= 1 - gamma;
              cov[a][b] = value;
            }
          }
        }
        final l = cholesky(cov);
        covariances.add(cov);
        factors.add(l);
        logDets.add(logDet(l));
      }
    }
  }
  List<double> vector(List<double> values) => [
    for (final f in features) values[f],
  ];
  List<double> squaredDistances(List<double> v) => [
    for (var k = 0; k < priors.length; k++)
      quadratic(factors[k], [
        for (var j = 0; j < v.length; j++) v[j] - stats.means[k][j],
      ]),
  ];
  List<double> distances(List<double> values) =>
      squaredDistances(vector(values));
  List<double> scores(List<double> v) {
    final q = squaredDistances(v);
    return [
      for (var k = 0; k < q.length; k++)
        logPriors[k] - normalizer - logDets[k] / 2 - q[k] / 2,
    ];
  }

  int predict(List<double> values) => argmax(scores(vector(values)));
  Prediction inferVector(List<double> v, [List<List<double>>? costs]) {
    final g = scores(v),
        pred = argmax(g),
        ex = [for (final score in g) math.exp(score - g[pred])];
    var total = 0.0;
    for (final x in ex) {
      total += x;
    }
    final probs = [for (final x in ex) x / total],
        lt = math.log(total),
        logs = [for (final x in g) (x - g[pred]) - lt];
    var decision = pred;
    if (costs != null) {
      final risks = List.filled(g.length, 0.0);
      for (var b = 0; b < g.length; b++) {
        for (var k = 0; k < g.length; k++) {
          risks[b] += probs[k] * costs[k][b];
        }
      }
      decision = argmin(risks);
    }
    return Prediction(pred, decision, probs, logs, probs[argmax(probs)]);
  }

  Prediction infer(List<double> values, [List<List<double>>? costs]) =>
      inferVector(vector(values), costs);
}

GaussianModel trainModel(
  List<Row> rows,
  List<int> features,
  int c,
  String name,
  String prior,
  double epsilon,
  double gamma,
) => GaussianModel(
  name,
  features,
  Statistics(rows, features, c),
  prior,
  epsilon,
  gamma,
);
