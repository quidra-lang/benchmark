import 'dart:io';
import 'dart:math';

part 'dataset.dart';
part 'stumps.dart';
part 'adaboost.dart';
part 'variants.dart';
part 'evaluation.dart';

class Minstd {
  int state;
  Minstd(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }
}

Model trainVariant(String variant, List<Row> rows, Params p) =>
    switch (variant) {
      'discrete' => trainDiscrete(rows, p.rounds),
      'real' => trainReal(rows, p.rounds, p.bins, p.smoothing, p.convergence),
      'gentle' => trainGentle(rows, p.rounds),
      'logit' => trainLogit(rows, p.rounds, p.clip),
      _ => throw StateError('unknown variant'),
    };
double rowScore(List<Round> rounds, List<double> values) {
  var total = 0.0;
  for (final round in rounds) {
    total += round.stump.output(values);
  }
  return total;
}

List<double> scoreRows(List<Round> rounds, List<Row> rows) => [
  for (final row in rows) rowScore(rounds, row.values),
];
void addRoundScores(Round round, List<Row> rows, List<double> scores) {
  for (var i = 0; i < rows.length; i++) {
    scores[i] += round.stump.output(rows[i].values);
  }
}

double magnitude(Round round) {
  var value = 0.0;
  for (final v in round.stump.values) {
    value = max(value, v.abs());
  }
  return value;
}

double totalMagnitude(List<Round> rounds) => sum(rounds.map(magnitude));
List<double> contributions(
  List<Round> rounds,
  List<double> values,
  int features,
) {
  final result = List.filled(features, 0.0);
  for (final round in rounds) {
    result[round.stump.feature] += round.stump.output(values);
  }
  return result;
}

int countErrors(List<Row> rows, List<double> scores) {
  var count = 0;
  for (var i = 0; i < rows.length; i++) {
    if (prediction(scores[i]) != rows[i].label) {
      count++;
    }
  }
  return count;
}

double loss(List<Row> rows, List<double> scores, String variant) {
  var total = 0.0;
  for (var i = 0; i < rows.length; i++) {
    total += variant == 'logit'
        ? log(1 + exp(-2 * rows[i].label * scores[i]))
        : exp(-rows[i].label * scores[i]);
  }
  return total / rows.length;
}

String metricsLine(
  String kind,
  String variant,
  int rounds,
  List<Row> rows,
  List<double> scores,
) {
  var tp = 0, fp = 0, tn = 0, fn = 0;
  for (var i = 0; i < rows.length; i++) {
    if (prediction(scores[i]) == 1) {
      if (rows[i].label == 1) {
        tp++;
      } else {
        fp++;
      }
    } else if (rows[i].label == -1) {
      tn++;
    } else {
      fn++;
    }
  }
  final (a, b) = auc(rows, scores);
  return '$kind $variant rounds $rounds correct ${tp + tn}/${rows.length} accuracy ${ratio(tp + tn, rows.length)} tp $tp fp $fp tn $tn fn $fn precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)} f1 ${ratio(2 * tp, 2 * tp + fp + fn)} auc ${ratio(a, b)} loss ${number(loss(rows, scores, variant))}';
}

class CurvePoint {
  final int round, trainErrors, testErrors;
  final double trainLoss, testLoss, margin;
  CurvePoint(
    this.round,
    this.trainErrors,
    this.testErrors,
    this.trainLoss,
    this.testLoss,
    this.margin,
  );
}

List<CurvePoint> trainingCurve(
  List<Round> rounds,
  List<Row> training,
  List<Row> testing,
  String variant,
) {
  final train = List.filled(training.length, 0.0),
      test = List.filled(testing.length, 0.0),
      curve = <CurvePoint>[];
  var scale = 0.0;
  for (var t = 0; t < rounds.length; t++) {
    final r = rounds[t];
    addRoundScores(r, training, train);
    addRoundScores(r, testing, test);
    scale += magnitude(r);
    var minimum = double.infinity;
    for (var i = 0; i < training.length; i++) {
      minimum = min(minimum, training[i].label * train[i]);
    }
    curve.add(
      CurvePoint(
        t + 1,
        countErrors(training, train),
        countErrors(testing, test),
        loss(training, train, variant),
        loss(testing, test, variant),
        minimum / scale,
      ),
    );
  }
  return curve;
}

class Fold {
  final List<int> indices, errors;
  final int train;
  final Model model;
  Fold(this.indices, this.train, this.model, this.errors);
}

class CrossValidation {
  final folds = <Fold>[];
  final List<int> errors;
  final List<double> scores;
  int selected = 0;
  CrossValidation(int rounds, int n)
    : errors = List.filled(rounds, 0),
      scores = List.filled(n, 0.0);
}

CrossValidation crossValidate(List<Row> rows, Params p) {
  final space = SearchSpace(rows), cv = CrossValidation(p.rounds, rows.length);
  for (var f = 0; f < p.folds; f++) {
    final indices = [
      for (var i = 0; i < rows.length; i++)
        if (i % p.folds == f) i,
    ];
    final n = rows.length - indices.length;
    final weights = [
      for (var i = 0; i < rows.length; i++) i % p.folds == f ? 0.0 : 1 / n,
    ];
    final model = trainDiscrete(rows, p.rounds, initial: weights, space: space);
    final validation = [for (final i in indices) rows[i]],
        scores = List.filled(indices.length, 0.0),
        errors = List.filled(p.rounds, 0);
    for (var t = 0; t < p.rounds; t++) {
      if (t < model.rounds.length) {
        addRoundScores(model.rounds[t], validation, scores);
      }
      errors[t] = countErrors(validation, scores);
      cv.errors[t] += errors[t];
    }
    cv.folds.add(Fold(indices, n, model, errors));
  }
  var best = 0;
  for (var t = 1; t < p.rounds; t++) {
    if (cv.errors[t] < cv.errors[best]) {
      best = t;
    }
  }
  cv.selected = best + 1;
  for (final fold in cv.folds) {
    final rounds = fold.model.rounds.take(cv.selected).toList();
    for (final i in fold.indices) {
      cv.scores[i] = rowScore(rounds, rows[i].values);
    }
  }
  return cv;
}

class Importance {
  final List<double> scores;
  final List<int> counts, order;
  late final double total;
  Importance(List<Round> rounds, int features, bool samme)
    : scores = List.filled(features, 0.0),
      counts = List.filled(features, 0),
      order = List.generate(features, (i) => i) {
    for (final r in rounds) {
      scores[r.stump.feature] += samme ? r.alpha : magnitude(r);
      counts[r.stump.feature]++;
    }
    total = sum(scores);
    order.sort((a, b) {
      final c = scores[b].compareTo(scores[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  }
}

List<String> importanceLines(Importance v, List<String> features) => [
  'importance',
  for (var rank = 0; rank < v.order.length; rank++)
    '${rank + 1} ${features[v.order[rank]]} score ${number(v.scores[v.order[rank]])} share ${ratioReal(v.scores[v.order[rank]], v.total)} rounds ${v.counts[v.order[rank]]}',
];

class VariantAnalysis {
  final String name;
  final Model full;
  final List<Round> rounds;
  final double scale;
  final List<double> train, test;
  final List<CurvePoint> curve;
  final Importance importance;
  VariantAnalysis(this.name, this.full, this.rounds, Inputs input)
    : scale = totalMagnitude(rounds),
      train = scoreRows(rounds, input.train),
      test = scoreRows(rounds, input.test),
      curve = trainingCurve(full.rounds, input.train, input.test, name),
      importance = Importance(rounds, input.features.length, false);
}

List<VariantAnalysis> analyzeVariants(Inputs input, int selected) {
  final result = <VariantAnalysis>[];
  for (final name in input.params.variants) {
    final model = trainVariant(name, input.train, input.params);
    final rounds = name == 'discrete'
        ? model.rounds.take(selected).toList()
        : model.rounds;
    result.add(VariantAnalysis(name, model, rounds, input));
  }
  return result;
}

String numberList(List<double> values) => values.map(number).join(' ');
List<String> ensembleLines(
  Inputs input,
  List<VariantAnalysis> analysis,
  CrossValidation cv,
) {
  final sections = <List<String>>[], p = input.params;
  for (final a in analysis) {
    final model = a.full;
    var header =
        'variant ${a.name} rounds ${model.rounds.length} stop ${model.stop}';
    if (a.name == 'real') {
      header +=
          ' bins ${p.bins} smoothing ${number(p.smoothing)} convergence ${numberDigits(p.convergence, 6)}';
    } else if (a.name == 'logit') {
      header += ' clip ${number(p.clip)}';
    }
    final lines = <String>[header];
    if (a.name == 'real') {
      for (var j = 0; j < model.cuts.length; j++) {
        lines.add('cuts ${input.features[j]} ${numberList(model.cuts[j])}');
      }
    }
    for (var t = 0; t < model.rounds.length; t++) {
      final r = model.rounds[t], s = r.stump;
      var line = 'round ${t + 1} feature ${input.features[s.feature]}';
      if (a.name == 'real') {
        line +=
            ' z ${number(r.z)} bound ${number(r.bound)} values ${numberList(s.values)}';
      } else {
        line += ' threshold ${number(s.thresholds[0])}';
        if (a.name == 'discrete') {
          line +=
              ' polarity ${r.polarity} error ${number(r.error)} alpha ${number(r.alpha)} z ${number(r.z)} bound ${number(r.bound)}';
        } else {
          line +=
              ' left ${number(s.values[0])} right ${number(s.values[1])} error ${number(r.error)}';
          if (a.name == 'logit') {
            line += ' loss ${number(r.loss)}';
          }
        }
      }
      lines.add(line);
      if (a.name == 'discrete') {
        var maximum = 0, squared = 0.0;
        for (var i = 0; i < r.weights.length; i++) {
          if (r.weights[i] > r.weights[maximum]) {
            maximum = i;
          }
          squared += r.weights[i] * r.weights[i];
        }
        lines.add(
          'weights ${t + 1} max ${numberDigits(r.weights[maximum], 6)} id ${input.train[maximum].id} ess ${number(1 / squared)}',
        );
      }
    }
    if (a.name == 'discrete') {
      lines.add(
        'cv folds ${p.folds} selected ${cv.selected} errors ${cv.errors[cv.selected - 1]}/${input.train.length}',
      );
      for (var f = 0; f < cv.folds.length; f++) {
        final fold = cv.folds[f], n = fold.indices.length;
        lines.add(
          'fold ${f + 1} train ${fold.train} validation $n rounds ${fold.model.rounds.length} stop ${fold.model.stop} selected ${fold.errors[cv.selected - 1]}/$n final ${fold.errors.last}/$n',
        );
      }
      lines.add('cv_errors ${ints(cv.errors)}');
    }
    sections.add(lines);
  }
  return separateSections(sections);
}

List<String> errorCurveLines(
  Inputs input,
  List<VariantAnalysis> analysis,
  List<(int, int, int)> sammeCurve,
) {
  final lines = <String>[
    'variant,round,train_error,test_error,train_loss,test_loss,min_margin',
  ];
  for (final a in analysis) {
    for (final c in a.curve) {
      lines.add(
        '${a.name},${c.round},${ratio(c.trainErrors, input.train.length)},${ratio(c.testErrors, input.test.length)},${number(c.trainLoss)},${number(c.testLoss)},${number(c.margin)}',
      );
    }
  }
  for (final (t, te, ve) in sammeCurve) {
    lines.add(
      'samme,$t,${ratio(te, input.multiTrain.length)},${ratio(ve, input.multiTest.length)},-,-,-',
    );
  }
  return lines;
}

List<String> predictionLines(Inputs input, List<VariantAnalysis> analysis) {
  final lines = <String>['id,variant,score,label,${input.features.join(',')}'];
  for (var i = 0; i < input.test.length; i++) {
    final row = input.test[i];
    for (final a in analysis) {
      lines.add(
        [
          row.id,
          a.name,
          number(a.test[i]),
          '${prediction(a.test[i])}',
          ...contributions(
            a.rounds,
            row.values,
            input.features.length,
          ).map(number),
        ].join(','),
      );
    }
  }
  return lines;
}

List<String> rocLines(Inputs input, List<VariantAnalysis> analysis) {
  final lines = <String>['variant,threshold,tp,fp'];
  for (final a in analysis) {
    final values = a.test.toSet().toList()..sort((a, b) => b.compareTo(a));
    for (final threshold in values) {
      var tp = 0, fp = 0;
      for (var i = 0; i < input.test.length; i++) {
        if (a.test[i] >= threshold) {
          if (input.test[i].label == 1) {
            tp++;
          } else {
            fp++;
          }
        }
      }
      lines.add('${a.name},${number(threshold)},$tp,$fp');
    }
  }
  return lines;
}

class PermutationResult {
  final int feature, drop, minimum, maximum;
  PermutationResult(this.feature, this.drop, this.minimum, this.maximum);
}

(int, List<PermutationResult>) permutationImportance(
  List<Round> rounds,
  List<Row> rows,
  int features,
  int repeats,
  Minstd rng,
) {
  final base = rows.length - countErrors(rows, scoreRows(rounds, rows)),
      result = <PermutationResult>[];
  for (var j = 0; j < features; j++) {
    var drop = 0, minimum = rows.length, maximum = 0;
    for (var repeat = 0; repeat < repeats; repeat++) {
      final permutation = List.generate(rows.length, (i) => i);
      for (var i = rows.length - 1; i >= 1; i--) {
        final other = rng.draw() % (i + 1), old = permutation[i];
        permutation[i] = permutation[other];
        permutation[other] = old;
      }
      var correct = 0;
      for (var i = 0; i < rows.length; i++) {
        final values = List<double>.of(rows[i].values);
        values[j] = rows[permutation[i]].values[j];
        if (prediction(rowScore(rounds, values)) == rows[i].label) {
          correct++;
        }
      }
      drop += base - correct;
      minimum = min(minimum, correct);
      maximum = max(maximum, correct);
    }
    result.add(PermutationResult(j, drop, minimum, maximum));
  }
  result.sort((a, b) {
    final c = b.drop.compareTo(a.drop);
    return c != 0 ? c : a.feature.compareTo(b.feature);
  });
  return (base, result);
}

List<double> margins(List<Row> rows, List<double> scores, double scale) => [
  for (var i = 0; i < rows.length; i++) rows[i].label * scores[i] / scale,
];
double minimum(List<double> values) => values.reduce(min);
double maximum(List<double> values) => values.reduce(max);
List<String> marginLines(Inputs input, List<VariantAnalysis> analysis) {
  final sections = <List<String>>[],
      p = input.params,
      rng = Minstd(input.params.permutationSeed);
  for (final a in analysis) {
    final train = margins(input.train, a.train, a.scale),
        test = margins(input.test, a.test, a.scale);
    final lines = <String>[
      'variant ${a.name} rounds ${a.rounds.length} scale ${number(a.scale)}',
      'train min ${number(minimum(train))} mean ${number(sum(train) / train.length)}',
    ];
    for (final theta in p.margins) {
      final count = countAtMost(train, theta);
      lines.add(
        'train le ${number(theta)} $count/${train.length} ${ratio(count, train.length)}',
      );
    }
    final hist = List.filled(20, 0);
    for (final v in train) {
      hist[min(19, ((v + 1) * 10).floor())]++;
    }
    lines.add('histogram ${ints(hist)}');
    final hardest = List.generate(train.length, (i) => i)
      ..sort((a, b) {
        final c = train[a].compareTo(train[b]);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final i in hardest.take(5)) {
      lines.add(
        'hardest ${input.train[i].id} label ${input.train[i].label} margin ${number(train[i])}',
      );
    }
    lines.add(
      'test min ${number(minimum(test))} mean ${number(sum(test) / test.length)}',
    );
    for (final theta in p.margins) {
      final count = countAtMost(test, theta);
      lines.add(
        'test le ${number(theta)} $count/${test.length} ${ratio(count, test.length)}',
      );
    }
    for (final theta in p.margins) {
      var confident = 0, correct = 0;
      for (var i = 0; i < test.length; i++) {
        if (test[i].abs() > theta) {
          confident++;
          if (prediction(a.test[i]) == input.test[i].label) {
            correct++;
          }
        }
      }
      lines.add(
        'test confident ${number(theta)} $confident/${test.length} correct $correct/$confident ${ratio(correct, confident)}',
      );
    }
    lines.addAll(importanceLines(a.importance, input.features));
    final (base, permutation) = permutationImportance(
      a.rounds,
      input.test,
      input.features.length,
      p.permutations,
      rng,
    );
    lines.add(
      'permutation repeats ${p.permutations} base $base/${input.test.length}',
    );
    for (var rank = 0; rank < permutation.length; rank++) {
      final v = permutation[rank];
      lines.add(
        '${rank + 1} ${input.features[v.feature]} drop ${ratio(v.drop, p.permutations * input.test.length)} min ${v.minimum}/${input.test.length} max ${v.maximum}/${input.test.length}',
      );
    }
    sections.add(lines);
  }
  return separateSections(sections);
}

List<String> shapeLines(Inputs input, List<VariantAnalysis> analysis) {
  final sections = <List<String>>[];
  for (final a in analysis) {
    final lines = <String>['variant ${a.name} rounds ${a.rounds.length}'];
    for (var j = 0; j < input.features.length; j++) {
      final collected = a.rounds.where((r) => r.stump.feature == j).toList();
      final cuts = collected.expand((r) => r.stump.thresholds).toSet().toList()
        ..sort();
      final values = List.filled(cuts.length + 1, 0.0);
      for (final r in collected) {
        values[0] += r.stump.values[0];
      }
      for (var k = 0; k < cuts.length; k++) {
        for (final r in collected) {
          var index = 0;
          while (index < r.stump.thresholds.length &&
              r.stump.thresholds[index] <= cuts[k]) {
            index++;
          }
          values[k + 1] += r.stump.values[index];
        }
      }
      lines.add(
        'feature ${input.features[j]} rounds ${collected.length} cuts ${cuts.length} range ${number(maximum(values) - minimum(values))}',
      );
      for (var i = 0; i < values.length; i++) {
        lines.add(
          'interval ${i == 0 ? '-inf' : number(cuts[i - 1])} ${i == cuts.length ? 'inf' : number(cuts[i])} value ${number(values[i])}',
        );
      }
    }
    sections.add(lines);
  }
  return separateSections(sections);
}

List<String> calibrationLines(
  String variant,
  List<Row> rows,
  List<double> scores,
) {
  final counts = List.filled(5, 0),
      positive = List.filled(5, 0),
      totals = List.filled(5, 0.0);
  var brier = 0.0;
  for (var i = 0; i < rows.length; i++) {
    final p = 1 / (1 + exp(-2 * scores[i])),
        target = rows[i].label == 1 ? 1 : 0,
        d = p - target;
    brier += d * d;
    final b = min(4, (p * 5).floor());
    counts[b]++;
    totals[b] += p;
    positive[b] += target;
  }
  final lines = <String>[
    'calibration $variant brier ${number(brier / rows.length)}',
  ];
  final ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0'];
  for (var b = 0; b < 5; b++) {
    lines.add(
      'bin ${ranges[b]} count ${counts[b]} mean ${ratioReal(totals[b], counts[b].toDouble())} positives ${positive[b]}',
    );
  }
  return lines;
}

List<String> comparisonLines(Inputs input, List<VariantAnalysis> analysis) {
  final wrong = <String>[];
  for (var i = 0; i < input.test.length; i++) {
    if (analysis.every((a) => prediction(a.test[i]) != input.test[i].label)) {
      wrong.add(input.test[i].id);
    }
  }
  final lines = <String>[
    'all_wrong ${wrong.length}${wrong.isEmpty ? '' : ' ${wrong.join(' ')}'}',
    'agreement',
  ];
  for (var i = 0; i < analysis.length; i++) {
    final a = analysis[i];
    for (final b in analysis.skip(i + 1)) {
      var agree = 0, first = 0, second = 0;
      for (var j = 0; j < input.test.length; j++) {
        final x = prediction(a.test[j]),
            y = prediction(b.test[j]),
            label = input.test[j].label;
        if (x == y) {
          agree++;
        }
        if (x == label && y != label) {
          first++;
        }
        if (y == label && x != label) {
          second++;
        }
      }
      final d = (first - second).abs() - 1;
      lines.add(
        '${a.name} ${b.name} agree $agree/${input.test.length} only_first $first only_second $second chi2 ${ratio(d * d, first + second)}',
      );
    }
  }
  return lines;
}

List<String> bootstrapLines(Inputs input, List<VariantAnalysis> analysis) {
  final p = input.params, rng = Minstd(input.params.bootstrapSeed);
  final counts = List.generate(
    analysis.length,
    (_) => List.filled(p.bootstrap, 0),
  );
  for (var b = 0; b < p.bootstrap; b++) {
    final selected = List.generate(
      input.test.length,
      (_) => rng.draw() % input.test.length,
    );
    for (var v = 0; v < analysis.length; v++) {
      for (final i in selected) {
        if (prediction(analysis[v].test[i]) == input.test[i].label) {
          counts[v][b]++;
        }
      }
    }
  }
  final lines = <String>[
        'bootstrap samples ${p.bootstrap} seed ${p.bootstrapSeed}',
      ],
      trim = p.bootstrap ~/ 40;
  for (var v = 0; v < analysis.length; v++) {
    final ordered = List<int>.of(counts[v])..sort();
    final total = ordered.fold(0, (a, b) => a + b);
    lines.add(
      '${analysis[v].name} mean ${ratio(total, p.bootstrap * input.test.length)} low ${ratio(ordered[trim], input.test.length)} high ${ratio(ordered[p.bootstrap - trim - 1], input.test.length)}',
    );
  }
  for (var a = 0; a < analysis.length; a++) {
    for (var b = a + 1; b < analysis.length; b++) {
      var first = 0, tie = 0, second = 0;
      for (var j = 0; j < p.bootstrap; j++) {
        if (counts[a][j] > counts[b][j]) {
          first++;
        } else if (counts[a][j] == counts[b][j]) {
          tie++;
        } else {
          second++;
        }
      }
      lines.add(
        '${analysis[a].name} ${analysis[b].name} first $first tie $tie second $second',
      );
    }
  }
  return lines;
}

String featureSummary(List<Row> rows, int feature) {
  final values = [for (final row in rows) row.values[feature]];
  return '${number(minimum(values))} ${number(maximum(values))} ${number(sum(values) / rows.length)} ${values.toSet().length}';
}

int positiveCount(List<Row> rows) => rows.where((r) => r.label == 1).length;
(CurvePoint, CurvePoint) curveMinima(List<CurvePoint> curve) {
  var train = curve.first, test = curve.first;
  for (final c in curve.skip(1)) {
    if (c.trainErrors < train.trainErrors) {
      train = c;
    }
    if (c.testErrors < test.testErrors) {
      test = c;
    }
  }
  return (train, test);
}

List<String> summaryLines(
  Inputs input,
  List<VariantAnalysis> analysis,
  CrossValidation cv,
) {
  final n = input.train.length, m = input.test.length;
  final lines = <String>[
    'data train $n test $m features ${input.features.length} positives ${positiveCount(input.train)} ${positiveCount(input.test)}',
  ];
  for (var j = 0; j < input.features.length; j++) {
    lines.add(
      'feature ${input.features[j]} train ${featureSummary(input.train, j)} test ${featureSummary(input.test, j)}',
    );
  }
  final errors = cv.errors[cv.selected - 1];
  lines.add(
    'cv selected ${cv.selected} errors $errors/$n rate ${ratio(errors, n)}',
  );
  lines.add(
    metricsLine('oof', 'discrete', cv.selected, input.train, cv.scores),
  );
  final ct = List.filled(n, 0.0), ce = List.filled(m, 0.0);
  var rounds = 0;
  for (final a in analysis) {
    lines.add(
      metricsLine('train', a.name, a.rounds.length, input.train, a.train),
    );
    lines.add(metricsLine('test', a.name, a.rounds.length, input.test, a.test));
    rounds += a.rounds.length;
    for (var i = 0; i < n; i++) {
      ct[i] += a.train[i] / a.scale;
    }
    for (var i = 0; i < m; i++) {
      ce[i] += a.test[i] / a.scale;
    }
  }
  lines.add(metricsLine('train', 'committee', rounds, input.train, ct));
  lines.add(metricsLine('test', 'committee', rounds, input.test, ce));
  for (final a in analysis) {
    final (train, test) = curveMinima(a.curve);
    lines.add(
      'curve ${a.name} rounds ${a.curve.length} train_min ${train.trainErrors}/$n at ${train.round} test_min ${test.testErrors}/$m at ${test.round}',
    );
  }
  lines.addAll(comparisonLines(input, analysis));
  lines.addAll(bootstrapLines(input, analysis));
  for (final a in analysis) {
    lines.addAll(calibrationLines(a.name, input.test, a.test));
  }
  return lines;
}

int classPrediction(List<double> scores) {
  var best = 0;
  for (var k = 1; k < scores.length; k++) {
    if (scores[k] > scores[best]) {
      best = k;
    }
  }
  return best + 1;
}

List<int> classPredictions(List<List<double>> scores) =>
    scores.map(classPrediction).toList();
int classErrors(List<Row> rows, List<int> predictions) {
  var count = 0;
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].label != predictions[i]) {
      count++;
    }
  }
  return count;
}

(List<List<double>>, List<List<double>>, List<(int, int, int)>)
sammeProgression(
  List<Round> rounds,
  List<Row> training,
  List<Row> testing,
  int classes,
) {
  final train = List.generate(
        training.length,
        (_) => List.filled(classes, 0.0),
      ),
      test = List.generate(testing.length, (_) => List.filled(classes, 0.0)),
      curve = <(int, int, int)>[];
  for (var t = 0; t < rounds.length; t++) {
    final r = rounds[t];
    for (var i = 0; i < training.length; i++) {
      train[i][r.stump.output(training[i].values).toInt() - 1] += r.alpha;
    }
    for (var i = 0; i < testing.length; i++) {
      test[i][r.stump.output(testing[i].values).toInt() - 1] += r.alpha;
    }
    curve.add((
      t + 1,
      classErrors(training, classPredictions(train)),
      classErrors(testing, classPredictions(test)),
    ));
  }
  return (train, test, curve);
}

List<String> confusionLines(
  List<Row> rows,
  List<int> predictions,
  int classes,
) {
  final matrix = confusion(rows, predictions, classes),
      lines = <String>['confusion'];
  for (final row in matrix) {
    lines.add(ints(row));
  }
  for (var c = 0; c < classes; c++) {
    var predicted = 0, actual = 0;
    for (var k = 0; k < classes; k++) {
      predicted += matrix[k][c];
      actual += matrix[c][k];
    }
    lines.add(
      'class ${c + 1} precision ${ratio(matrix[c][c], predicted)} recall ${ratio(matrix[c][c], actual)}',
    );
  }
  return lines;
}

List<Row> binaryRows(List<Row> rows, int classNumber) => [
  for (final r in rows) Row(r.id, r.values, r.label == classNumber ? 1 : -1),
];
(List<String>, List<(int, int, int)>) multiclassReport(Inputs input) {
  final p = input.params,
      training = input.multiTrain,
      testing = input.multiTest;
  final model = trainSamme(training, p.sammeRounds, p.classes);
  final (trainScores, testScores, curve) = sammeProgression(
    model.rounds,
    training,
    testing,
    p.classes,
  );
  final trainPred = classPredictions(trainScores),
      testPred = classPredictions(testScores);
  final lines = <String>[
    'samme classes ${p.classes} train ${training.length} test ${testing.length} rounds ${model.rounds.length} stop ${model.stop}',
  ];
  for (var t = 0; t < model.rounds.length; t++) {
    final r = model.rounds[t], s = r.stump;
    lines.add(
      'round ${t + 1} feature ${input.multiFeatures[s.feature]} threshold ${number(s.thresholds[0])} left ${s.values[0].toInt()} right ${s.values[1].toInt()} error ${number(r.error)} alpha ${number(r.alpha)}',
    );
  }
  var te = classErrors(training, trainPred),
      ve = classErrors(testing, testPred);
  lines.add(
    'train errors $te/${training.length} rate ${ratio(te, training.length)}',
  );
  lines.add(
    'test errors $ve/${testing.length} rate ${ratio(ve, testing.length)}',
  );
  lines.addAll(confusionLines(testing, testPred, p.classes));
  lines.addAll(
    importanceLines(
      Importance(model.rounds, input.multiFeatures.length, true),
      input.multiFeatures,
    ),
  );
  lines.addAll(['', 'ovr classes ${p.classes} rounds ${p.sammeRounds}']);
  final ovrTrain = List.generate(
        training.length,
        (_) => List.filled(p.classes, 0.0),
      ),
      ovrTest = List.generate(
        testing.length,
        (_) => List.filled(p.classes, 0.0),
      );
  for (var c = 1; c <= p.classes; c++) {
    final bt = binaryRows(training, c),
        bv = binaryRows(testing, c),
        bm = trainDiscrete(bt, p.sammeRounds);
    final ts = scoreRows(bm.rounds, bt), vs = scoreRows(bm.rounds, bv);
    for (var i = 0; i < ts.length; i++) {
      ovrTrain[i][c - 1] = ts[i];
    }
    for (var i = 0; i < vs.length; i++) {
      ovrTest[i][c - 1] = vs[i];
    }
    lines.add(
      'class $c rounds ${bm.rounds.length} stop ${bm.stop} positives ${positiveCount(bt)} train_errors ${countErrors(bt, ts)}/${training.length} test_errors ${countErrors(bv, vs)}/${testing.length}',
    );
  }
  final ovrTrainPred = classPredictions(ovrTrain),
      ovrTestPred = classPredictions(ovrTest);
  te = classErrors(training, ovrTrainPred);
  ve = classErrors(testing, ovrTestPred);
  lines.add(
    'train errors $te/${training.length} rate ${ratio(te, training.length)}',
  );
  lines.add(
    'test errors $ve/${testing.length} rate ${ratio(ve, testing.length)}',
  );
  lines.addAll(confusionLines(testing, ovrTestPred, p.classes));
  var agreement = 0;
  for (var i = 0; i < testPred.length; i++) {
    if (testPred[i] == ovrTestPred[i]) {
      agreement++;
    }
  }
  lines.addAll(['agreement $agreement/${testing.length}', '', 'predictions']);
  for (var i = 0; i < testing.length; i++) {
    lines.add(
      '${testing[i].id} class ${testing[i].label} samme ${testPred[i]} ovr ${ovrTestPred[i]} scores ${numberList(testScores[i])}',
    );
  }
  return (lines, curve);
}

(int, int) modelErrors(Model model, List<Row> training, List<Row> testing) => (
  countErrors(training, scoreRows(model.rounds, training)),
  countErrors(testing, scoreRows(model.rounds, testing)),
);
(int, int) testMinimum(List<Round> rounds, List<Row> testing) {
  final scores = List.filled(testing.length, 0.0);
  var minimum = testing.length + 1, at = 0;
  for (var t = 0; t < rounds.length; t++) {
    addRoundScores(rounds[t], testing, scores);
    final errors = countErrors(testing, scores);
    if (errors < minimum) {
      minimum = errors;
      at = t + 1;
    }
  }
  return (minimum, at);
}

List<Row> reducedRows(List<Row> rows, List<int> features) => [
  for (final row in rows)
    Row(row.id, [for (final f in features) row.values[f]], row.label),
];
List<String> experimentLines(
  Inputs input,
  List<VariantAnalysis> analysis,
  int selected,
) {
  final p = input.params,
      n = input.train.length,
      m = input.test.length,
      lines = <String>[];
  for (final q in p.sizes) {
    final size = n * q ~/ 100, subset = input.train.sublist(0, n * q ~/ 100);
    lines.add('size $q rows $size');
    for (final name in p.variants) {
      final model = trainVariant(name, subset, p);
      final (te, ve) = modelErrors(model, subset, input.test);
      lines.add(
        '$name rounds ${model.rounds.length} stop ${model.stop} train_errors $te/$size test_errors $ve/$m',
      );
    }
  }
  for (final nu in p.shrinkage) {
    final model = trainDiscrete(input.train, p.rounds, shrinkage: nu);
    final (te, ve) = modelErrors(model, input.train, input.test);
    final (minimum, at) = testMinimum(model.rounds, input.test);
    lines.add(
      'shrinkage ${number(nu)} rounds ${model.rounds.length} stop ${model.stop} train_errors $te/$n test_errors $ve/$m test_min $minimum/$m at $at',
    );
  }
  final ranked = analysis
      .firstWhere((a) => a.name == 'discrete')
      .importance
      .order;
  for (var count = 1; count <= input.features.length; count++) {
    final features = ranked.take(count).toList()..sort();
    final training = reducedRows(input.train, features),
        testing = reducedRows(input.test, features);
    final model = trainDiscrete(training, selected);
    final (te, ve) = modelErrors(model, training, testing);
    final names = [for (final j in features) input.features[j]];
    lines.add(
      'top $count features ${names.join(' ')} rounds ${model.rounds.length} train_errors $te/$n test_errors $ve/$m',
    );
  }
  for (final q in p.noise) {
    final count = n * q ~/ 100,
        rng = Minstd(p.noiseSeed),
        permutation = List.generate(n, (i) => i);
    for (var i = 0; i < count; i++) {
      final other = rng.draw() % (n - i) + i, old = permutation[i];
      permutation[i] = permutation[other];
      permutation[other] = old;
    }
    final flipped = List.filled(n, false);
    for (final i in permutation.take(count)) {
      flipped[i] = true;
    }
    final noisy = [
      for (var i = 0; i < n; i++)
        Row(
          input.train[i].id,
          input.train[i].values,
          flipped[i] ? -input.train[i].label : input.train[i].label,
        ),
    ];
    lines.add('noise $q flipped $count');
    for (final name in p.variants) {
      final model = trainVariant(name, noisy, p);
      final (te, ve) = modelErrors(model, noisy, input.test);
      final (minimum, at) = testMinimum(model.rounds, input.test);
      var weight = 0.0;
      for (var i = 0; i < n; i++) {
        if (flipped[i]) {
          weight += model.rounds.last.weights[i];
        }
      }
      lines.add(
        '$name rounds ${model.rounds.length} stop ${model.stop} train_errors $te/$n test_errors $ve/$m test_min $minimum/$m at $at flipped_weight ${number(weight)}',
      );
    }
  }
  return lines;
}

List<String> separateSections(List<List<String>> sections) {
  final lines = <String>[];
  for (final section in sections) {
    if (lines.isNotEmpty) {
      lines.add('');
    }
    lines.addAll(section);
  }
  return lines;
}

void main() {
  final input = readInputs(), cv = crossValidate(input.train, input.params);
  final analysis = analyzeVariants(input, cv.selected);
  final (samme, curve) = multiclassReport(input);
  writeLines('ensemble.txt', ensembleLines(input, analysis, cv));
  writeLines('error_curve.csv', errorCurveLines(input, analysis, curve));
  writeLines('predictions.csv', predictionLines(input, analysis));
  writeLines('roc.csv', rocLines(input, analysis));
  writeLines('margins.txt', marginLines(input, analysis));
  writeLines('shapes.txt', shapeLines(input, analysis));
  writeLines('samme.txt', samme);
  writeLines('summary.txt', summaryLines(input, analysis, cv));
  writeLines('experiments.txt', experimentLines(input, analysis, cv.selected));
}
