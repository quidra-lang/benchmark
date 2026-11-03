import 'dart:io';
import 'dart:math';
part 'dataset.dart';
part 'kernels.dart';
part 'smo.dart';
part 'multiclass.dart';
part 'evaluation.dart';

class FoldResult {
  final int training, test, correct, support, passes, steps;
  final bool converged;
  FoldResult(
    this.training,
    this.test,
    this.correct,
    this.support,
    this.passes,
    this.steps,
    this.converged,
  );
}

class CV {
  final int kernel, cIndex;
  final double c;
  int correct = 0, support = 0, passes = 0, steps = 0;
  final List<double> values;
  final folds = <FoldResult>[];
  CV(this.kernel, this.cIndex, this.c, int n) : values = List.filled(n, 0);
}

List<double> decisions(Model m, List<Example> data) =>
    data.map((e) => m.decision(e.point)).toList();
String runInfo(Model m) =>
    'passes ${m.passes.length} steps ${m.steps} converged ${yes(m.converged)}';
String svInfo(Model m) {
  final (total, bound, free) = m.counts();
  return 'support_vectors $total bound $bound free $free';
}

class Calibration {
  double a = 0, b = 0;
  final probabilities = <double>[], report = <String>[];
}

double probability(double v, double a, double b) => 1 / (1 + exp(a * v + b));

class Pegasos {
  final weights = List.filled(3, 0.0),
      average = List.filled(3, 0.0),
      values = <double>[],
      report = <String>[];
}

double linearValue(List<double> w, Point p) => w[0] * p.$1 + w[1] * p.$2 + w[2];
List<double> linearValues(List<double> w, List<Example> data) =>
    data.map((e) => linearValue(w, e.point)).toList();

class Application {
  final List<Example> trainData, testData;
  final Params params;
  final matrices = <List<List<double>>>[],
      grid = <List<CV>>[],
      models = <Model>[],
      trainValues = <List<double>>[],
      testValues = <List<double>>[];
  late final List<int> best;
  int selected = 0;
  Application(this.trainData, this.testData, this.params);
  void prepare() {
    final n = trainData.length, p = params;
    best = List.filled(p.kernels.length, 0);
    for (var ki = 0; ki < p.kernels.length; ki++) {
      final k = p.kernels[ki], q = kernelMatrix(trainData, k), row = <CV>[];
      matrices.add(q);
      for (var ci = 0; ci < p.cs.length; ci++) {
        final c = p.cs[ci], cv = CV(ki, ci, c, n);
        for (var fold = 0; fold < p.folds; fold++) {
          final (training, validation) = folds(n, p.folds, fold);
          final (data, matrix) = subset(trainData, q, training);
          final m = train(data, matrix, k, c, p);
          var count = 0;
          for (final i in validation) {
            final v = m.decision(trainData[i].point);
            cv.values[i] = v;
            if (sign(v) == trainData[i].label) count++;
          }
          final (support, _, _) = m.counts();
          cv.folds.add(
            FoldResult(
              training.length,
              validation.length,
              count,
              support,
              m.passes.length,
              m.steps,
              m.converged,
            ),
          );
          cv.correct += count;
          cv.support += support;
          cv.passes += m.passes.length;
          cv.steps += m.steps;
        }
        row.add(cv);
        if (ci == 0 || cv.correct > row[best[ki]].correct) best[ki] = ci;
      }
      grid.add(row);
      final chosen = grid[ki][best[ki]],
          current = grid[selected][best[selected]];
      if (chosen.correct > current.correct ||
          (chosen.correct == current.correct && chosen.c < current.c))
        selected = ki;
      final m = train(trainData, q, k, chosen.c, p);
      models.add(m);
      trainValues.add(m.trainingValues());
      testValues.add(decisions(m, testData));
    }
  }

  List<String> cvOutput() {
    final n = trainData.length,
        p = params,
        out = ['cross_validation folds ${p.folds} examples $n'],
        ranked = <CV>[],
        header = [
          'kernel',
          'C',
          for (var i = 1; i <= p.folds; i++) 'fold$i',
          'correct',
          'accuracy',
          'support_vectors',
          'passes',
          'steps',
        ],
        csv = <String>[];
    csv.add(header.join(','));
    for (var ki = 0; ki < p.kernels.length; ki++) {
      final k = p.kernels[ki], chosen = grid[ki][best[ki]];
      out.add(
        'best ${k.name} C ${fixed(chosen.c, 4)} correct ${chosen.correct}/$n accuracy ${ratio(chosen.correct, n)}',
      );
      for (final cv in grid[ki]) {
        ranked.add(cv);
        csv.add(
          [
            k.name,
            fixed(cv.c, 4),
            ...cv.folds.map((f) => '${f.correct}'),
            '${cv.correct}',
            ratio(cv.correct, n),
            '${cv.support}',
            '${cv.passes}',
            '${cv.steps}',
          ].join(','),
        );
      }
    }
    final chosen = grid[selected][best[selected]],
        name = p.kernels[selected].name;
    out.addAll(['selected $name C ${fixed(chosen.c, 4)}', 'ranking']);
    ranked.sort((x, y) {
      var c = y.correct.compareTo(x.correct);
      if (c != 0) return c;
      c = x.c.compareTo(y.c);
      return c != 0 ? c : x.kernel.compareTo(y.kernel);
    });
    for (var i = 0; i < ranked.length; i++) {
      final cv = ranked[i];
      out.add(
        '${i + 1} ${p.kernels[cv.kernel].name} C ${fixed(cv.c, 4)} correct ${cv.correct}/$n',
      );
    }
    out.add('cv_detail $name C ${fixed(chosen.c, 4)}');
    for (var i = 0; i < chosen.folds.length; i++) {
      final f = chosen.folds[i];
      out.add(
        'fold ${i + 1} train ${f.training} test ${f.test} correct ${f.correct} support_vectors ${f.support} passes ${f.passes} steps ${f.steps} converged ${yes(f.converged)}',
      );
    }
    writeLines('cv_grid.csv', csv);
    return out;
  }

  List<String> modelOutput(int ki) {
    final m = models[ki],
        q = matrices[ki],
        trainF = trainValues[ki],
        testF = testValues[ki],
        n = trainData.length,
        nt = testData.length,
        weights = List.filled(2, 0.0),
        counts = List.generate(2, (_) => List.filled(2, 0));
    var alignmentY = 0.0,
        alignmentG = 0.0,
        equality = 0.0,
        maximumDiagonal = q[0][0],
        minimumEntry = q[0][0];
    for (var i = 0; i < n; i++) {
      final e = trainData[i];
      equality += m.alpha[i] * e.label;
      weights[0] += m.alpha[i] * e.label * e.point.$1;
      weights[1] += m.alpha[i] * e.label * e.point.$2;
      if (m.alpha[i] > 0)
        counts[e.label == 1 ? 0 : 1][m.alpha[i] == m.c ? 0 : 1]++;
      maximumDiagonal = max(maximumDiagonal, q[i][i]);
      for (var j = 0; j < n; j++) {
        alignmentY += e.label * trainData[j].label * q[i][j];
        alignmentG += q[i][j] * q[i][j];
        minimumEntry = min(minimumEntry, q[i][j]);
      }
    }
    final (quadratic, dual) = objective(m.alpha, m.data, m.q);
    final norm = sqrt(quadratic), radius = maximumDiagonal - minimumEntry;
    var hinge = 0.0, maximumViolation = 0.0, violations = 0, estimate = 0;
    for (var i = 0; i < n; i++) {
      final yf = trainData[i].label * trainF[i],
          xi = max(0.0, 1 - yf),
          r = yf - 1;
      hinge += xi;
      final v = m.alpha[i] == 0
          ? max(0.0, -r)
          : m.alpha[i] == m.c
          ? max(0.0, r)
          : r.abs();
      if (v > params.tolerance) violations++;
      maximumViolation = max(maximumViolation, v);
      if (2 * m.alpha[i] * radius + xi >= 1) estimate++;
    }
    final primal = quadratic / 2 + m.c * hinge,
        metrics = evaluate(testData, testF),
        trainCorrect = correct(trainData, trainF),
        out = [
          'model ${m.kernel.name}',
          'kernel ${m.kernel.description}',
          'C ${fixed(m.c, 4)}',
          'alignment ${fixed(alignmentY / (n * sqrt(alignmentG)), 6)}',
          'passes ${m.passes.length} full ${m.full} nonbound ${m.nonbound} converged ${yes(m.converged)}',
          'examined ${m.examined} steps ${m.steps}',
          'choice heuristic ${m.choice[0]} nonbound_loop ${m.choice[1]} full_loop ${m.choice[2]}',
          'clipping none ${m.clipping[0]} lower ${m.clipping[1]} upper ${m.clipping[2]}',
          svInfo(m),
          'b ${fixed(m.b, 6)}',
          'equality ${fixed(equality, 6)}',
        ];
    if (m.kernel.kind == 'linear')
      out.add('w ${fixed(weights[0], 6)} ${fixed(weights[1], 6)}');
    out.addAll([
      'sv_by_class positive bound ${counts[0][0]} free ${counts[0][1]} negative bound ${counts[1][0]} free ${counts[1][1]}',
      'norm ${fixed(norm, 6)} margin ${fixed(2 / norm, 6)}',
      'dual_objective ${fixed(dual, 6)}',
      'primal_objective ${fixed(primal, 6)}',
      'duality_gap ${fixed(primal - dual, 6)}',
      'kkt_violations $violations max ${fixed(maximumViolation, 6)}',
      'xi_alpha radius ${fixed(radius, 6)} errors $estimate/$n accuracy ${ratio(n - estimate, n)}',
      'train correct $trainCorrect/$n accuracy ${ratio(trainCorrect, n)}',
      'test correct ${metrics.correct}/$nt accuracy ${ratio(metrics.correct, nt)} tp ${metrics.tp} fp ${metrics.fp} tn ${metrics.tn} fn ${metrics.fn}',
      'test precision ${ratio(metrics.tp, metrics.tp + metrics.fp)} recall ${ratio(metrics.tp, metrics.tp + metrics.fn)} f1 ${ratio(2 * metrics.tp, 2 * metrics.tp + metrics.fp + metrics.fn)} auc ${fixed(metrics.auc, 4)}',
      'test inside_margin ${metrics.inside}',
      'test mean_decision positive ${fixed(metrics.positiveMean, 4)} negative ${fixed(metrics.negativeMean, 4)}',
    ]);
    for (var i = 0; i < n; i++) {
      if (m.alpha[i] <= 0) continue;
      final e = trainData[i], kind = m.alpha[i] == m.c ? 'bound' : 'free';
      out.add(
        'sv ${e.id} y ${e.label} alpha ${fixed(m.alpha[i], 6)} f ${fixed(trainF[i], 4)} $kind',
      );
    }
    return out;
  }

  List<String> progressOutput() {
    final m = models[selected], out = ['training_log ${m.kernel.name}'];
    for (var i = 0; i < m.passes.length;) {
      final pass = m.passes[i];
      if (pass.full) {
        final (_, dual) = objective(pass.alpha, m.data, m.q);
        out.add(
          'pass ${i + 1} full examined ${pass.examined} changed ${pass.changed} dual_objective ${fixed(dual, 6)}',
        );
        i++;
      } else {
        var j = i, examined = 0, changed = 0;
        while (j < m.passes.length && !m.passes[j].full) {
          examined += m.passes[j].examined;
          changed += m.passes[j].changed;
          j++;
        }
        out.add(
          'passes ${i + 1}-$j nonbound examined $examined changed $changed',
        );
        i = j;
      }
    }
    return out;
  }

  List<String> pathOutput() {
    final selectedModel = models[selected],
        out = ['c_path ${selectedModel.kernel.name}'];
    for (final c in params.cs) {
      final m = train(
        trainData,
        matrices[selected],
        selectedModel.kernel,
        c,
        params,
      );
      final (_, dual) = objective(m.alpha, m.data, m.q);
      out.add(
        'C ${fixed(c, 4)} ${svInfo(m)} dual_objective ${fixed(dual, 6)} train ${correct(trainData, m.trainingValues())}/${trainData.length} test ${correct(testData, decisions(m, testData))}/${testData.length} ${runInfo(m)}',
      );
    }
    return out;
  }

  List<String> learningOutput() {
    final selectedModel = models[selected],
        out = [
          'learning_curve ${selectedModel.kernel.name} C ${fixed(selectedModel.c, 4)}',
        ];
    for (final fraction in params.learning) {
      final s = trainData.length * fraction ~/ 100,
          indices = List.generate(s, (i) => i);
      final (data, q) = subset(trainData, matrices[selected], indices);
      final m = train(data, q, selectedModel.kernel, selectedModel.c, params);
      final (support, _, _) = m.counts();
      out.add(
        'size $s support_vectors $support train ${correct(data, m.trainingValues())}/$s test ${correct(testData, decisions(m, testData))}/${testData.length} ${runInfo(m)}',
      );
    }
    return out;
  }

  Calibration calibrate() {
    final selectedModel = models[selected],
        values = grid[selected][best[selected]].values,
        positive = trainData.where((e) => e.label == 1).length,
        negative = trainData.length - positive,
        targets = [
          for (final e in trainData)
            e.label == 1 ? (positive + 1) / (positive + 2) : 1 / (negative + 2),
        ],
        out = Calibration()..b = log((negative + 1) / (positive + 1));
    double nll() {
      var s = 0.0;
      for (var i = 0; i < values.length; i++) {
        final p = probability(values[i], out.a, out.b);
        s += targets[i] * log(p) + (1 - targets[i]) * log(1 - p);
      }
      return -s;
    }

    out.report.addAll([
      'calibration ${selectedModel.kernel.name} C ${fixed(selectedModel.c, 4)} positives $positive negatives $negative',
      'start A ${fixed(out.a, 6)} B ${fixed(out.b, 6)} nll ${fixed(nll(), 6)}',
    ]);
    for (var iteration = 1; iteration <= params.newton; iteration++) {
      var g1 = 0.0, g2 = 0.0, h11 = 0.0, h21 = 0.0, h22 = 0.0;
      for (var i = 0; i < values.length; i++) {
        final v = values[i], p = probability(v, out.a, out.b);
        g1 += v * (targets[i] - p);
        g2 += targets[i] - p;
        h11 += v * v * p * (1 - p);
        h21 += v * p * (1 - p);
        h22 += p * (1 - p);
      }
      final det = h11 * h22 - h21 * h21,
          da = (h22 * g1 - h21 * g2) / det,
          db = (h11 * g2 - h21 * g1) / det;
      out.a -= da;
      out.b -= db;
      out.report.add(
        'iteration $iteration A ${fixed(out.a, 6)} B ${fixed(out.b, 6)} nll ${fixed(nll(), 6)}',
      );
    }
    var logLoss = 0.0, brier = 0.0;
    final counts = List.filled(5, 0),
        positiveBins = List.filled(5, 0),
        means = List.filled(5, 0.0);
    for (var j = 0; j < testData.length; j++) {
      final e = testData[j],
          p = probability(testValues[selected][j], out.a, out.b);
      out.probabilities.add(p);
      logLoss += e.label == 1 ? log(p) : log(1 - p);
      final d = p - (e.label == 1 ? 1 : 0);
      brier += d * d;
      final bin = min(4, (p * 5).floor());
      counts[bin]++;
      means[bin] += p;
      if (e.label == 1) positiveBins[bin]++;
    }
    out.report.add(
      'test log_loss ${fixed(-logLoss / testData.length, 6)} brier ${fixed(brier / testData.length, 6)}',
    );
    const ranges = ['0.0-0.2', '0.2-0.4', '0.4-0.6', '0.6-0.8', '0.8-1.0'];
    for (var bin = 0; bin < 5; bin++) {
      final count = counts[bin],
          mean = count > 0 ? fixed(means[bin] / count, 4) : '-';
      out.report.add(
        'bin ${ranges[bin]} count $count mean_probability $mean positive_rate ${ratio(positiveBins[bin], count)}',
      );
    }
    final closest = List.generate(testData.length, (i) => i)
      ..sort((i, j) {
        final c = testValues[selected][i].abs().compareTo(
          testValues[selected][j].abs(),
        );
        return c != 0 ? c : i.compareTo(j);
      });
    for (final j in closest.take(5)) {
      out.report.add(
        'closest ${testData[j].id} label ${testData[j].label} decision ${fixed(testValues[selected][j], 4)} probability ${fixed(out.probabilities[j], 4)}',
      );
    }
    return out;
  }

  Pegasos pegasos() {
    final p = params,
        out = Pegasos(),
        sums = List.filled(3, 0.0),
        n = trainData.length;
    out.report.add(
      'pegasos lambda ${fixed(p.lambda, 4)} iterations ${p.iterations} seed ${p.seed}',
    );
    var state = p.seed, updates = 0;
    for (var t = 1; t <= p.iterations; t++) {
      state = 48271 * state % 2147483647;
      final e = trainData[state % n],
          eta = 1 / (p.lambda * t),
          sigma = 1 - eta * p.lambda,
          w = out.weights,
          violation = e.label * linearValue(w, e.point) < 1;
      if (violation) {
        w[0] = sigma * w[0] + eta * e.label * e.point.$1;
        w[1] = sigma * w[1] + eta * e.label * e.point.$2;
        w[2] = sigma * w[2] + eta * e.label;
        updates++;
      } else {
        for (var j = 0; j < 3; j++) {
          w[j] = sigma * w[j];
        }
      }
      for (var j = 0; j < 3; j++) {
        sums[j] += w[j];
      }
      if (t % (p.iterations ~/ 10) == 0) {
        final values = linearValues(w, trainData);
        var hinge = 0.0;
        for (var i = 0; i < n; i++) {
          hinge += max(0.0, 1 - trainData[i].label * values[i]);
        }
        final objective =
            p.lambda / 2 * (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) +
            hinge / n;
        out.report.add(
          'checkpoint $t objective ${fixed(objective, 6)} train ${correct(trainData, values)}/$n',
        );
      }
    }
    for (var j = 0; j < 3; j++) {
      out.average[j] = sums[j] / p.iterations;
    }
    out.values.addAll(linearValues(out.weights, testData));
    final trainCorrect = correct(
          trainData,
          linearValues(out.weights, trainData),
        ),
        testCorrect = correct(testData, out.values),
        averageCorrect = correct(testData, linearValues(out.average, testData)),
        comparison = p.kernels.indexWhere((k) => k.kind == 'linear'),
        m = models[comparison],
        v = List.filled(2, 0.0);
    for (var i = 0; i < n; i++) {
      final e = trainData[i];
      v[0] += m.alpha[i] * e.label * e.point.$1;
      v[1] += m.alpha[i] * e.label * e.point.$2;
    }
    final w = out.weights,
        cosine =
            (w[0] * v[0] + w[1] * v[1]) /
            (sqrt(w[0] * w[0] + w[1] * w[1]) * sqrt(v[0] * v[0] + v[1] * v[1]));
    var agreement = 0;
    for (var j = 0; j < out.values.length; j++) {
      if (sign(out.values[j]) == sign(testValues[comparison][j])) agreement++;
    }
    out.report.addAll([
      'updates $updates',
      'w ${fixed(w[0], 6)} ${fixed(w[1], 6)} bias ${fixed(w[2], 6)}',
      'train correct $trainCorrect/$n accuracy ${ratio(trainCorrect, n)}',
      'test correct $testCorrect/${testData.length} accuracy ${ratio(testCorrect, testData.length)}',
      'average w ${fixed(out.average[0], 6)} ${fixed(out.average[1], 6)} bias ${fixed(out.average[2], 6)} test correct $averageCorrect/${testData.length}',
      'compare ${p.kernels[comparison].name} cosine ${fixed(cosine, 6)} test_agreement $agreement/${testData.length}',
    ]);
    return out;
  }

  List<String> mcnemar(Pegasos peg) {
    final out = ['mcnemar'],
        names = [...params.kernels.map((k) => k.name), 'pegasos'],
        values = [...testValues, peg.values];
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        var first = 0, second = 0;
        for (var k = 0; k < testData.length; k++) {
          final x = sign(values[i][k]) == testData[k].label,
              y = sign(values[j][k]) == testData[k].label;
          if (x && !y) first++;
          if (y && !x) second++;
        }
        var chi = '-';
        if (first + second > 0) {
          final d = (first - second).abs() - 1;
          chi = fixed(d * d / (first + second), 4);
        }
        out.add(
          '${names[i]} ${names[j]} only_first $first only_second $second chi2 $chi',
        );
      }
    }
    return out;
  }

  void predictionsOutput(Calibration cal, Pegasos peg) {
    final header = [
          'id',
          'label',
          ...params.kernels.map((k) => k.name),
          'pegasos',
          'predicted',
          'probability',
        ],
        out = [header.join(',')];
    for (var i = 0; i < testData.length; i++) {
      final e = testData[i];
      out.add(
        [
          e.id,
          '${e.label}',
          for (final values in testValues) fixed(values[i], 4),
          fixed(peg.values[i], 4),
          '${sign(testValues[selected][i])}',
          fixed(cal.probabilities[i], 4),
        ].join(','),
      );
    }
    writeLines('predictions.csv', out);
  }

  void plots(
    Calibration cal,
    Multiclass multi,
    Kernel multiKernel,
    List<Example> multiData,
  ) {
    final p = params,
        selectedModel = models[selected],
        dx = (p.xMax - p.xMin) / p.w,
        dy = (p.yMax - p.yMin) / p.h,
        binary = List.generate(p.h, (_) => List.filled(p.w, ' ')),
        probabilities = List.generate(p.h, (_) => List.filled(p.w, ' ')),
        multiplot = List.generate(p.h, (_) => List.filled(p.w, ' ')),
        gridSigns = List.generate(
          models.length,
          (_) => List.filled(p.w * p.h, 0),
        ),
        positiveCounts = List.filled(models.length, 0),
        levels = List.filled(10, 0);
    for (var r = 0; r < p.h; r++) {
      for (var c = 0; c < p.w; c++) {
        final point = (p.xMin + (c + .5) * dx, p.yMax - (r + .5) * dy),
            value = selectedModel.decision(point);
        binary[r][c] = value >= 1
            ? '+'
            : value > 0
            ? '.'
            : value > -1
            ? '-'
            : ' ';
        final level = min(9, (probability(value, cal.a, cal.b) * 10).floor());
        probabilities[r][c] = '$level';
        levels[level]++;
        for (var i = 0; i < models.length; i++) {
          final sgn = sign(models[i].decision(point));
          gridSigns[i][r * p.w + c] = sgn;
          if (sgn == 1) positiveCounts[i]++;
        }
        final mp = multi.classify(point);
        multiplot[r][c] = mp.ovr == mp.ovo ? [' ', '.', ':'][mp.ovr - 1] : '?';
      }
    }
    (int, bool) position(Point point) {
      final c = ((point.$1 - p.xMin) / dx).floor(),
          r = ((p.yMax - point.$2) / dy).floor();
      return (r * p.w + c, r >= 0 && r < p.h && c >= 0 && c < p.w);
    }

    final owners = List.filled(p.w * p.h, -1);
    var outside = 0, points = 0;
    for (var i = 0; i < trainData.length; i++) {
      final (index, inside) = position(trainData[i].point);
      if (!inside) {
        outside++;
        continue;
      }
      final old = owners[index];
      if (old < 0 ||
          (selectedModel.alpha[i] > 0 && selectedModel.alpha[old] == 0))
        owners[index] = i;
    }
    for (var index = 0; index < owners.length; index++) {
      final i = owners[index];
      if (i < 0) continue;
      points++;
      var ch = trainData[i].label == 1 ? 'x' : 'o';
      if (selectedModel.alpha[i] > 0) ch = ch == 'x' ? 'X' : 'O';
      binary[index ~/ p.w][index % p.w] = ch;
    }
    Map<String, int> characterCounts(List<List<String>> grid) {
      final counts = <String, int>{};
      for (final row in grid) {
        for (final ch in row) {
          counts[ch] = (counts[ch] ?? 0) + 1;
        }
      }
      return counts;
    }

    var counts = characterCounts(binary);
    final out = [
      'binary ${selectedModel.kernel.name} C ${fixed(selectedModel.c, 4)}',
      'x ${fixed(p.xMin, 4)} ${fixed(p.xMax, 4)} y ${fixed(p.yMin, 4)} ${fixed(p.yMax, 4)} grid ${p.w}x${p.h}',
      ...framed(binary),
      'cells outer_positive ${counts['+'] ?? 0} inner_positive ${counts['.'] ?? 0} inner_negative ${counts['-'] ?? 0} outer_negative ${counts[' '] ?? 0} points $points outside $outside',
      '',
      'probability ${selectedModel.kernel.name} A ${fixed(cal.a, 6)} B ${fixed(cal.b, 6)}',
      ...framed(probabilities),
      'levels ${levels.join(' ')}',
      '',
      'grid_agreement',
    ];
    for (var i = 0; i < p.kernels.length; i++) {
      for (var j = i + 1; j < p.kernels.length; j++) {
        var agreement = 0;
        for (var index = 0; index < p.w * p.h; index++) {
          if (gridSigns[i][index] == gridSigns[j][index]) agreement++;
        }
        out.add(
          '${p.kernels[i].name} ${p.kernels[j].name} $agreement/${p.w * p.h} positive ${positiveCounts[i]} ${positiveCounts[j]}',
        );
      }
    }
    owners.fillRange(0, owners.length, -1);
    outside = 0;
    points = 0;
    for (var i = 0; i < multiData.length; i++) {
      final (index, inside) = position(multiData[i].point);
      if (!inside) {
        outside++;
        continue;
      }
      if (owners[index] < 0) owners[index] = i;
    }
    for (var index = 0; index < owners.length; index++) {
      final i = owners[index];
      if (i >= 0) {
        points++;
        multiplot[index ~/ p.w][index % p.w] = '${multiData[i].label}';
      }
    }
    counts = characterCounts(multiplot);
    out.addAll([
      '',
      'multiclass ${multiKernel.name} C ${fixed(p.multiclassC, 4)}',
      ...framed(multiplot),
      'cells class1 ${counts[' '] ?? 0} class2 ${counts['.'] ?? 0} class3 ${counts[':'] ?? 0} disagree ${counts['?'] ?? 0} points $points outside $outside',
    ]);
    writeLines('decision_plot.txt', out);
  }
}

List<String> framed(List<List<String>> grid) => [
  '+${'-' * grid.first.length}+',
  ...grid.map((r) => '|${r.join()}|'),
  '+${'-' * grid.first.length}+',
];
void multiclassOutput(
  Multiclass model,
  Kernel k,
  double c,
  List<Example> trainData,
  List<Example> testData,
) {
  final out = [
    'multiclass kernel ${k.name} C ${fixed(c, 4)} classes 3 train ${trainData.length} test ${testData.length}',
    'ovr',
  ];
  for (var i = 0; i < 3; i++) {
    final m = model.rest[i],
        positive = m.data.where((e) => e.label == 1).length;
    var testCorrect = 0;
    for (final e in testData) {
      if (sign(m.decision(e.point)) == (e.label == i + 1 ? 1 : -1))
        testCorrect++;
    }
    out.add(
      'model ${i + 1}-rest examples ${m.data.length} positives $positive ${svInfo(m)} b ${fixed(m.b, 6)} ${runInfo(m)} test $testCorrect/${testData.length}',
    );
  }
  out.add('ovo');
  for (var i = 0; i < 3; i++) {
    final m = model.pair[i],
        pair = classPairs[i],
        positive = m.data.where((e) => e.label == 1).length;
    var testCorrect = 0, testCount = 0;
    for (final e in testData) {
      if (e.label != pair.$1 && e.label != pair.$2) continue;
      testCount++;
      if (sign(m.decision(e.point)) == (e.label == pair.$1 ? 1 : -1))
        testCorrect++;
    }
    out.add(
      'model ${pair.$1}-${pair.$2} examples ${m.data.length} positives $positive ${svInfo(m)} b ${fixed(m.b, 6)} ${runInfo(m)} test $testCorrect/$testCount',
    );
  }
  out.add('predictions');
  final testPredictions = <MultiPrediction>[];
  for (final e in testData) {
    final p = model.classify(e.point);
    testPredictions.add(p);
    out.add(
      '${e.id} class ${e.label} ovr ${p.rest.map((v) => fixed(v, 4)).join(' ')} pred ${p.ovr} ovo ${p.pair.map((v) => fixed(v, 4)).join(' ')} votes ${p.votes.join(' ')} pred ${p.ovo}',
    );
  }
  for (var index = 0; index < 2; index++) {
    final data = index == 0 ? trainData : testData;
    var ovr = 0, ovo = 0, agreement = 0, ties = 0;
    for (final e in data) {
      final p = model.classify(e.point);
      if (p.ovr == e.label) ovr++;
      if (p.ovo == e.label) ovo++;
      if (p.ovr == p.ovo) agreement++;
      if (p.tie) ties++;
    }
    final n = data.length;
    out.add(
      '${index == 0 ? 'train' : 'test'} ovr $ovr/$n ${ratio(ovr, n)} ovo $ovo/$n ${ratio(ovo, n)} agreement $agreement/$n vote_ties $ties',
    );
  }
  for (var index = 0; index < 2; index++) {
    final predictions = testPredictions
            .map((p) => index == 0 ? p.ovr : p.ovo)
            .toList(),
        matrix = confusion(testData, predictions);
    out.add('confusion ${index == 0 ? 'ovr' : 'ovo'}');
    for (final row in matrix) {
      out.add(row.join(' '));
    }
    for (var cl = 0; cl < 3; cl++) {
      var column = 0, row = 0;
      for (var j = 0; j < 3; j++) {
        column += matrix[j][cl];
        row += matrix[cl][j];
      }
      out.add(
        'class ${cl + 1} precision ${ratio(matrix[cl][cl], column)} recall ${ratio(matrix[cl][cl], row)}',
      );
    }
  }
  writeLines('multiclass.txt', out);
}

void main() {
  final a = Application(
    readExamples('input/train.csv'),
    readExamples('input/test.csv'),
    readParams(),
  );
  a.prepare();
  final parts = [
        a.cvOutput(),
        for (var i = 0; i < a.params.kernels.length; i++) a.modelOutput(i),
        a.progressOutput(),
        a.pathOutput(),
        a.learningOutput(),
      ],
      cal = a.calibrate(),
      peg = a.pegasos();
  parts.addAll([cal.report, peg.report, a.mcnemar(peg)]);
  final out = <String>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) out.add('');
    out.addAll(parts[i]);
  }
  writeLines('model.txt', out);
  a.predictionsOutput(cal, peg);
  final (multiTrain, multiTest) = readMulticlass();
  final kernel = a.params.kernels.firstWhere(
        (k) => k.name == a.params.multiclass,
      ),
      multi = trainMulticlass(
        multiTrain,
        kernel,
        a.params.multiclassC,
        a.params,
      );
  multiclassOutput(multi, kernel, a.params.multiclassC, multiTrain, multiTest);
  a.plots(cal, multi, kernel, multiTrain);
}
