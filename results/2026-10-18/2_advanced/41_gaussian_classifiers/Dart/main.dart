import 'dart:io';
import 'dart:math' as math;

part 'dataset.dart';
part 'linalg.dart';
part 'gaussian_models.dart';
part 'evaluation.dart';
part 'plot.dart';

class CrossValidation {
  final List<int> predictions, foldCorrect;
  final int correct;
  CrossValidation(this.predictions, this.foldCorrect, this.correct);
}

List<String> confusionLines(List<String> classes, List<List<int>> matrix) => [
  for (var i = 0; i < classes.length; i++)
    'confusion ${classes[i]} ${ints(matrix[i])}',
];
List<String> comparisonLines(
  String title,
  List<String> names,
  List<List<int>> predictions,
  List<int> actual,
) {
  final lines = [title];
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      final (b01, b10, chi) = mcnemar(actual, predictions[i], predictions[j]);
      lines.add(
        '${names[i]} ${names[j]} b01 $b01 b10 $b10 chi2 ${real(chi)} significant ${chi > 3.841 ? 'yes' : 'no'}',
      );
    }
  }
  return lines;
}

int correctCount(GaussianModel model, List<Row> rows) {
  var n = 0;
  for (final r in rows) {
    if (model.predict(r.values) == r.classIndex) n++;
  }
  return n;
}

class DistanceRow {
  final double distance;
  final int index, classIndex;
  final Row row;
  DistanceRow(this.distance, this.index, this.classIndex, this.row);
}

void orderDistances(List<DistanceRow> rows) {
  rows.sort((a, b) {
    final c = b.distance.compareTo(a.distance);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
}

List<List<String>> pointGrid(
  List<(double, double)> points,
  List<int> actual,
  List<String> letters,
  List<double> limits,
  (int, int) size,
) {
  final (w, h) = size;
  final grid = List.generate(h, (_) => List.filled(w, ' '));
  for (var i = 0; i < points.length; i++) {
    final (x, y) = points[i];
    final c = cell(x, limits[0], limits[1], w),
        r = h - 1 - cell(y, limits[2], limits[3], h),
        letter = letters[actual[i]];
    grid[r][c] = grid[r][c] == ' ' || grid[r][c] == letter ? letter : '*';
  }
  return grid;
}

List<double> pointLimits(List<(double, double)> points) {
  final v = [
    points.first.$1,
    points.first.$1,
    points.first.$2,
    points.first.$2,
  ];
  for (final (x, y) in points.skip(1)) {
    v[0] = math.min(v[0], x);
    v[1] = math.max(v[1], x);
    v[2] = math.min(v[2], y);
    v[3] = math.max(v[3], y);
  }
  return v;
}

int nearestCorrect(
  List<(double, double)> points,
  List<int> actual,
  List<(double, double)> centroids,
  int dimensions,
) {
  var correct = 0;
  for (var i = 0; i < points.length; i++) {
    final p = points[i], distances = <double>[];
    for (final c in centroids) {
      var delta = p.$1 - c.$1, d = delta * delta;
      if (dimensions == 2) {
        delta = p.$2 - c.$2;
        d = d + delta * delta;
      }
      distances.add(d);
    }
    if (argmin(distances) == actual[i]) correct++;
  }
  return correct;
}

class Analysis {
  final Dataset data;
  late final int n, m, d, c;
  late final List<int> all, trainActual, testActual, folds, foldSizes;
  late final List<String> upper, lower;
  final models = <GaussianModel>[],
      results = <List<Prediction>>[],
      predictions = <List<int>>[];
  final cache = <String, CrossValidation>{};
  Analysis(this.data) {
    n = data.train.length;
    m = data.test.length;
    d = data.features.length;
    c = data.classes.length;
    all = List.generate(d, (i) => i);
    trainActual = data.train.map((r) => r.classIndex).toList();
    testActual = data.test.map((r) => r.classIndex).toList();
    folds = data.train.map((r) => r.id % data.params.folds).toList();
    foldSizes = List.filled(data.params.folds, 0);
    for (final f in folds) {
      foldSizes[f]++;
    }
    lower = data.classes.map((s) => s[0]).toList();
    upper = lower.map((s) => s.toUpperCase()).toList();
    for (final name in modelNames) {
      final model = fit(name, all, data.train),
          rs = [
            for (final row in data.test) model.infer(row.values, data.costs),
          ];
      models.add(model);
      results.add(rs);
      predictions.add(rs.map((r) => r.predicted).toList());
    }
  }
  GaussianModel fit(String name, List<int> features, List<Row> rows) {
    final p = data.params;
    return trainModel(rows, features, c, name, p.prior, p.epsilon, p.gamma);
  }

  CrossValidation cv(
    String name,
    List<int> features,
    double epsilon,
    double gamma,
  ) {
    final key = '$name|${features.join(',')}|$epsilon|$gamma';
    if (cache.containsKey(key)) return cache[key]!;
    final pred = List.filled(n, 0), counts = List.filled(data.params.folds, 0);
    var correct = 0;
    for (var f = 0; f < counts.length; f++) {
      final rows = [
            for (var i = 0; i < n; i++)
              if (folds[i] != f) data.train[i],
          ],
          model = trainModel(
            rows,
            features,
            c,
            name,
            data.params.prior,
            epsilon,
            gamma,
          );
      for (var i = 0; i < n; i++) {
        if (folds[i] == f) {
          final row = data.train[i];
          pred[i] = model.predict(row.values);
          if (pred[i] == row.classIndex) {
            counts[f]++;
            correct++;
          }
        }
      }
    }
    final r = CrossValidation(pred, counts, correct);
    cache[key] = r;
    return r;
  }

  CrossValidation crossValidate(String name, List<int> features) =>
      cv(name, features, data.params.epsilon, data.params.gamma);
  String featureNames(List<int> features) =>
      features.map((f) => data.features[f]).join(' ');
  List<List<String>> modelSections() {
    final nb = models[0],
        lda = models[1],
        qda = models[2],
        s = nb.stats,
        sections = <List<String>>[];
    var lines = [
      'features ${data.features.join(' ')}',
      'classes ${data.classes.join(' ')}',
      'prior_mode ${data.params.prior}',
    ];
    for (var k = 0; k < c; k++) {
      lines.add(
        'class ${data.classes[k]} letter ${upper[k]} count ${s.counts[k]} prior ${real(nb.priors[k])} mean ${reals(s.means[k])}',
      );
    }
    sections.add(lines);
    lines = [
      'model NB',
      'smoothing epsilon ${real(nb.epsilon)} max_variance ${real(nb.maxVariance)} added ${real(nb.added)}',
    ];
    for (var k = 0; k < c; k++) {
      final diag = [for (var j = 0; j < d; j++) nb.covariances[k][j][j]];
      lines.add(
        'class ${data.classes[k]} variance ${reals(diag)} log_det ${real(nb.logDets[k])}',
      );
    }
    sections.add(lines);
    final l = lda.factors[0];
    lines = [
      'model LDA',
      'log_det ${real(lda.logDets[0])}',
      for (final row in lda.covariances[0]) '  ${reals(row)}',
    ];
    for (var k = 0; k < c; k++) {
      final coef = backward(l, forward(l, s.means[k])),
          intercept = math.log(lda.priors[k]) - dot(s.means[k], coef) / 2;
      lines.add(
        'class ${data.classes[k]} intercept ${real(intercept)} coef ${reals(coef)}',
      );
    }
    sections.add(lines);
    lines = ['model QDA gamma ${real(qda.gamma)}'];
    for (var k = 0; k < c; k++) {
      final e = jacobi(qda.covariances[k]).values
        ..sort((a, b) => b.compareTo(a));
      lines.add(
        'class ${data.classes[k]} log_det ${real(qda.logDets[k])} eigenvalues ${reals(e)} condition ${real(e.first / e.last)}',
      );
      lines.addAll(qda.covariances[k].map((row) => '  ${reals(row)}'));
    }
    sections.add(lines);
    lines = ['separation'];
    for (var i = 0; i < c; i++) {
      for (var j = i + 1; j < c; j++) {
        final delta = [
              for (var f = 0; f < d; f++) s.means[i][f] - s.means[j][f],
            ],
            average = zeros(d);
        for (var r = 0; r < d; r++) {
          for (var col = 0; col < d; col++) {
            average[r][col] =
                (qda.covariances[i][r][col] + qda.covariances[j][r][col]) / 2;
          }
        }
        final al = cholesky(average),
            bh =
                quadratic(al, delta) / 8 +
                (logDet(al) - (qda.logDets[i] + qda.logDets[j]) / 2) / 2;
        lines.add(
          '${data.classes[i]} ${data.classes[j]} mahalanobis ${real(math.sqrt(quadratic(l, delta)))} bhattacharyya ${real(bh)}',
        );
      }
    }
    sections.add(lines);
    final outliers = <DistanceRow>[];
    for (var i = 0; i < n; i++) {
      final row = data.train[i], q = qda.distances(row.values)[row.classIndex];
      if (q > data.params.outlier)
        outliers.add(DistanceRow(q, i, row.classIndex, row));
    }
    orderDistances(outliers);
    sections.add([
      'outliers threshold ${real(data.params.outlier)}',
      for (final r in outliers)
        '${r.row.id} ${r.row.label} q ${real(r.distance)}',
      'count ${outliers.length}',
    ]);
    return sections;
  }

  List<String> predictionLines() {
    final lines = [
      'id,model,actual,predicted,decision,${data.classes.join(',')}',
    ];
    for (var i = 0; i < m; i++) {
      final row = data.test[i];
      for (var k = 0; k < 3; k++) {
        final r = results[k][i];
        lines.add(
          [
            row.id,
            modelNames[k],
            row.label,
            data.classes[r.predicted],
            data.classes[r.decision],
            ...r.posterior.map(real),
          ].join(','),
        );
      }
    }
    return lines;
  }

  List<String> modelEvaluation(int k) {
    final rs = results[k],
        metrics = Metrics(testActual, predictions[k], c),
        lines = [
          'model ${modelNames[k]}',
          ...confusionLines(data.classes, metrics.matrix),
        ];
    lines.addAll([
      'accuracy ${fractionText(metrics.accuracy)}',
      'balanced_accuracy ${fractionText(metrics.balanced)}',
      'kappa ${fractionText(metrics.kappa)}',
    ]);
    for (var cl = 0; cl < c; cl++) {
      lines.add(
        'class ${data.classes[cl]} support ${metrics.support[cl]} recall ${fractionText(metrics.recall[cl])} precision ${fractionText(metrics.precision[cl])} f1 ${fractionText(metrics.f1[cl])}',
      );
    }
    var loss = 0.0;
    final errors = <String>[];
    for (var i = 0; i < m; i++) {
      final row = data.test[i], r = rs[i];
      loss += r.logPosterior[row.classIndex];
      if (r.predicted != row.classIndex) {
        errors.add(
          'error ${row.id} actual ${row.label} predicted ${data.classes[r.predicted]} confidence ${real(r.confidence)}',
        );
      }
    }
    lines.addAll([
      'macro_f1 ${real(metrics.macroF1)}',
      'log_loss ${real(-loss / m)}',
      'errors ${errors.length}',
      ...errors,
    ]);
    final edges = [0.0, ...data.params.edges, 1.0];
    var ece = 0.0;
    for (var bin = 0; bin < edges.length - 1; bin++) {
      final lo = edges[bin], hi = edges[bin + 1];
      var count = 0, correct = 0;
      var conf = 0.0;
      for (var i = 0; i < m; i++) {
        final r = rs[i];
        if (r.confidence >= lo &&
            (r.confidence < hi ||
                (bin == edges.length - 2 && r.confidence == hi))) {
          count++;
          conf += r.confidence;
          if (r.predicted == testActual[i]) correct++;
        }
      }
      final text = count > 0 ? real(conf / count) : '-';
      lines.add(
        'bin ${real(lo)} ${real(hi)} count $count confidence $text accuracy ${ratio(correct, count)}',
      );
      ece += (correct - conf).abs();
    }
    lines.add('ece ${real(ece / m)}');
    for (final threshold in data.params.reject) {
      var count = 0, correct = 0;
      for (var i = 0; i < m; i++) {
        final r = rs[i];
        if (r.confidence >= threshold) {
          count++;
          if (r.predicted == testActual[i]) correct++;
        }
      }
      lines.add(
        'reject ${real(threshold)} accepted $count coverage ${ratio(count, m)} accuracy ${ratio(correct, count)}',
      );
    }
    return lines;
  }

  List<int> ensemble() {
    final pred = <int>[];
    for (var i = 0; i < m; i++) {
      final p = List.filled(c, 0.0);
      for (var k = 0; k < c; k++) {
        for (var model = 0; model < 3; model++) {
          p[k] += results[model][i].posterior[k];
        }
        p[k] /= 3;
      }
      pred.add(argmax(p));
    }
    return pred;
  }

  List<String> costLines() {
    final lines = ['costs'];
    for (var k = 0; k < 3; k++) {
      var total = 0.0, decision = 0.0;
      var changed = 0, correct = 0;
      for (var i = 0; i < m; i++) {
        final r = results[k][i], y = testActual[i];
        total += data.costs[y][r.predicted];
        decision += data.costs[y][r.decision];
        if (r.decision != r.predicted) changed++;
        if (r.decision == y) correct++;
      }
      lines.add(
        '${modelNames[k]} argmax_total ${real(total)} decision_total ${real(decision)} changed $changed decision_accuracy ${ratio(correct, m)}',
      );
    }
    return lines;
  }

  List<String> noveltyLines() {
    final novel = <DistanceRow>[];
    for (var i = 0; i < m; i++) {
      final row = data.test[i],
          q = models[2].distances(row.values),
          k = argmin(q);
      if (q[k] > data.params.outlier) novel.add(DistanceRow(q[k], i, k, row));
    }
    orderDistances(novel);
    return [
      'novelty threshold ${real(data.params.outlier)}',
      for (final r in novel)
        '${r.row.id} nearest ${data.classes[r.classIndex]} q ${real(r.distance)}',
      'count ${novel.length}',
    ];
  }

  List<String> bootstrapLines() {
    final count = data.params.bootstrap,
        rng = RandomGenerator(data.params.seed),
        samples = List.generate(
          3,
          (_) => List.filled(data.params.bootstrap, 0),
        );
    for (var b = 0; b < count; b++) {
      for (var i = 0; i < m; i++) {
        final j = rng.draw() % m;
        for (var k = 0; k < 3; k++) {
          if (predictions[k][j] == testActual[j]) samples[k][b]++;
        }
      }
    }
    final lines = ['bootstrap resamples $count seed ${data.params.seed}'],
        offset = count ~/ 40;
    for (var k = 0; k < 3; k++) {
      final ordered = [...samples[k]]..sort();
      var total = 0;
      for (final value in ordered) {
        total += value;
      }
      final mean = total / count / m;
      lines.add(
        '${modelNames[k]} mean ${real(mean)} interval ${ratio(ordered[offset], m)} ${ratio(ordered[count - offset - 1], m)}',
      );
    }
    for (var i = 0; i < 3; i++) {
      for (var j = i + 1; j < 3; j++) {
        var wins = 0, ties = 0;
        for (var b = 0; b < count; b++) {
          if (samples[i][b] > samples[j][b])
            wins++;
          else if (samples[i][b] == samples[j][b])
            ties++;
        }
        lines.add(
          '${modelNames[i]} ${modelNames[j]} wins $wins ties $ties losses ${count - wins - ties}',
        );
      }
    }
    return lines;
  }

  List<String> priorLines() {
    final p = data.params,
        alternative = p.prior == 'empirical' ? 'uniform' : 'empirical',
        lines = ['prior_sensitivity alternative $alternative'];
    for (var k = 0; k < 3; k++) {
      final model = trainModel(
            data.train,
            all,
            c,
            modelNames[k],
            alternative,
            p.epsilon,
            p.gamma,
          ),
          pred = [for (final row in data.test) model.predict(row.values)];
      final metrics = Metrics(testActual, pred, c);
      var changed = 0;
      for (var i = 0; i < m; i++) {
        if (pred[i] != predictions[k][i]) changed++;
      }
      lines.add(
        '${modelNames[k]} accuracy ${fractionText(metrics.accuracy)} balanced_accuracy ${fractionText(metrics.balanced)} changed $changed',
      );
    }
    return lines;
  }

  List<String> learningLines() {
    final lines = ['learning_curve'];
    for (final size in data.params.curve) {
      final taken = List.filled(c, 0), rows = <Row>[];
      for (final row in data.train) {
        if (taken[row.classIndex] < size) {
          rows.add(row);
          taken[row.classIndex]++;
        }
      }
      final fields = ['size $size rows ${rows.length}'];
      for (final name in modelNames) {
        fields.add(
          '$name ${ratio(correctCount(fit(name, all, rows), data.test), m)}',
        );
      }
      lines.add(fields.join(' '));
    }
    return lines;
  }

  List<String> subsetLines() {
    final lines = [
      'cross_validation folds ${data.params.folds}',
      'fold_sizes ${ints(foldSizes)}',
    ];
    var bestSubset = 0, bestModel = 0, bestCorrect = -1;
    for (var i = 0; i < data.params.subsets.length; i++) {
      final s = data.params.subsets[i];
      lines.add('subset ${s.name} features ${featureNames(s.features)}');
      for (var k = 0; k < 3; k++) {
        final r = crossValidate(modelNames[k], s.features);
        lines.add(
          '  ${modelNames[k]} fold_correct ${ints(r.foldCorrect)} correct ${r.correct} accuracy ${ratio(r.correct, n)}',
        );
        if (r.correct > bestCorrect ||
            (r.correct == bestCorrect &&
                s.features.length <
                    data.params.subsets[bestSubset].features.length)) {
          bestSubset = i;
          bestModel = k;
          bestCorrect = r.correct;
        }
      }
    }
    final s = data.params.subsets[bestSubset],
        name = modelNames[bestModel],
        correct = correctCount(fit(name, s.features, data.train), data.test);
    lines.addAll([
      'best subset ${s.name} model $name correct $bestCorrect accuracy ${ratio(bestCorrect, n)}',
      'refit_test correct $correct accuracy ${ratio(correct, m)}',
    ]);
    return lines;
  }

  List<String> looLines() {
    final lines = ['leave_one_out'];
    for (final name in modelNames) {
      var correct = 0;
      for (var i = 0; i < n; i++) {
        final rows = [...data.train.take(i), ...data.train.skip(i + 1)],
            row = data.train[i];
        if (fit(name, all, rows).predict(row.values) == row.classIndex)
          correct++;
      }
      lines.add('$name correct $correct accuracy ${ratio(correct, n)}');
    }
    return lines;
  }

  List<List<String>> forwardSections() {
    final sections = <List<String>>[];
    for (final name in modelNames) {
      final lines = ['forward_selection model $name'],
          selected = <int>[],
          used = <int>{};
      var bestStep = 0, bestCorrect = -1;
      for (var step = 1; step <= d; step++) {
        var added = 0, stepCorrect = -1;
        for (final f in all) {
          if (used.contains(f)) continue;
          final r = crossValidate(name, [...selected, f]);
          if (r.correct > stepCorrect) {
            added = f;
            stepCorrect = r.correct;
          }
        }
        selected.add(added);
        used.add(added);
        lines.add(
          'step $step add ${data.features[added]} correct $stepCorrect accuracy ${ratio(stepCorrect, n)}',
        );
        if (stepCorrect > bestCorrect) {
          bestStep = step;
          bestCorrect = stepCorrect;
        }
      }
      lines.add(
        'best_step $bestStep features ${featureNames(selected.take(bestStep).toList())}',
      );
      sections.add(lines);
    }
    return sections;
  }

  List<String> tuningLines(String name, List<double> values, String title) {
    final lines = [title], p = data.params;
    var bestValue = 0.0, bestCorrect = -1;
    for (final v in values) {
      final epsilon = name == 'NB' ? v : p.epsilon,
          gamma = name == 'QDA' ? v : p.gamma,
          r = cv(name, all, epsilon, gamma);
      lines.add(
        'value ${real(v)} correct ${r.correct} accuracy ${ratio(r.correct, n)}',
      );
      if (r.correct >= bestCorrect) {
        bestValue = v;
        bestCorrect = r.correct;
      }
    }
    final epsilon = name == 'NB' ? bestValue : p.epsilon,
        gamma = name == 'QDA' ? bestValue : p.gamma,
        model = trainModel(data.train, all, c, name, p.prior, epsilon, gamma),
        correct = correctCount(model, data.test);
    lines.add(
      'best ${real(bestValue)} test correct $correct accuracy ${ratio(correct, m)}',
    );
    return lines;
  }

  List<List<String>> evaluationSections() {
    final sections = <List<String>>[
          ['test rows $m'],
          for (var k = 0; k < 3; k++) modelEvaluation(k),
        ],
        ens = ensemble(),
        metrics = Metrics(testActual, ens, c);
    sections.add([
      'ensemble soft_vote',
      'accuracy ${fractionText(metrics.accuracy)} balanced_accuracy ${fractionText(metrics.balanced)} kappa ${fractionText(metrics.kappa)}',
    ]);
    sections.addAll([
      comparisonLines(
        'mcnemar test',
        [...modelNames, 'ENSEMBLE'],
        [...predictions, ens],
        testActual,
      ),
      costLines(),
      noveltyLines(),
      bootstrapLines(),
      priorLines(),
      learningLines(),
      subsetLines(),
    ]);
    final cv = [for (final name in modelNames) crossValidate(name, all)];
    sections.add(
      comparisonLines(
        'mcnemar cross_validation',
        modelNames,
        cv.map((r) => r.predictions).toList(),
        trainActual,
      ),
    );
    for (var k = 0; k < 3; k++) {
      final metrics = Metrics(trainActual, cv[k].predictions, c);
      sections.add([
        'cv_confusion model ${modelNames[k]}',
        ...confusionLines(data.classes, metrics.matrix),
        'balanced_accuracy ${fractionText(metrics.balanced)} kappa ${fractionText(metrics.kappa)}',
      ]);
    }
    sections.add(looLines());
    sections.addAll(forwardSections());
    sections.addAll([
      tuningLines('NB', data.params.smoothing, 'nb_smoothing_path'),
      tuningLines('QDA', data.params.gammaGrid, 'qda_gamma_path'),
    ]);
    return sections;
  }

  List<List<String>> boundarySections() {
    final sections = <List<String>>[];
    final (w, h) = data.params.mapSize;
    for (final (fx, fy) in data.params.pairs) {
      final points = [
            for (final row in data.train) (row.values[fx], row.values[fy]),
          ],
          limits = pointLimits(points),
          xmin = limits[0],
          xmax = limits[1],
          ymin = limits[2],
          ymax = limits[3],
          dx = (xmax - xmin) / (w - 1),
          dy = (ymax - ymin) / (h - 1);
      final lines = [
            'pair ${data.features[fx]} ${data.features[fy]}',
            'x ${data.features[fx]} ${real(xmin)} ${real(xmax)} y ${data.features[fy]} ${real(ymin)} ${real(ymax)} grid ${w}x$h',
          ],
          allGrids = <List<List<Prediction>>>[];
      for (final name in modelNames) {
        final features = [fx, fy],
            model = fit(name, features, data.train),
            cv = crossValidate(name, features),
            rs = [
              for (var row = 0; row < h; row++)
                [
                  for (var col = 0; col < w; col++)
                    model.inferVector([xmin + col * dx, ymax - row * dy]),
                ],
            ],
            counts = List.filled(c, 0);
        lines.add(
          'model $name train_accuracy ${ratio(correctCount(model, data.train), n)} cv_accuracy ${ratio(cv.correct, n)}',
        );
        allGrids.add(rs);
        lines.addAll(
          frame([
            for (final row in rs) [for (final r in row) upper[r.predicted]],
          ]),
        );
        for (final row in rs) {
          for (final r in row) {
            counts[r.predicted]++;
          }
        }
        lines.add(
          'cells ${[for (var k = 0; k < c; k++) '${upper[k]} ${counts[k]}'].join(' ')}',
        );
      }
      final agreement = List.generate(h, (_) => List.filled(w, '.')),
          uncertainty = List.generate(h, (_) => List.filled(w, ' '));
      var disagreements = 0;
      for (var row = 0; row < h; row++) {
        for (var col = 0; col < w; col++) {
          final distinct = {
            for (final grid in allGrids) grid[row][col].predicted,
          }.length;
          if (distinct > 1) {
            agreement[row][col] = '$distinct';
            disagreements++;
          }
          final u = (1 - allGrids[2][row][col].confidence) / (1 - 1 / c),
              level = math.min(9, (10 * u).floor());
          uncertainty[row][col] = ' .:-=+*#%@'[level];
        }
      }
      lines.addAll([
        'agreement',
        ...frame(agreement),
        'disagreement_cells $disagreements',
        'uncertainty QDA',
        ...frame(uncertainty),
        'points',
        ...frame(
          pointGrid(points, trainActual, lower, limits, data.params.mapSize),
        ),
      ]);
      sections.add(lines);
    }
    return sections;
  }

  List<List<String>> projectionSections() {
    final s = models[0].stats, within = zeros(d), between = zeros(d);
    for (var i = 0; i < d; i++) {
      for (var j = 0; j < d; j++) {
        for (var k = 0; k < c; k++) {
          within[i][j] += s.scatter[k][i][j];
          between[i][j] +=
              s.counts[k] *
              (s.means[k][i] - s.center[i]) *
              (s.means[k][j] - s.center[j]);
        }
      }
    }
    final fv = [
          for (var j = 0; j < d; j++)
            (between[j][j] / (c - 1)) / (within[j][j] / (n - c)),
        ],
        featureOrder = [...all]
          ..sort((a, b) {
            final result = fv[b].compareTo(fv[a]);
            return result != 0 ? result : a.compareTo(b);
          });
    final univariate = [
      'univariate',
      for (var rank = 0; rank < d; rank++)
        'rank ${rank + 1} ${data.features[featureOrder[rank]]} f ${real(fv[featureOrder[rank]])} between ${real(between[featureOrder[rank]][featureOrder[rank]])} within ${real(within[featureOrder[rank]][featureOrder[rank]])}',
    ];
    final l = cholesky(within), y = zeros(d);
    for (var j = 0; j < d; j++) {
      final column = forward(l, [for (var i = 0; i < d; i++) between[i][j]]);
      for (var i = 0; i < d; i++) {
        y[i][j] = column[i];
      }
    }
    final z = zeros(d);
    for (var i = 0; i < d; i++) {
      final column = forward(l, y[i]);
      for (var j = 0; j < d; j++) {
        z[j][i] = column[j];
      }
    }
    final symmetric = [
          for (var i = 0; i < d; i++)
            [for (var j = 0; j < d; j++) (z[i][j] + z[j][i]) / 2],
        ],
        eigen = jacobi(symmetric),
        order = [...all]
          ..sort((a, b) {
            final result = eigen.values[b].compareTo(eigen.values[a]);
            return result != 0 ? result : a.compareTo(b);
          });
    var total = 0.0;
    for (final value in eigen.values) {
      total += value;
    }
    final directions = <List<double>>[];
    for (final index in order.take(2)) {
      final v = backward(l, [
            for (var j = 0; j < d; j++) eigen.vectors[j][index],
          ]),
          norm = math.sqrt(dot(v, v));
      for (var j = 0; j < d; j++) {
        v[j] /= norm;
      }
      if (v[argmax(v.map((x) => x.abs()).toList())] < 0) {
        for (var j = 0; j < d; j++) {
          v[j] = -v[j];
        }
      }
      directions.add(v);
    }
    (double, double) project(List<double> values) {
      final p = List.filled(2, 0.0);
      for (var t = 0; t < 2; t++) {
        for (var j = 0; j < d; j++) {
          p[t] += directions[t][j] * (values[j] - s.center[j]);
        }
      }
      return (p[0], p[1]);
    }

    final trainPoints = [for (final row in data.train) project(row.values)],
        testPoints = [for (final row in data.test) project(row.values)],
        centroids = [for (final mean in s.means) project(mean)];
    final fisher = [
      'fisher features ${data.features.join(' ')}',
      'center ${reals(s.center)}',
      'sweeps ${eigen.sweeps}',
      'eigenvalues ${reals(order.map((j) => eigen.values[j]))}',
      'ratios ${reals(order.map((j) => eigen.values[j] / total))}',
    ];
    for (var t = 0; t < 2; t++) {
      final v = directions[t],
          standard = [
            for (var j = 0; j < d; j++)
              directions[t][j] * math.sqrt(models[1].covariances[0][j][j]),
          ];
      fisher.addAll([
        'direction ${t + 1} ${reals(v)}',
        'standardized ${t + 1} ${reals(standard)}',
      ]);
    }
    for (var k = 0; k < c; k++) {
      final spread = <double>[];
      for (var t = 0; t < 2; t++) {
        var sum = 0.0;
        for (var i = 0; i < n; i++) {
          if (trainActual[i] == k) {
            final point = trainPoints[i],
                center = centroids[k],
                delta = t == 0 ? point.$1 - center.$1 : point.$2 - center.$2;
            sum += delta * delta;
          }
        }
        spread.add(math.sqrt(sum / s.counts[k]));
      }
      fisher.add(
        'centroid ${data.classes[k]} ${reals([centroids[k].$1, centroids[k].$2])} spread ${reals(spread)}',
      );
    }
    for (var dims = 1; dims <= 2; dims++) {
      fisher.add(
        'nearest_centroid dims $dims train ${ratio(nearestCorrect(trainPoints, trainActual, centroids, dims), n)} test ${ratio(nearestCorrect(testPoints, testActual, centroids, dims), m)}',
      );
    }
    final limits = pointLimits(trainPoints);
    final (w, h) = data.params.plotSize;
    final grid = pointGrid(
      trainPoints,
      trainActual,
      lower,
      limits,
      data.params.plotSize,
    );
    for (var k = 0; k < c; k++) {
      final (x, y) = centroids[k];
      final col = cell(x, limits[0], limits[1], w),
          row = h - 1 - cell(y, limits[2], limits[3], h);
      grid[row][col] = upper[k];
    }
    final plot = [
      'plot x ${real(limits[0])} ${real(limits[1])} y ${real(limits[2])} ${real(limits[3])} size ${w}x$h',
      ...frame(grid),
    ];
    return [univariate, fisher, plot];
  }
}

void main() {
  final a = Analysis(readInputs());
  writeLines('models.txt', joinSections(a.modelSections()));
  writeLines('predictions.csv', a.predictionLines());
  writeLines('evaluation.txt', joinSections(a.evaluationSections()));
  writeLines('boundaries.txt', joinSections(a.boundarySections()));
  writeLines('projection.txt', joinSections(a.projectionSections()));
}
