part of 'main.dart';

class RandomGenerator {
  int state;
  RandomGenerator(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }

  double factor() => (draw() % 2001 - 1000) / 10000;
}

double dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var f = 0; f < a.length; f++) {
    sum += a[f] * b[f];
  }
  return sum;
}

List<List<double>> zeros(int rows, int cols) =>
    List.generate(rows, (_) => List.filled(cols, 0.0));

class FactorModel {
  final double mean;
  final List<List<double>> users, items;
  final List<double> userBias, itemBias;
  FactorModel(this.mean, this.users, this.items, this.userBias, this.itemBias);
  double predict(int u, int i) =>
      ((mean + userBias[u]) + itemBias[i]) + dot(users[u], items[i]);
}

class TrainingRecord {
  final String method;
  final int epoch;
  final double rmse;
  TrainingRecord(this.method, this.epoch, this.rmse);
}

(FactorModel, List<TrainingRecord>) trainSVD(Ratings d) {
  final p = d.params,
      rng = RandomGenerator(p.seed),
      users = zeros(d.users.length, p.factors),
      items = zeros(d.items.length, p.factors);
  for (final row in users) {
    for (var f = 0; f < p.factors; f++) {
      row[f] = rng.factor();
    }
  }
  for (final row in items) {
    for (var f = 0; f < p.factors; f++) {
      row[f] = rng.factor();
    }
  }
  final model = FactorModel(
        d.mean,
        users,
        items,
        List.filled(users.length, 0.0),
        List.filled(items.length, 0.0),
      ),
      order = List.generate(d.training.length, (i) => i),
      log = <TrainingRecord>[];
  for (var epoch = 1; epoch <= p.epochs; epoch++) {
    for (var t = order.length - 1; t >= 1; t--) {
      final y = rng.draw() % (t + 1), old = order[t];
      order[t] = order[y];
      order[y] = old;
    }
    for (final j in order) {
      final r = d.training[j],
          u = r.user,
          i = r.item,
          e = r.value - model.predict(u, i);
      model.userBias[u] += p.rate * (e - p.regularization * model.userBias[u]);
      model.itemBias[i] += p.rate * (e - p.regularization * model.itemBias[i]);
      for (var f = 0; f < p.factors; f++) {
        final a = users[u][f], b = items[i][f];
        users[u][f] = a + p.rate * (e * b - p.regularization * a);
        items[i][f] = b + p.rate * (e * a - p.regularization * b);
      }
    }
    log.add(
      TrainingRecord('SVD', epoch, trainingRMSE(d.training, model.predict)),
    );
  }
  return (model, log);
}

List<double> choleskySolve(List<List<double>> a, List<double> w) {
  final n = w.length, l = zeros(w.length, w.length);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j <= i; j++) {
      var sum = 0.0;
      for (var k = 0; k < j; k++) {
        sum += l[i][k] * l[j][k];
      }
      final s = a[i][j] - sum;
      l[i][j] = i == j ? math.sqrt(s) : s / l[j][j];
    }
  }
  final z = List.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    var sum = 0.0;
    for (var k = 0; k < i; k++) {
      sum += l[i][k] * z[k];
    }
    z[i] = (w[i] - sum) / l[i][i];
  }
  final x = List.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    var sum = 0.0;
    for (var k = i + 1; k < n; k++) {
      sum += l[k][i] * x[k];
    }
    x[i] = (z[i] - sum) / l[i][i];
  }
  return x;
}

List<double> fitVector(
  List<List<double>> vectors,
  List<double> residuals,
  int factors,
  double regularization,
) {
  final a = zeros(factors, factors), w = List.filled(factors, 0.0);
  for (var i = 0; i < vectors.length; i++) {
    final v = vectors[i];
    for (var row = 0; row < factors; row++) {
      w[row] += residuals[i] * v[row];
      for (var col = 0; col < factors; col++) {
        a[row][col] += v[row] * v[col];
      }
    }
  }
  for (var row = 0; row < factors; row++) {
    a[row][row] += regularization * vectors.length;
  }
  return choleskySolve(a, w);
}

(FactorModel, List<TrainingRecord>) trainALS(
  Ratings d,
  List<double> userBias,
  List<double> itemBias,
) {
  final p = d.params,
      rng = RandomGenerator(p.seed),
      users = zeros(d.users.length, p.factors),
      items = zeros(d.items.length, p.factors);
  for (final row in items) {
    for (var f = 0; f < p.factors; f++) {
      row[f] = rng.factor();
    }
  }
  final model = FactorModel(d.mean, users, items, userBias, itemBias),
      residual = zeros(d.users.length, d.items.length),
      log = <TrainingRecord>[];
  for (final r in d.training) {
    residual[r.user][r.item] =
        r.value - ((d.mean + userBias[r.user]) + itemBias[r.item]);
  }
  for (var iteration = 1; iteration <= p.alsIterations; iteration++) {
    for (var u = 0; u < d.users.length; u++) {
      final vectors = <List<double>>[], targets = <double>[];
      for (final r in d.byUser[u]) {
        vectors.add(items[r.other]);
        targets.add(residual[u][r.other]);
      }
      users[u] = fitVector(vectors, targets, p.factors, p.alsReg);
    }
    for (var i = 0; i < d.items.length; i++) {
      final vectors = <List<double>>[], targets = <double>[];
      for (final r in d.byItem[i]) {
        vectors.add(users[r.other]);
        targets.add(residual[r.other][i]);
      }
      items[i] = fitVector(vectors, targets, p.factors, p.alsReg);
    }
    log.add(
      TrainingRecord('ALS', iteration, trainingRMSE(d.training, model.predict)),
    );
  }
  return (model, log);
}
