import 'dart:io';
import 'dart:math' as math;
import 'dataset.dart';
import 'logistic.dart';
import 'optimizers.dart';
import 'metrics.dart';
import 'softmax.dart';

String f4(double value) => fixed(value, 4);
String f6(double value) => fixed(value, 6);
String line(List<Object> parts) => parts.join(' ');
String realText(Iterable<double> values, int places) =>
    values.map((v) => fixed(v, places)).join(' ');
double sequentialSum(Iterable<double> values) {
  var total = 0.0;
  for (final v in values) {
    total += v;
  }
  return total;
}

int sum(Iterable<int> values) =>
    values.fold(0, (total, value) => total + value);
double length(Iterable<double> values) =>
    math.sqrt(sequentialSum(values.map((v) => v * v)));
int countEqual(List<int> a, List<int> b) => [
  for (var i = 0; i < a.length; i++)
    if (a[i] == b[i]) i,
].length;
List<int> predict(List<double> p, double threshold) =>
    p.map((v) => v >= threshold ? 1 : 0).toList();
List<double> probabilities(List<double> w, List<List<double>> x) =>
    x.map((v) => probability(score(w, v))).toList();
List<int> targets(List<int> labels, int classNumber) =>
    labels.map((label) => label == classNumber ? 1 : 0).toList();
List<List<double>> firstColumns(List<List<double>> rows, int count) =>
    rows.map((row) => row.take(count).toList()).toList();
List<List<double>> inverse(List<List<double>> a) {
  final n = a.length, lower = cholesky(a), result = matrix(a.length, a.length);
  for (var k = 0; k < n; k++) {
    final unit = List.filled(n, 0.0);
    unit[k] = 1;
    final column = solve(lower, unit);
    for (var j = 0; j < n; j++) {
      result[j][k] = column[j];
    }
  }
  return result;
}

List<double> originalUnits(List<double> w, Statistics stats) {
  final result = List.filled(w.length, 0.0);
  var shift = 0.0;
  for (var j = 1; j < w.length; j++) {
    result[j] = w[j] / stats.deviations[j - 1];
    shift += result[j] * stats.means[j - 1];
  }
  result[0] = w[0] - shift;
  return result;
}

void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
void writeParts(String name, List<List<String>> parts) => writeLines(name, [
  for (var i = 0; i < parts.length; i++) ...[if (i > 0) '', ...parts[i]],
]);

class Data {
  final List<String> names;
  final List<Example> train, test;
  final Settings settings;
  late final List<List<int>> tuples;
  late final List<String> featureNames;
  late final int count, classes;
  late final List<int> degreeCounts,
      trainTargets,
      testTargets,
      trainLabels,
      testLabels;
  late final List<List<double>> trainExpanded,
      testExpanded,
      trainVectors,
      testVectors;
  late final Statistics overall;
  late final List<double> meanValues;
  Data(this.names, this.train, this.test, this.settings) {
    tuples = expansionTuples(names.length, settings.integer('DEGREE'));
    count = tuples.length;
    featureNames = expandedNames(names, tuples);
    degreeCounts = [
      for (var degree = 1; degree <= settings.integer('DEGREE'); degree++)
        tuples.where((t) => t.length <= degree).length,
    ];
    trainLabels = train.map((row) => row.label).toList();
    testLabels = test.map((row) => row.label).toList();
    classes = trainLabels.reduce(math.max) + 1;
    trainExpanded = train
        .map((row) => expandedValues(tuples, row.values))
        .toList();
    testExpanded = test
        .map((row) => expandedValues(tuples, row.values))
        .toList();
    overall = computeStatistics(trainExpanded, count);
    trainVectors = standardizedRows(trainExpanded, overall, count);
    testVectors = standardizedRows(testExpanded, overall, count);
    trainTargets = targets(trainLabels, settings.integer('POSITIVE'));
    testTargets = targets(testLabels, settings.integer('POSITIVE'));
    meanValues = overall.means.take(names.length).toList();
  }
  List<double> vector(List<double> values) =>
      standardize(expandedValues(tuples, values), overall, count);
  (double, double) range(int base) {
    final column = train.map((row) => row.values[base]).toList();
    return (column.reduce(math.min), column.reduce(math.max));
  }
}

class CrossValidation {
  final double lambda, loss;
  final List<double> foldLosses, probabilities;
  final int errors;
  CrossValidation(
    this.lambda,
    this.loss,
    this.foldLosses,
    this.probabilities,
    this.errors,
  );
}

CrossValidation crossValidate(Data d, double lambda, int count) {
  final losses = List.filled(d.train.length, 0.0),
      p = List.filled(d.train.length, 0.0),
      foldLosses = <double>[];
  var errors = 0;
  for (var fold = 0; fold < 5; fold++) {
    final fitting = [
          for (var i = 0; i < d.train.length; i++)
            if (i % 5 != fold) i,
        ],
        checking = [
          for (var i = 0; i < d.train.length; i++)
            if (i % 5 == fold) i,
        ];
    final rows = fitting.map((i) => d.trainExpanded[i]).toList(),
        y = fitting.map((i) => d.trainTargets[i]).toList();
    final stats = computeStatistics(rows, count);
    final w = finalWeights(
      newtonMethod(standardizedRows(rows, stats, count), y, lambda),
    );
    var total = 0.0;
    for (final i in checking) {
      final u = score(w, standardize(d.trainExpanded[i], stats, count));
      losses[i] = loss(u, d.trainTargets[i]);
      p[i] = probability(u);
      total += losses[i];
      if ((p[i] >= d.settings.real('THRESHOLD') ? 1 : 0) != d.trainTargets[i])
        errors++;
    }
    foldLosses.add(total / checking.length);
  }
  return CrossValidation(
    lambda,
    sequentialSum(losses) / losses.length,
    foldLosses,
    p,
    errors,
  );
}

class Evaluation {
  late final List<double> probabilities;
  late final List<int> predictions;
  late final double loss;
  late final int correct;
  late final Fraction area;
  Evaluation(
    List<double> w,
    List<List<double>> x,
    List<int> y,
    double threshold,
  ) {
    probabilities = x.map((v) => probability(score(w, v))).toList();
    predictions = predict(probabilities, threshold);
    loss = averageLoss(w, x, y);
    correct = countEqual(predictions, y);
    area = auc(probabilities, y);
  }
}

class BinaryModel {
  final String name;
  final List<Checkpoint> checkpoints;
  late final List<double> weights;
  late final Evaluation train, test;
  late final List<RocPoint> roc;
  BinaryModel(this.name, this.checkpoints, Data d) {
    weights = finalWeights(checkpoints);
    final threshold = d.settings.real('THRESHOLD');
    train = Evaluation(weights, d.trainVectors, d.trainTargets, threshold);
    test = Evaluation(weights, d.testVectors, d.testTargets, threshold);
    roc = rocPoints(test.probabilities, d.testTargets);
  }
}

class SoftmaxModel {
  final List<SoftCheckpoint> checkpoints;
  late final List<List<double>> weights, probabilities;
  late final List<int> predictions;
  SoftmaxModel(this.checkpoints, Data d) {
    weights = checkpoints.last.$2;
    probabilities = d.testVectors
        .map((v) => softmaxProbabilities(weights, v))
        .toList();
    predictions = probabilities.map(predictedClass).toList();
  }
}

class Influence {
  late final List<List<double>> inverseHessian;
  final probabilities = <double>[],
      leverages = <double>[],
      residuals = <double>[],
      distances = <double>[];
  late final double edf, deviance, aic, bic;
  Influence(List<double> w, List<List<double>> x, List<int> y, double lambda) {
    inverseHessian = inverse(hessian(w, x, lambda));
    for (var i = 0; i < x.length; i++) {
      final v = x[i], p = probability(score(w, x[i]));
      final variance = p * (1 - p);
      var quadratic = 0.0;
      for (var j = 0; j < w.length; j++) {
        for (var k = 0; k < w.length; k++) {
          quadratic += v[j] * inverseHessian[j][k] * v[k];
        }
      }
      final leverage = variance * quadratic / x.length,
          pearson = (y[i] - p) / math.sqrt(variance);
      probabilities.add(p);
      leverages.add(leverage);
      residuals.add(pearson / math.sqrt(1 - leverage));
      distances.add(
        pearson *
            pearson *
            leverage /
            (w.length * ((1 - leverage) * (1 - leverage))),
      );
    }
    edf = sequentialSum(leverages);
    deviance = 2 * x.length * averageLoss(w, x, y);
    aic = deviance + 2 * edf;
    bic = deviance + math.log(x.length) * edf;
  }
}

class Bin {
  int count = 0, hits = 0;
  double total = 0;
}

int binIndex(double p) => math.min(9, (p * 10).floor());
List<Bin> fillBins(List<double> p, List<int> y) {
  final bins = List.generate(10, (_) => Bin());
  for (var i = 0; i < p.length; i++) {
    final b = bins[binIndex(p[i])];
    b.count++;
    b.total += p[i];
    b.hits += y[i];
  }
  return bins;
}

List<String> binLines(List<Bin> bins, String meanLabel, String rateLabel) => [
  for (var i = 0; i < bins.length; i++)
    line([
      'bin',
      '${(i / 10).toStringAsFixed(1)}-${((i + 1) / 10).toStringAsFixed(1)}',
      'count',
      bins[i].count,
      meanLabel,
      bins[i].count == 0 ? '-' : f4(bins[i].total / bins[i].count),
      rateLabel,
      ratio(bins[i].hits, bins[i].count),
    ]),
];
double calibrationError(List<Bin> bins, int n) =>
    sequentialSum(
      bins.where((b) => b.count > 0).map((b) => (b.total - b.hits).abs()),
    ) /
    n;
List<String> termLines(List<String> names, List<double> w, Statistics stats) {
  final original = originalUnits(w, stats), terms = ['intercept', ...names];
  return [
    for (var j = 0; j < w.length; j++)
      'term ${terms[j]} standardized ${f4(w[j])} original ${f4(original[j])}',
  ];
}

List<List<String>> weightsParts(
  Data d,
  List<BinaryModel> models,
  SoftmaxModel soft,
  Influence influence,
  double lambda,
) {
  final n = d.train.length, p = d.count, correlation = matrix(d.count, d.count);
  for (var j = 0; j < p; j++) {
    for (var k = 0; k < p; k++) {
      var total = 0.0;
      for (final v in d.trainVectors) {
        total += v[j + 1] * v[k + 1];
      }
      correlation[j][k] = total / (n - 1);
    }
  }
  final vif = inverse(correlation),
      feature = [
        'features ${d.names.length} degree ${d.settings.integer('DEGREE')} expanded $p',
        'standardization',
      ];
  for (var j = 0; j < p; j++) {
    feature.add(
      '${d.featureNames[j]} mean ${f6(d.overall.means[j])} sd ${f6(d.overall.deviations[j])} vif ${f4(vif[j][j])}',
    );
  }
  feature.add('correlation');
  feature.addAll(correlation.map((row) => realText(row, 4)));
  final parts = [feature], nw = models[2].weights;
  for (final m in models) {
    final lines = [
      'model ${m.name} lambda ${f4(lambda)}',
      ...termLines(d.featureNames, m.weights, d.overall),
      'norm ${f4(length(m.weights.skip(1)))}',
    ];
    if (m.name != 'newton')
      lines.add(
        'distance_to_newton ${f6(length([for (var j = 0; j < nw.length; j++) m.weights[j] - nw[j]]))}',
      );
    parts.add(lines);
  }
  final coefficients = ['coefficients newton lambda ${f4(lambda)}'],
      terms = ['intercept', ...d.featureNames];
  for (var j = 0; j < nw.length; j++) {
    final w = nw[j], se = math.sqrt(influence.inverseHessian[j][j] / n);
    coefficients.add(
      line([
        terms[j],
        'weight',
        f4(w),
        'se',
        f4(se),
        'z',
        f4(w / se),
        'lower',
        f4(w - 1.96 * se),
        'upper',
        f4(w + 1.96 * se),
        'odds_ratio',
        f4(math.exp(w)),
      ]),
    );
  }
  parts.add(coefficients);
  final softLines = [
    'model softmax lambda ${f4(d.settings.real('SOFTMAX', 2))}',
  ];
  for (var k = 0; k < soft.weights.length; k++) {
    softLines.add('class $k');
    softLines.addAll(termLines(d.featureNames, soft.weights[k], d.overall));
  }
  parts.add(softLines);
  return parts;
}

List<String> traceLines(
  Data d,
  List<BinaryModel> models,
  SoftmaxModel soft,
  double lambda,
) {
  final lines = ['optimizer,iteration,loss,gradient_norm,test_loss'];
  for (final m in models) {
    for (final (t, w) in m.checkpoints) {
      lines.add(
        '${m.name},$t,${f6(objective(w, d.trainVectors, d.trainTargets, lambda))},${f6(length(gradient(w, d.trainVectors, d.trainTargets, lambda)))},${f6(averageLoss(w, d.testVectors, d.testTargets))}',
      );
    }
  }
  final l = d.settings.real('SOFTMAX', 2);
  for (final (t, w) in soft.checkpoints) {
    final g = softmaxGradient(w, d.trainVectors, d.trainLabels, l);
    lines.add(
      'softmax,$t,${f6(softmaxObjective(w, d.trainVectors, d.trainLabels, l))},${f6(length(g.expand((row) => row)))},${f6(softmaxAverage(w, d.testVectors, d.testLabels))}',
    );
  }
  return lines;
}

List<String> predictionLines(
  Data d,
  List<BinaryModel> models,
  SoftmaxModel soft,
) {
  final lines = ['id,model,probability,predicted,actual'];
  for (final m in models) {
    for (var j = 0; j < d.test.length; j++) {
      lines.add(
        '${d.test[j].ident},${m.name},${f6(m.test.probabilities[j])},${m.test.predictions[j]},${d.testTargets[j]}',
      );
    }
  }
  for (var j = 0; j < d.test.length; j++) {
    final k = soft.predictions[j];
    lines.add(
      '${d.test[j].ident},softmax,${f6(soft.probabilities[j][k])},$k,${d.testLabels[j]}',
    );
  }
  return lines;
}

List<String> rocLines(Data d, List<BinaryModel> models) {
  final pos = sum(d.testTargets),
      neg = d.test.length - sum(d.testTargets),
      lines = ['model,threshold,tpr,fpr,precision'];
  for (final m in models) {
    lines.add('${m.name},inf,0.0000,0.0000,-');
    for (final p in m.roc) {
      lines.add(
        '${m.name},${f6(p.threshold)},${ratio(p.tp, pos)},${ratio(p.fp, neg)},${ratio(p.tp, p.tp + p.fp)}',
      );
    }
  }
  return lines;
}

List<String> dataPart(Data d) {
  final train = List.filled(d.classes, 0), test = List.filled(d.classes, 0);
  for (final k in d.trainLabels) {
    train[k]++;
  }
  for (final k in d.testLabels) {
    test[k]++;
  }
  return [
    'data train ${d.train.length} test ${d.test.length} base_features ${d.names.length} degree ${d.settings.integer('DEGREE')} features ${d.count}',
    'binary positive_class ${d.settings.integer('POSITIVE')} train ${sum(d.trainTargets)}/${d.train.length} test ${sum(d.testTargets)}/${d.test.length}',
    'classes ${d.classes} train ${train.join(' ')} test ${test.join(' ')}',
  ];
}

List<String> crossValidationPart(
  Data d,
  List<CrossValidation> results,
  CrossValidation best,
  double se,
  double oneSE,
) {
  final n = d.train.length,
      lines = ['cross_validation folds 5 newton_iterations 10'];
  for (final r in results) {
    lines.add(
      'lambda ${f4(r.lambda)} fold_loss ${realText(r.foldLosses, 6)} cv_loss ${f6(r.loss)} errors ${r.errors}/$n',
    );
  }
  lines.add(
    'selected lambda ${f4(best.lambda)} cv_loss ${f6(best.loss)} se ${f6(se)} lambda_1se ${f4(oneSE)}',
  );
  final c = Confusion(
    predict(best.probabilities, d.settings.real('THRESHOLD')),
    d.trainTargets,
  );
  lines.add(
    'out_of_fold tp ${c.tp} fp ${c.fp} tn ${c.tn} fn ${c.fn} accuracy ${ratio(c.tp + c.tn, n)} auc ${auc(best.probabilities, d.trainTargets).text()}',
  );
  return lines;
}

List<String> lambdaPathPart(Data d) {
  final lines = ['lambda_path'];
  for (var i = 0; i < d.settings.fields['LAMBDAS']!.length; i++) {
    final l = d.settings.real('LAMBDAS', i),
        threshold = d.settings.real('THRESHOLD');
    final w = finalWeights(newtonMethod(d.trainVectors, d.trainTargets, l));
    final train = Evaluation(w, d.trainVectors, d.trainTargets, threshold),
        test = Evaluation(w, d.testVectors, d.testTargets, threshold);
    lines.add(
      line([
        'lambda',
        f4(l),
        'objective',
        f6(objective(w, d.trainVectors, d.trainTargets, l)),
        'train_loss',
        f6(train.loss),
        'test_loss',
        f6(test.loss),
        'train_accuracy',
        ratio(train.correct, d.train.length),
        'test_accuracy',
        ratio(test.correct, d.test.length),
        'norm',
        f4(length(w.skip(1))),
      ]),
    );
  }
  return lines;
}

List<String> degreePart(Data d, double l) {
  final lines = ['degrees lambda ${f4(l)}'];
  for (var i = 0; i < d.degreeCounts.length; i++) {
    final q = d.degreeCounts[i],
        x = firstColumns(d.trainVectors, d.degreeCounts[i] + 1),
        z = firstColumns(d.testVectors, d.degreeCounts[i] + 1);
    final w = finalWeights(newtonMethod(x, d.trainTargets, l)),
        cv = crossValidate(d, l, q),
        threshold = d.settings.real('THRESHOLD');
    final train = Evaluation(w, x, d.trainTargets, threshold),
        test = Evaluation(w, z, d.testTargets, threshold),
        influence = Influence(w, x, d.trainTargets, l);
    lines.add(
      line([
        'degree',
        i + 1,
        'features',
        q,
        'cv_loss',
        f6(cv.loss),
        'train_loss',
        f6(train.loss),
        'test_loss',
        f6(test.loss),
        'test_accuracy',
        ratio(test.correct, d.test.length),
        'auc',
        test.area.text(),
        'edf',
        f4(influence.edf),
        'aic',
        f4(influence.aic),
        'bic',
        f4(influence.bic),
      ]),
    );
  }
  return lines;
}

List<String> learningPart(Data d, double l) {
  final lines = ['learning_curve lambda ${f4(l)}'];
  for (var k = 1; k <= 4; k++) {
    final n = k * d.train.length ~/ 4,
        rows = d.trainExpanded.take(k * d.train.length ~/ 4).toList();
    final stats = computeStatistics(rows, d.count),
        y = d.trainTargets.take(n).toList(),
        threshold = d.settings.real('THRESHOLD');
    final x = standardizedRows(rows, stats, d.count),
        z = standardizedRows(d.testExpanded, stats, d.count);
    final w = finalWeights(newtonMethod(x, y, l));
    final train = Evaluation(w, x, y, threshold),
        test = Evaluation(w, z, d.testTargets, threshold);
    lines.add(
      'size $n train_loss ${f6(train.loss)} test_loss ${f6(test.loss)} test_accuracy ${ratio(test.correct, d.test.length)} auc ${test.area.text()}',
    );
  }
  return lines;
}

List<String> calibrationLines(List<double> p, List<int> y) {
  final bins = fillBins(p, y);
  final lines = [
    'calibration',
    ...binLines(bins, 'mean_probability', 'positive_rate'),
  ];
  var mce = 0.0, hl = 0.0, groups = 0;
  for (final b in bins) {
    if (b.count > 0) {
      groups++;
      mce = math.max(mce, (b.total / b.count - b.hits / b.count).abs());
      final difference = b.hits - b.total;
      hl += difference * difference / (b.total * (1 - b.total / b.count));
    }
  }
  lines.add(
    'ece ${f4(calibrationError(bins, y.length))} mce ${f4(mce)} hosmer_lemeshow ${f4(hl)} groups $groups',
  );
  return lines;
}

List<String> gainsLines(List<double> p, List<int> y) {
  final lines = ['gains'], order = ordered(p, true), pos = sum(y), n = y.length;
  for (var g = 1; g <= 10; g++) {
    final size = g * n ~/ 10,
        hits = sum(order.take(g * n ~/ 10).map((j) => y[j]));
    lines.add(
      'decile $g rows $size positives $hits gain ${ratio(hits, pos)} lift ${ratio(hits * n, size * pos)}',
    );
  }
  return lines;
}

List<String> binaryPart(Data d, BinaryModel m, double l) {
  final n = d.test.length,
      pos = sum(d.testTargets),
      neg = d.test.length - sum(d.testTargets),
      c = Confusion(m.test.predictions, d.testTargets);
  final brier =
      sequentialSum([
        for (var j = 0; j < n; j++)
          (m.test.probabilities[j] - d.testTargets[j]) *
              (m.test.probabilities[j] - d.testTargets[j]),
      ]) /
      n;
  var youden = m.roc.first,
      bestF1 = m.roc.first,
      cheapest = m.roc.first,
      ap = 0.0,
      previous = 0;
  int cost(RocPoint p) =>
      d.settings.integer('COST') * p.fp +
      d.settings.integer('COST', 1) * (pos - p.tp);
  for (final p in m.roc) {
    if (p.tp * neg - p.fp * pos > youden.tp * neg - youden.fp * pos) youden = p;
    if (p.tp * (pos + bestF1.tp + bestF1.fp) > bestF1.tp * (pos + p.tp + p.fp))
      bestF1 = p;
    if (cost(p) < cost(cheapest)) cheapest = p;
    ap += (p.tp - previous) * p.tp / (p.tp + p.fp);
    previous = p.tp;
  }
  ap /= pos;
  return [
    'model ${m.name} lambda ${f4(l)}',
    'train correct ${m.train.correct}/${d.train.length} accuracy ${ratio(m.train.correct, d.train.length)}',
    'test tp ${c.tp} fp ${c.fp} tn ${c.tn} fn ${c.fn}',
    'test accuracy ${ratio(c.tp + c.tn, n)} precision ${ratio(c.tp, c.tp + c.fp)} recall ${ratio(c.tp, c.tp + c.fn)} specificity ${ratio(c.tn, c.tn + c.fp)} f1 ${ratio(2 * c.tp, 2 * c.tp + c.fp + c.fn)}',
    'log_loss ${f6(m.test.loss)} brier ${f6(brier)}',
    'auc ${m.test.area.text()} average_precision ${f4(ap)}',
    'youden threshold ${f6(youden.threshold)} tpr ${ratio(youden.tp, pos)} fpr ${ratio(youden.fp, neg)} j ${ratio(youden.tp * neg - youden.fp * pos, pos * neg)}',
    'best_f1 threshold ${f6(bestF1.threshold)} precision ${ratio(bestF1.tp, bestF1.tp + bestF1.fp)} recall ${ratio(bestF1.tp, pos)} f1 ${ratio(2 * bestF1.tp, pos + bestF1.tp + bestF1.fp)}',
    'min_cost threshold ${f6(cheapest.threshold)} cost ${cost(cheapest)} fp ${cheapest.fp} fn ${pos - cheapest.tp}',
    ...calibrationLines(m.test.probabilities, d.testTargets),
    ...gainsLines(m.test.probabilities, d.testTargets),
  ];
}

List<String> comparisonPart(Data d, List<BinaryModel> models) {
  final lines = <String>[];
  for (final pair in [(0, 1), (0, 2), (1, 2)]) {
    final a = models[pair.$1], b = models[pair.$2];
    var onlyA = 0, onlyB = 0;
    for (var j = 0; j < d.test.length; j++) {
      final y = d.testTargets[j];
      if (a.test.predictions[j] == y && b.test.predictions[j] != y) onlyA++;
      if (b.test.predictions[j] == y && a.test.predictions[j] != y) onlyB++;
    }
    final gap = (onlyA - onlyB).abs() - 1;
    lines.add(
      'agreement ${a.name} ${b.name} same ${countEqual(a.test.predictions, b.test.predictions)}/${d.test.length} only_first $onlyA only_second $onlyB mcnemar ${ratio(gap * gap, onlyA + onlyB)}',
    );
  }
  return lines;
}

double slope(
  List<List<int>> tuples,
  List<double> original,
  List<double> values,
  int base,
) {
  var total = 0.0;
  for (var j = 0; j < tuples.length; j++) {
    var count = 0, removed = false, product = 1.0;
    for (final index in tuples[j]) {
      if (index == base) {
        count++;
        if (!removed) {
          removed = true;
          continue;
        }
      }
      product *= values[index];
    }
    if (count > 0) total += original[j + 1] * (count * product);
  }
  return total;
}

List<String> diagnosticsPart(
  Data d,
  BinaryModel m,
  Influence influence,
  double l,
) {
  final n = d.train.length,
      size = d.test.length,
      base = sum(d.trainTargets) / d.train.length;
  final nullLoss = -(base * math.log(base) + (1 - base) * math.log(1 - base));
  final lines = [
    'diagnostics newton lambda ${f4(l)}',
    line([
      'fit',
      'null_loss',
      f6(nullLoss),
      'train_loss',
      f6(m.train.loss),
      'mcfadden_r2',
      f4(1 - m.train.loss / nullLoss),
      'deviance',
      f4(influence.deviance),
      'edf',
      f4(influence.edf),
      'aic',
      f4(influence.aic),
      'bic',
      f4(influence.bic),
    ]),
  ];
  final order = ordered(influence.probabilities, false), groups = <String>[];
  var hl = 0.0;
  for (var g = 1; g <= 10; g++) {
    final members = order.sublist((g - 1) * n ~/ 10, g * n ~/ 10),
        observed = sum(
          order
              .sublist((g - 1) * n ~/ 10, g * n ~/ 10)
              .map((i) => d.trainTargets[i]),
        );
    final expected = sequentialSum(
      members.map((i) => influence.probabilities[i]),
    );
    final difference = observed - expected;
    hl +=
        difference * difference / (expected * (1 - expected / members.length));
    groups.add(
      'group $g rows ${members.length} observed $observed expected ${f4(expected)}',
    );
  }
  lines.addAll([
    'hosmer_lemeshow_train groups 10 statistic ${f4(hl)}',
    ...groups,
    'newton_iterations',
  ]);
  for (var t = 1; t <= 10; t++) {
    final w = m.checkpoints[t - 1].$2;
    final (g, step) = newtonDirection(w, d.trainVectors, d.trainTargets, l);
    final decrease =
        sequentialSum([for (var j = 0; j < g.length; j++) g[j] * step[j]]) / 2;
    lines.add(
      line([
        'iteration',
        t,
        'objective',
        f6(objective(w, d.trainVectors, d.trainTargets, l)),
        'gradient_norm',
        f6(length(g)),
        'step_norm',
        f6(length(step)),
        'predicted_decrease',
        f6(decrease),
      ]),
    );
  }
  final original = originalUnits(m.weights, d.overall),
      centre = probability(score(m.weights, d.vector(d.meanValues)));
  for (var k = 0; k < d.names.length; k++) {
    var total = 0.0;
    for (var i = 0; i < n; i++) {
      final p = influence.probabilities[i];
      total += p * (1 - p) * slope(d.tuples, original, d.train[i].values, k);
    }
    final atMean =
        centre * (1 - centre) * slope(d.tuples, original, d.meanValues, k);
    lines.add(
      'marginal ${d.names[k]} average ${f4(total / n)} at_mean ${f4(atMean)}',
    );
  }
  for (var k = 1; k <= 9; k++) {
    final c = Confusion(predict(m.test.probabilities, k / 10), d.testTargets);
    lines.add(
      'cut 0.$k positive ${c.tp + c.fp} tp ${c.tp} fp ${c.fp} precision ${ratio(c.tp, c.tp + c.fp)} recall ${ratio(c.tp, c.tp + c.fn)} accuracy ${ratio(c.tp + c.tn, size)}',
    );
  }
  final threshold = d.settings.real('THRESHOLD');
  final wrong =
      [
        for (var j = 0; j < size; j++)
          if (m.test.predictions[j] != d.testTargets[j]) j,
      ]..sort((a, b) {
        final order = (m.test.probabilities[b] - threshold).abs().compareTo(
          (m.test.probabilities[a] - threshold).abs(),
        );
        return order == 0 ? a.compareTo(b) : order;
      });
  for (final j in wrong.take(5)) {
    lines.add(
      'error ${d.test[j].ident} actual ${d.testTargets[j]} probability ${f6(m.test.probabilities[j])}',
    );
  }
  final count = d.settings.integer('BOOTSTRAP'),
      seed = d.settings.integer('BOOTSTRAP', 1),
      samples = <Fraction>[],
      values = <double>[];
  final rng = Minstd(seed);
  for (var b = 0; b < count; b++) {
    final scores = <double>[], y = <int>[];
    for (var j = 0; j < size; j++) {
      final i = rng.draw() % size;
      scores.add(m.test.probabilities[i]);
      y.add(d.testTargets[i]);
    }
    final f = auc(scores, y);
    samples.add(f);
    values.add(f.value);
  }
  final mean = sequentialSum(values) / count, tail = count ~/ 40;
  final squares = sequentialSum(
    values.map((value) => (value - mean) * (value - mean)),
  );
  samples.sort((a, b) => a.value.compareTo(b.value));
  lines.add(
    'bootstrap resamples $count seed $seed auc_mean ${f4(mean)} auc_sd ${f4(math.sqrt(squares / (count - 1)))} lower ${samples[tail].text()} upper ${samples[count - tail - 1].text()}',
  );
  final large = influence.residuals.where((v) => v.abs() > 2).length;
  lines.add(
    'influence effective_parameters ${f4(influence.edf)} large_residuals $large',
  );
  for (final i in ordered(influence.distances, true).take(5)) {
    lines.add(
      line([
        'cook',
        d.train[i].ident,
        'actual',
        d.trainTargets[i],
        'probability',
        f4(influence.probabilities[i]),
        'leverage',
        f4(influence.leverages[i]),
        'residual',
        f4(influence.residuals[i]),
        'distance',
        f4(influence.distances[i]),
      ]),
    );
  }
  return lines;
}

int softmaxCorrect(List<List<double>> w, List<List<double>> x, List<int> y) =>
    countEqual(
      x.map((v) => predictedClass(softmaxProbabilities(w, v))).toList(),
      y,
    );
List<String> importancePart(Data d, BinaryModel m, SoftmaxModel soft) {
  final n = d.test.length,
      repeats = d.settings.integer('PERMUTATION'),
      seed = d.settings.integer('PERMUTATION', 1);
  final lines = [
        'importance repeats $repeats seed $seed',
        'baseline log_loss ${f6(m.test.loss)} auc ${m.test.area.text()} softmax_accuracy ${ratio(countEqual(soft.predictions, d.testLabels), n)}',
      ],
      rng = Minstd(seed);
  for (var base = 0; base < d.names.length; base++) {
    var losses = 0.0, numerator = 0, correct = 0;
    for (var t = 0; t < repeats; t++) {
      final order = List.generate(n, (i) => i);
      rng.shuffle(order);
      final vectors = <List<double>>[];
      for (var j = 0; j < n; j++) {
        final values = List<double>.of(d.test[j].values);
        values[base] = d.test[order[j]].values[base];
        vectors.add(d.vector(values));
      }
      losses += averageLoss(m.weights, vectors, d.testTargets);
      numerator += auc(probabilities(m.weights, vectors), d.testTargets).a;
      correct += softmaxCorrect(soft.weights, vectors, d.testLabels);
    }
    lines.add(
      'feature ${d.names[base]} log_loss_increase ${f6(losses / repeats - m.test.loss)} auc ${Fraction(numerator, repeats * m.test.area.b).text()} softmax_accuracy ${ratio(correct, repeats * n)}',
    );
  }
  return lines;
}

List<String> profilePart(Data d, BinaryModel m, SoftmaxModel soft) {
  final lines = ['profiles'];
  for (var base = 0; base < d.names.length; base++) {
    final (lo, hi) = d.range(base);
    for (var g = 0; g <= 4; g++) {
      final values = List<double>.of(d.meanValues);
      values[base] = lo + (hi - lo) * g / 4;
      final v = d.vector(values);
      lines.add(
        'profile ${d.names[base]} value ${f4(values[base])} newton ${f4(probability(score(m.weights, v)))} softmax ${realText(softmaxProbabilities(soft.weights, v), 4)}',
      );
    }
  }
  return lines;
}

List<String> softmaxPart(Data d, SoftmaxModel soft, BinaryModel newton) {
  final n = d.test.length,
      k = d.classes,
      table = List.generate(d.classes, (_) => List.filled(d.classes, 0));
  for (var j = 0; j < n; j++) {
    table[d.testLabels[j]][soft.predictions[j]]++;
  }
  final rows = table.map(sum).toList(),
      columns = [for (var c = 0; c < k; c++) sum(table.map((row) => row[c]))];
  final lines = [
    'softmax classes $k lambda ${f4(d.settings.real('SOFTMAX', 2))} iterations ${d.settings.integer('SOFTMAX', 1)}',
    'confusion',
    ...table.map((row) => row.join(' ')),
  ];
  var diagonal = 0, chance = 0;
  for (var c = 0; c < k; c++) {
    final scores = soft.probabilities.map((p) => p[c]).toList(),
        hits = table[c][c];
    diagonal += hits;
    chance += rows[c] * columns[c];
    lines.add(
      'class $c precision ${ratio(hits, columns[c])} recall ${ratio(hits, rows[c])} f1 ${ratio(2 * hits, columns[c] + rows[c])} auc ${auc(scores, targets(d.testLabels, c)).text()}',
    );
  }
  lines.add(
    'accuracy ${ratio(diagonal, n)} kappa ${ratio(n * diagonal - chance, n * n - chance)}',
  );
  var brier = 0.0;
  for (var j = 0; j < n; j++) {
    var total = 0.0;
    for (var c = 0; c < k; c++) {
      final error = soft.probabilities[j][c] - (d.testLabels[j] == c ? 1 : 0);
      total += error * error;
    }
    brier += total;
  }
  lines.add(
    'log_loss ${f6(softmaxAverage(soft.weights, d.testVectors, d.testLabels))} brier ${f6(brier / n)}',
  );
  final positive = d.settings.integer('POSITIVE'),
      scores = <double>[],
      confidences = <double>[],
      hits = <int>[];
  var binaryLoss = 0.0;
  for (var j = 0; j < n; j++) {
    final p = soft.probabilities[j],
        value = soft.probabilities[j][positive],
        predicted = soft.predictions[j];
    scores.add(value);
    binaryLoss += -math.log(d.testTargets[j] == 1 ? value : 1 - value);
    confidences.add(p[predicted]);
    hits.add(predicted == d.testLabels[j] ? 1 : 0);
  }
  final prediction = predict(scores, d.settings.real('THRESHOLD')),
      bins = fillBins(confidences, hits);
  lines.addAll([
    'binary_view positive_class $positive auc ${auc(scores, d.testTargets).text()} log_loss ${f6(binaryLoss / n)} accuracy ${ratio(countEqual(prediction, d.testTargets), n)} agreement_with_newton ${countEqual(prediction, newton.test.predictions)}/$n',
    'confidence',
    ...binLines(bins, 'mean_confidence', 'accuracy'),
    'ece ${f4(calibrationError(bins, n))}',
  ]);
  return lines;
}

List<String> oneVsRestPart(Data d, SoftmaxModel soft) {
  final l = d.settings.real('SOFTMAX', 2),
      lines = [
        'one_vs_rest lambda ${f4(d.settings.real('SOFTMAX', 2))} newton_iterations 10',
      ],
      classProbabilities = <List<double>>[];
  for (var k = 0; k < d.classes; k++) {
    final y = targets(d.trainLabels, k);
    final w = finalWeights(newtonMethod(d.trainVectors, y, l));
    final p = probabilities(w, d.testVectors);
    classProbabilities.add(p);
    lines.add(
      'class $k objective ${f6(objective(w, d.trainVectors, y, l))} auc ${auc(p, targets(d.testLabels, k)).text()}',
    );
  }
  final prediction = [
        for (var j = 0; j < d.test.length; j++)
          predictedClass(classProbabilities.map((p) => p[j]).toList()),
      ],
      n = d.test.length;
  lines.add(
    'accuracy ${ratio(countEqual(prediction, d.testLabels), n)} agreement_with_softmax ${countEqual(prediction, soft.predictions)}/$n',
  );
  return lines;
}

List<String> mapPart(Data d, BinaryModel m, SoftmaxModel soft) {
  final w = d.settings.integer('MAP'),
      h = d.settings.integer('MAP', 1),
      cells = List.filled(d.classes, 0),
      classes = <String>[],
      probabilityRows = <String>[];
  final (loX, hiX) = d.range(0);
  final (loY, hiY) = d.range(1);
  for (var r = 0; r < h; r++) {
    var classRow = '', probabilityRow = '';
    for (var c = 0; c < w; c++) {
      final values = List<double>.of(d.meanValues);
      values[0] = loX + (c + 0.5) * (hiX - loX) / w;
      values[1] = hiY - (r + 0.5) * (hiY - loY) / h;
      final v = d.vector(values);
      final k = predictedClass(softmaxProbabilities(soft.weights, v));
      cells[k]++;
      classRow += '$k';
      probabilityRow += '${binIndex(probability(score(m.weights, v)))}';
    }
    classes.add(classRow);
    probabilityRows.add(probabilityRow);
  }
  return [
    'map ${d.names[0]} ${d.names[1]} width $w height $h',
    'softmax_classes',
    ...classes,
    'cells ${cells.join(' ')}',
    'newton_probability',
    ...probabilityRows,
  ];
}

void main() {
  final (names, train) = readExamples('input/train.csv');
  final (_, test) = readExamples('input/test.csv');
  final s = Settings();
  final d = Data(names, train, test, s);
  final results = [
    for (var i = 0; i < s.fields['LAMBDAS']!.length; i++)
      crossValidate(d, s.real('LAMBDAS', i), d.count),
  ];
  var best = results.first;
  for (final r in results) {
    if (r.loss <= best.loss) best = r;
  }
  final mean = sequentialSum(best.foldLosses) / 5, l = best.lambda;
  final spread = sequentialSum(
    best.foldLosses.map((v) => (v - mean) * (v - mean)),
  );
  final se = math.sqrt(spread / 4) / math.sqrt(5);
  var oneSE = best.lambda;
  for (final r in results) {
    if (r.loss <= best.loss + se) oneSE = r.lambda;
  }
  final gd = gradientDescent(
        d.trainVectors,
        d.trainTargets,
        l,
        s.real('GD'),
        s.integer('GD', 1),
      ),
      sgd = stochasticDescent(
        d.trainVectors,
        d.trainTargets,
        l,
        s.real('SGD'),
        s.integer('SGD', 1),
        s.integer('SGD', 2),
        s.integer('SGD', 3),
      );
  final newton = BinaryModel(
    'newton',
    newtonMethod(d.trainVectors, d.trainTargets, l),
    d,
  );
  final models = [BinaryModel('gd', gd, d), BinaryModel('sgd', sgd, d), newton],
      soft = SoftmaxModel(
        softmaxTrain(
          d.trainVectors,
          d.trainLabels,
          d.classes,
          s.real('SOFTMAX', 2),
          s.real('SOFTMAX'),
          s.integer('SOFTMAX', 1),
        ),
        d,
      ),
      influence = Influence(newton.weights, d.trainVectors, d.trainTargets, l);
  Directory('output').createSync(recursive: true);
  writeParts('weights.txt', weightsParts(d, models, soft, influence, l));
  writeLines('loss_trace.csv', traceLines(d, models, soft, l));
  writeLines('predictions.csv', predictionLines(d, models, soft));
  final parts = [
    dataPart(d),
    crossValidationPart(d, results, best, se, oneSE),
    lambdaPathPart(d),
    degreePart(d, l),
    learningPart(d, l),
    for (final m in models) binaryPart(d, m, l),
    comparisonPart(d, models),
    diagnosticsPart(d, newton, influence, l),
    importancePart(d, newton, soft),
    profilePart(d, newton, soft),
    softmaxPart(d, soft, newton),
    oneVsRestPart(d, soft),
    mapPart(d, newton, soft),
  ];
  writeParts('evaluation.txt', parts);
  writeLines('roc.csv', rocLines(d, models));
}
