part of 'main.dart';

double sum(Iterable<double> values) {
  var total = 0.0;
  for (final value in values) {
    total += value;
  }
  return total;
}

int lowerBound(List<double> values, double target) {
  var low = 0, high = values.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (values[middle] < target) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

class Stump {
  final int feature;
  final List<double> thresholds, values;
  Stump(this.feature, this.thresholds, this.values);
  double output(List<double> row) =>
      values[lowerBound(thresholds, row[feature])];
}

class SearchSpace {
  final List<Row> rows;
  final orders = <List<int>>[];
  final groups = <List<List<int>>>[];
  final thresholds = <List<double>>[];
  SearchSpace(this.rows) {
    for (var feature = 0; feature < rows.first.values.length; feature++) {
      final order = List.generate(rows.length, (i) => i);
      order.sort((a, b) {
        final c = rows[a].values[feature].compareTo(rows[b].values[feature]);
        return c != 0 ? c : a.compareTo(b);
      });
      final grouped = <List<int>>[], distinct = <double>[];
      for (final i in order) {
        final value = rows[i].values[feature];
        if (distinct.isEmpty || value != distinct.last) {
          distinct.add(value);
          grouped.add([]);
        }
        grouped.last.add(i);
      }
      final cuts = <double>[distinct.first - 1];
      for (var k = 0; k + 1 < distinct.length; k++) {
        cuts.add((distinct[k] + distinct[k + 1]) / 2);
      }
      orders.add(order);
      groups.add(grouped);
      thresholds.add(cuts);
    }
  }
}

List<double> leftCumulative(List<List<int>> groups, List<double> values) {
  final result = List.filled(groups.length, 0.0);
  var total = 0.0;
  for (var k = 0; k + 1 < groups.length; k++) {
    for (final i in groups[k]) {
      total += values[i];
    }
    result[k + 1] = total;
  }
  return result;
}

class Candidate {
  final double error, threshold, left, right;
  final int feature, polarity;
  final List<double> positive, negative;
  Candidate(
    this.error,
    this.feature, {
    this.threshold = 0,
    this.polarity = 0,
    this.left = 0,
    this.right = 0,
    this.positive = const [],
    this.negative = const [],
  });
}

Candidate choose(List<Candidate> candidates) {
  var minimum = candidates.first.error;
  for (final c in candidates.skip(1)) {
    minimum = min(minimum, c.error);
  }
  return candidates.firstWhere((c) => c.error <= minimum + 1e-9);
}

Candidate discreteSearch(
  SearchSpace space,
  List<int> labels,
  List<double> weights,
) {
  final positive = List.filled(weights.length, 0.0),
      negative = List.filled(weights.length, 0.0);
  for (var i = 0; i < weights.length; i++) {
    (labels[i] == 1 ? positive : negative)[i] = weights[i];
  }
  final wp = sum(positive), wn = sum(negative), candidates = <Candidate>[];
  for (var feature = 0; feature < space.thresholds.length; feature++) {
    final lp = leftCumulative(space.groups[feature], positive),
        ln = leftCumulative(space.groups[feature], negative);
    for (var k = 0; k < space.thresholds[feature].length; k++) {
      final t = space.thresholds[feature][k];
      candidates.add(
        Candidate(lp[k] + (wn - ln[k]), feature, threshold: t, polarity: 1),
      );
      candidates.add(
        Candidate(ln[k] + (wp - lp[k]), feature, threshold: t, polarity: -1),
      );
    }
  }
  return choose(candidates);
}

(Stump, double) regressionSearch(
  SearchSpace space,
  List<double> targets,
  List<double> weights,
) {
  final w = sum(weights), products = List.filled(weights.length, 0.0);
  var q = 0.0;
  for (var i = 0; i < weights.length; i++) {
    products[i] = weights[i] * targets[i];
    q += weights[i] * targets[i] * targets[i];
  }
  final s = sum(products), candidates = <Candidate>[];
  for (var feature = 0; feature < space.thresholds.length; feature++) {
    final lw = leftCumulative(space.groups[feature], weights),
        ls = leftCumulative(space.groups[feature], products);
    for (var k = 0; k < space.thresholds[feature].length; k++) {
      final wr = w - lw[k], sr = s - ls[k];
      var left = 0.0, gain = sr * sr / wr;
      if (k > 0) {
        left = ls[k] / lw[k];
        gain = ls[k] * ls[k] / lw[k] + sr * sr / wr;
      }
      candidates.add(
        Candidate(
          q - gain,
          feature,
          threshold: space.thresholds[feature][k],
          left: left,
          right: sr / wr,
        ),
      );
    }
  }
  final c = choose(candidates);
  return (Stump(c.feature, [c.threshold], [c.left, c.right]), c.error);
}

(Stump, double) multiclassSearch(
  SearchSpace space,
  List<int> labels,
  List<double> weights,
  int classes,
) {
  final total = sum(weights), totals = List.filled(classes, 0.0);
  for (var c = 0; c < classes; c++) {
    for (var i = 0; i < weights.length; i++) {
      if (labels[i] == c + 1) {
        totals[c] += weights[i];
      }
    }
  }
  final candidates = <Candidate>[];
  for (var feature = 0; feature < space.thresholds.length; feature++) {
    final left = List.filled(classes, 0.0);
    for (var k = 0; k < space.thresholds[feature].length; k++) {
      if (k > 0) {
        for (final i in space.groups[feature][k - 1]) {
          left[labels[i] - 1] += weights[i];
        }
      }
      final right = List.generate(classes, (c) => totals[c] - left[c]);
      var a = 0, b = 0;
      for (var c = 1; c < classes; c++) {
        if (left[c] > left[a]) {
          a = c;
        }
        if (right[c] > right[b]) {
          b = c;
        }
      }
      candidates.add(
        Candidate(
          total - (left[a] + right[b]),
          feature,
          threshold: space.thresholds[feature][k],
          left: (a + 1).toDouble(),
          right: (b + 1).toDouble(),
        ),
      );
    }
  }
  final c = choose(candidates);
  return (Stump(c.feature, [c.threshold], [c.left, c.right]), c.error);
}

(List<List<double>>, List<List<int>>) realGeometry(
  SearchSpace space,
  int bins,
) {
  final cuts = <List<double>>[], assignments = <List<int>>[];
  for (var feature = 0; feature < space.orders.length; feature++) {
    final values = [
      for (final i in space.orders[feature]) space.rows[i].values[feature],
    ];
    final featureCuts = <double>[];
    for (var b = 1; b < bins; b++) {
      final r = b * values.length ~/ bins;
      featureCuts.add((values[r - 1] + values[r]) / 2);
    }
    cuts.add(featureCuts);
    assignments.add([
      for (final row in space.rows)
        lowerBound(featureCuts, row.values[feature]),
    ]);
  }
  return (cuts, assignments);
}

Candidate realSearch(
  List<List<int>> assignments,
  List<int> labels,
  List<double> weights,
  int bins,
) {
  final candidates = <Candidate>[];
  for (var feature = 0; feature < assignments.length; feature++) {
    final positive = List.filled(bins, 0.0), negative = List.filled(bins, 0.0);
    for (var i = 0; i < weights.length; i++) {
      (labels[i] == 1 ? positive : negative)[assignments[feature][i]] +=
          weights[i];
    }
    var z = 0.0;
    for (var b = 0; b < bins; b++) {
      z += sqrt(positive[b] * negative[b]);
    }
    candidates.add(
      Candidate(2 * z, feature, positive: positive, negative: negative),
    );
  }
  return choose(candidates);
}
