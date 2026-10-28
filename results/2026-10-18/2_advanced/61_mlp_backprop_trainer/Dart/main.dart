import 'dart:io';
import 'dart:math';
part 'dataset.dart';
part 'layers.dart';
part 'network.dart';
part 'optimizers.dart';
part 'evaluation.dart';

class Evaluation {
  double loss = 0;
  int correct = 0;
  final results = <Forward>[];
}

Evaluation evaluate(Network n, List<double> theta, List<Image> data) {
  final out = Evaluation();
  for (final image in data) {
    final f = n.forward(theta, image);
    out.loss += f.loss;
    if (f.predicted == image.label) out.correct++;
    out.results.add(f);
  }
  out.loss /= data.length;
  return out;
}

class Epoch {
  final double eta, gradient, trainLoss, validationLoss;
  final int trainCorrect, validationCorrect;
  final bool improved;
  final List<bool> status;
  Epoch(
    this.eta,
    this.gradient,
    this.trainLoss,
    this.validationLoss,
    this.trainCorrect,
    this.validationCorrect,
    this.improved,
    this.status,
  );
}

class Run {
  final RunConfig config;
  final Network network;
  List<double> theta = [];
  final epochs = <Epoch>[];
  int bestEpoch = 0, bestCorrect = 0, updates = 0;
  double bestLoss = 0;
  String stop = 'max_epochs';
  late Evaluation test;
  late List<List<int>> matrix;
  Run(this.network, this.config);
}

void writeLines(String name, List<String> values) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${values.join('\n')}\n');
}

List<int> indices(int n) => List.generate(n, (i) => i);
void gradientCheck(List<Network> networks, List<Image> data, Params params) {
  final out = <String>[];
  for (var ni = 0; ni < networks.length; ni++) {
    final n = networks[ni];
    if (ni > 0) out.add('');
    final rng = RNG(params.seed), order = indices(data.length);
    rng.shuffle(order);
    final batch = order.take(min(params.batch, order.length)).toList(),
        theta = List<double>.of(n.initial);
    final (analytic, _) = n.meanGradient(theta, data, batch);
    final counts = List.generate(n.layers.length, (_) => List.filled(2, 0));
    var checked = 0, pass = true;
    for (var p = 0; p < theta.length; p += params.stride) {
      final original = theta[p];
      theta[p] = original + .00001;
      final (_, plus) = n.meanGradient(theta, data, batch);
      theta[p] = original - .00001;
      final (_, minus) = n.meanGradient(theta, data, batch);
      theta[p] = original;
      final numeric = (plus - minus) / (2 * .00001),
          error =
              (analytic[p] - numeric).abs() /
              max(1.0, analytic[p].abs() + numeric.abs());
      if (error >= .000001) pass = false;
      checked++;
      for (var l = 0; l < n.layers.length; l++) {
        final layer = n.layers[l];
        if (p >= layer.weights && p < layer.biases + layer.units) {
          counts[l][p >= layer.biases ? 1 : 0]++;
          break;
        }
      }
    }
    out.addAll([
      'network ${n.name}',
      'parameters ${theta.length}',
      'batch ${batch.map((i) => data[i].id).join(' ')}',
    ]);
    for (var l = 0; l < counts.length; l++) {
      out.add('layer ${l + 1} weights ${counts[l][0]} biases ${counts[l][1]}');
    }
    out.addAll(['checked $checked', 'result ${pass ? 'PASS' : 'FAIL'}']);
  }
  writeLines('gradient_check.txt', out);
}

Run trainRun(
  Network network,
  RunConfig config,
  Params params,
  List<Image> training,
  List<Image> validation,
  List<Image> test,
) {
  final out = Run(network, config),
      theta = List<double>.of(network.initial),
      order = indices(training.length),
      rng = RNG(params.seed),
      optimizer = Optimizer(config, theta.length);
  var wait = 0;
  for (var epoch = 1; epoch <= params.epochs; epoch++) {
    final eta = learningRate(config, params, epoch);
    rng.shuffle(order);
    var magnitude = 0.0, batches = 0;
    for (var start = 0; start < order.length; start += params.batch) {
      final batch = order.sublist(
        start,
        min(order.length, start + params.batch),
      );
      final (g, _) = network.meanGradient(theta, training, batch);
      for (final p in network.weightIndices) {
        g[p] = g[p] + config.lambda * theta[p];
      }
      var sum = 0.0;
      for (final v in g) {
        sum += v * v;
      }
      magnitude += sqrt(sum);
      batches++;
      optimizer.update(theta, g, eta);
      out.updates++;
    }
    final trainEval = evaluate(network, theta, training),
        valEval = evaluate(network, theta, validation),
        status = [
          for (var i = 0; i < training.length; i++)
            trainEval.results[i].predicted == training[i].label,
        ],
        improved = epoch == 1 || valEval.loss < out.bestLoss;
    if (improved) {
      out.bestLoss = valEval.loss;
      out.bestEpoch = epoch;
      out.bestCorrect = valEval.correct;
      out.theta = List.of(theta);
      wait = 0;
    } else {
      wait++;
    }
    out.epochs.add(
      Epoch(
        eta,
        magnitude / batches,
        trainEval.loss,
        valEval.loss,
        trainEval.correct,
        valEval.correct,
        improved,
        status,
      ),
    );
    if (wait >= params.patience) {
      out.stop = 'early';
      break;
    }
    if (epoch == params.epochs) break;
  }
  out.test = evaluate(network, out.theta, test);
  out.matrix = confusion(test, out.test.results, network.layers.last.units);
  return out;
}

void trainingOutputs(
  List<Run> runs,
  List<Image> training,
  List<Image> validation,
  List<Image> test,
) {
  final log = [
        'run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved',
      ],
      weights = <String>[],
      predictions = ['run,id,label,predicted,confidence'];
  for (var ri = 0; ri < runs.length; ri++) {
    final run = runs[ri];
    for (var e = 0; e < run.epochs.length; e++) {
      final record = run.epochs[e];
      log.add(
        '${run.config.name},${e + 1},${fixed(record.eta, 6)},${fixed(record.gradient, 4)},${fixed(record.trainLoss, 6)},${ratio(record.trainCorrect, training.length)},${fixed(record.validationLoss, 6)},${ratio(record.validationCorrect, validation.length)},${record.improved ? 1 : 0}',
      );
    }
    if (ri > 0) weights.add('');
    weights.add(
      'RUN ${run.config.name} NETWORK ${run.network.name} EPOCH ${run.bestEpoch}',
    );
    for (var l = 0; l < run.network.layers.length; l++) {
      final layer = run.network.layers[l];
      weights.add('LAYER ${l + 1} ${layer.units} ${layer.inputs}');
      for (var j = 0; j < layer.units; j++) {
        weights.add(
          'W ${[for (var i = 0; i < layer.inputs; i++) fixed(run.theta[layer.weights + j * layer.inputs + i], 4)].join(' ')}',
        );
      }
      weights.add(
        'B ${[for (var j = 0; j < layer.units; j++) fixed(run.theta[layer.biases + j], 4)].join(' ')}',
      );
    }
    for (var i = 0; i < test.length; i++) {
      final image = test[i], f = run.test.results[i];
      predictions.add(
        '${run.config.name},${image.id},${image.label},${f.predicted},${fixed(f.confidence, 4)}',
      );
    }
  }
  writeLines('training_log.csv', log);
  writeLines('final_weights.txt', weights);
  writeLines('predictions.csv', predictions);
}

(List<Image>, int) noisyImages(List<Image> test, int rate, int seed) {
  final rng = RNG(seed), out = <Image>[];
  var flips = 0;
  for (final image in test) {
    final pixels = image.pixels.split(''), input = List<double>.of(image.input);
    for (var i = 0; i < pixels.length; i++) {
      if (rng.next() % 100 < rate) {
        flips++;
        if (pixels[i] == '1') {
          pixels[i] = '0';
          input[i] = 0;
        } else {
          pixels[i] = '1';
          input[i] = 1;
        }
      }
    }
    out.add(Image(image.id, image.label, pixels.join(), input));
  }
  return (out, flips);
}

List<String> dataOutput(
  List<Image> training,
  List<Image> validation,
  List<Image> test,
  int k,
  int w,
  int h,
) {
  final counts = List.generate(k, (_) => List.filled(3, 0)),
      ink = List.filled(k, 0),
      pixels = List.generate(k, (_) => List.filled(w * h, 0)),
      levels = List.generate(k, (_) => List.filled(w * h, 0)),
      sequences = [training, validation, test];
  for (var which = 0; which < 3; which++) {
    for (final image in sequences[which]) {
      counts[image.label][which]++;
      if (which == 0) {
        for (var i = 0; i < image.pixels.length; i++) {
          if (image.pixels[i] == '1') {
            ink[image.label]++;
            pixels[image.label][i]++;
          }
        }
      }
    }
  }
  final out = [
        'data',
        'train ${training.length} validation ${validation.length} test ${test.length} pixels ${w * h}',
      ],
      names = ['mean_images'];
  for (var cl = 0; cl < k; cl++) {
    out.add(
      'class $cl train ${counts[cl][0]} validation ${counts[cl][1]} test ${counts[cl][2]} ink ${ratio(ink[cl], counts[cl][0])}',
    );
    names.add('$cl');
    if (counts[cl][0] > 0) {
      for (var i = 0; i < w * h; i++) {
        levels[cl][i] = min(9, 10 * pixels[cl][i] ~/ counts[cl][0]);
      }
    }
  }
  out.add(names.join(' '));
  out.addAll(levelLines(levels, w, h));
  return out;
}

List<String> runOutput(
  Run run,
  Params params,
  List<Image> training,
  List<Image> validation,
  List<Image> test,
  Map<int, List<Image>> noisy,
) {
  final n = run.network,
      k = n.layers.last.units,
      total = test.length,
      confidenceSum = List.filled(2, 0.0),
      confidenceCount = List.filled(2, 0),
      wrong = <String>[];
  var top2 = 0;
  for (var i = 0; i < test.length; i++) {
    final image = test[i],
        f = run.test.results[i],
        right = f.predicted == image.label,
        group = right ? 0 : 1;
    if (!right) wrong.add(image.id);
    confidenceSum[group] += f.confidence;
    confidenceCount[group]++;
    if (right || second(f.scores, f.predicted) == image.label) top2++;
  }
  final mean = [
    for (var g = 0; g < 2; g++)
      confidenceCount[g] > 0
          ? fixed(confidenceSum[g] / confidenceCount[g], 4)
          : '-',
  ];
  var forgetting = 0, forgotten = 0, never = 0;
  for (var i = 0; i < training.length; i++) {
    var count = 0, learned = false;
    for (var e = 0; e < run.epochs.length; e++) {
      final epoch = run.epochs[e];
      if (epoch.status[i]) learned = true;
      if (e > 0 && run.epochs[e - 1].status[i] && !epoch.status[i]) count++;
    }
    forgetting += count;
    if (count > 0) forgotten++;
    if (!learned) never++;
  }
  final norms = <String>[], changes = <String>[];
  for (final layer in n.layers) {
    var norm = 0.0, change = 0.0;
    for (var p = layer.weights; p < layer.biases; p++) {
      norm += run.theta[p] * run.theta[p];
      final d = run.theta[p] - n.initial[p];
      change += d * d;
    }
    norms.add(fixed(sqrt(norm), 4));
    changes.add(fixed(sqrt(change), 4));
  }
  final out = [
    'run ${run.config.name} network ${n.name} optimizer ${run.config.optimizer}',
    'epochs ${run.epochs.length} best_epoch ${run.bestEpoch} stop ${run.stop} updates ${run.updates}',
    'best_val_loss ${fixed(run.bestLoss, 6)} best_val_acc ${ratio(run.bestCorrect, validation.length)} correct ${run.bestCorrect}/${validation.length}',
    'test_loss ${fixed(run.test.loss, 6)} test_acc ${ratio(run.test.correct, total)} correct ${run.test.correct}/$total',
    'top2_acc ${ratio(top2, total)} correct $top2/$total',
    'confidence correct ${mean[0]} wrong ${mean[1]}',
    'forgetting events $forgetting rows $forgotten never_learned $never',
    'weight_norms ${norms.join(' ')}',
    'weight_changes ${changes.join(' ')}',
    'curve',
  ];
  var lmax = 0.0;
  for (final e in run.epochs) {
    lmax = max(lmax, max(e.trainLoss, e.validationLoss));
  }
  for (var e = 0; e < run.epochs.length; e++) {
    final record = run.epochs[e],
        row = List.filled(40, ' '),
        ct = (39 * record.trainLoss / lmax + .5).floor(),
        cv = (39 * record.validationLoss / lmax + .5).floor();
    row[ct] = 't';
    row[cv] = ct == cv ? '*' : 'v';
    out.add(
      '${(e + 1).toString().padLeft(2)} |${row.join()}|${e + 1 == run.bestEpoch ? ' best' : ''}',
    );
  }
  out.add('confusion');
  for (var cl = 0; cl < k; cl++) {
    out.add('$cl: ${run.matrix[cl].join(' ')}');
  }
  for (var cl = 0; cl < k; cl++) {
    final (support, predicted, precision, recall, f1) = classMetrics(
      run.matrix,
      cl,
    );
    out.add(
      'class $cl support $support predicted $predicted precision $precision recall $recall f1 $f1',
    );
  }
  out.add('calibration');
  final binCounts = List.filled(params.bins, 0),
      binCorrect = List.filled(params.bins, 0),
      binSums = List.filled(params.bins, 0.0);
  for (var i = 0; i < run.test.results.length; i++) {
    final f = run.test.results[i],
        bin = min(params.bins - 1, (f.confidence * params.bins).floor());
    binCounts[bin]++;
    binSums[bin] += f.confidence;
    if (f.predicted == test[i].label) binCorrect[bin]++;
  }
  var ece = 0.0;
  for (var bin = 0; bin < params.bins; bin++) {
    final count = binCounts[bin];
    var confidence = '-';
    if (count > 0) {
      final value = binSums[bin] / count;
      confidence = fixed(value, 4);
      ece += count / total * (binCorrect[bin] / count - value).abs();
    }
    out.add(
      'bin ${bin + 1} ${fixed(bin / params.bins, 2)} ${fixed((bin + 1) / params.bins, 2)} count $count accuracy ${ratio(binCorrect[bin], count)} confidence $confidence',
    );
  }
  out.add('ece ${fixed(ece, 4)}');
  for (var l = 0; l < n.layers.length - 1; l++) {
    final layer = n.layers[l],
        counts = List.filled(k, 0),
        sums = List.generate(k, (_) => List.filled(layer.units, 0.0)),
        zeros = List.filled(layer.units, 0);
    for (var i = 0; i < test.length; i++) {
      final image = test[i];
      counts[image.label]++;
      for (var j = 0; j < layer.units; j++) {
        final v = run.test.results[i].activations[l + 1][j];
        sums[image.label][j] += v;
        if (v == 0) zeros[j]++;
      }
    }
    out.add('hidden ${l + 1} ${layer.activation} units ${layer.units}');
    for (var cl = 0; cl < k; cl++) {
      final count = counts[cl];
      if (count == 0) {
        out.add('class $cl mean -');
      } else {
        for (var j = 0; j < layer.units; j++) {
          sums[cl][j] /= count;
        }
        out.add('class $cl mean ${sums[cl].map((v) => fixed(v, 4)).join(' ')}');
      }
    }
    final preferred = <int>[];
    for (var j = 0; j < layer.units; j++) {
      var best = -1;
      for (var cl = 0; cl < k; cl++) {
        if (counts[cl] > 0 && (best < 0 || sums[cl][j] > sums[best][j]))
          best = cl;
      }
      preferred.add(best);
    }
    out.add('preferred ${preferred.join(' ')}');
    if (layer.activation == 'RELU') out.add('zero_counts ${zeros.join(' ')}');
  }
  out.add('pruning');
  final ordered = List<int>.of(n.weightIndices)
    ..sort((i, j) {
      final c = run.theta[i].abs().compareTo(run.theta[j].abs());
      return c != 0 ? c : i.compareTo(j);
    });
  for (final fraction in params.prune) {
    final theta = List<double>.of(run.theta),
        removed = fraction * ordered.length ~/ 100;
    for (final p in ordered.take(removed)) {
      theta[p] = 0;
    }
    final evaluation = evaluate(n, theta, test);
    out.add(
      'prune $fraction removed $removed correct ${evaluation.correct} test_acc ${ratio(evaluation.correct, total)} test_loss ${fixed(evaluation.loss, 6)}',
    );
  }
  out.add('noise');
  for (final rate in params.noise) {
    final evaluation = evaluate(n, run.theta, noisy[rate]!);
    out.add(
      'noise $rate correct ${evaluation.correct} test_acc ${ratio(evaluation.correct, total)}',
    );
  }
  out.add(
    'misclassified ${wrong.length}${wrong.isEmpty ? '' : ' ${wrong.join(' ')}'}',
  );
  return out;
}

List<String> comparisonOutput(
  List<Run> runs,
  Params params,
  List<Image> all,
  List<Image> training,
  List<Image> test,
  int w,
  int h,
  int k,
  Map<int, int> flips,
) {
  final order = indices(runs.length)
        ..sort((i, j) {
          final x = runs[i], y = runs[j];
          var c = y.test.correct.compareTo(x.test.correct);
          if (c != 0) return c;
          c = x.bestLoss.compareTo(y.bestLoss);
          return c != 0 ? c : i.compareTo(j);
        }),
      top = runs[order.first],
      total = test.length,
      out = ['comparison'];
  for (var rank = 0; rank < order.length; rank++) {
    final r = runs[order[rank]];
    out.add(
      'rank ${rank + 1} ${r.config.name} correct ${r.test.correct} test_acc ${ratio(r.test.correct, total)} best_val_loss ${fixed(r.bestLoss, 6)} test_loss ${fixed(r.test.loss, 6)} best_epoch ${r.bestEpoch} epochs ${r.epochs.length} updates ${r.updates}',
    );
  }
  out.add('agreement');
  for (final a in runs) {
    final line = [a.config.name];
    for (final b in runs) {
      var count = 0;
      for (var i = 0; i < test.length; i++) {
        if (a.test.results[i].predicted == b.test.results[i].predicted) count++;
      }
      line.add('$count');
    }
    out.add(line.join(' '));
  }
  out.add('mcnemar ${top.config.name}');
  for (final index in order.skip(1)) {
    final r = runs[index];
    var b = 0, c = 0;
    for (var i = 0; i < test.length; i++) {
      final x = top.test.results[i].predicted == test[i].label,
          y = r.test.results[i].predicted == test[i].label;
      if (x && !y) b++;
      if (y && !x) c++;
    }
    final difference = max(0, (b - c).abs() - 1),
        numerator = difference * difference,
        denominator = b + c,
        chi = denominator > 0 ? ratio(numerator, denominator) : '0.0000',
        significant = numerator * 1000 > 3841 * denominator ? 'yes' : 'no';
    out.add('vs ${r.config.name} b $b c $c chi2 $chi significant $significant');
  }
  final ensemble = List.filled(total, 0);
  var ensembleCorrect = 0, fixedCount = 0, broken = 0;
  for (var i = 0; i < test.length; i++) {
    final image = test[i], votes = List.filled(k, 0);
    var maximum = 0;
    for (final r in runs) {
      final cl = r.test.results[i].predicted;
      votes[cl]++;
      maximum = max(maximum, votes[cl]);
    }
    var chosen = 0;
    for (final index in order) {
      final cl = runs[index].test.results[i].predicted;
      if (votes[cl] == maximum) {
        chosen = cl;
        break;
      }
    }
    ensemble[i] = chosen;
    final right = chosen == image.label,
        topRight = top.test.results[i].predicted == image.label;
    if (right) ensembleCorrect++;
    if (right && !topRight) fixedCount++;
    if (!right && topRight) broken++;
  }
  out.add(
    'ensemble correct $ensembleCorrect/$total test_acc ${ratio(ensembleCorrect, total)} fixed $fixedCount broken $broken',
  );
  final soft = [
    for (var i = 0; i < runs.length; i++)
      if (runs[i].network.layers.last.activation == 'SOFTMAX') i,
  ];
  if (soft.isEmpty) {
    out.add('soft_ensemble none');
  } else {
    var correct = 0;
    for (var i = 0; i < test.length; i++) {
      final means = List.filled(k, 0.0);
      for (final index in soft) {
        for (var cl = 0; cl < k; cl++) {
          means[cl] += runs[index].test.results[i].scores[cl];
        }
      }
      for (var cl = 0; cl < k; cl++) {
        means[cl] /= soft.length;
      }
      if (prediction(means) == test[i].label) correct++;
    }
    out.add(
      'soft_ensemble runs ${soft.length} correct $correct/$total test_acc ${ratio(correct, total)}',
    );
  }
  for (final rate in params.noise) {
    out.add('noise $rate flipped ${flips[rate]}');
  }
  final pairs = <(int, int, int)>[];
  for (var y = 0; y < k; y++) {
    for (var p = 0; p < k; p++) {
      if (y == p) continue;
      var count = 0;
      for (final r in runs) {
        count += r.matrix[y][p];
      }
      if (count > 0) pairs.add((y, p, count));
    }
  }
  pairs.sort((a, b) {
    var c = b.$3.compareTo(a.$3);
    if (c != 0) return c;
    c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  out.add('confused_pairs');
  for (final (y, p, count) in pairs.take(5)) {
    out.add('$y as $p count $count');
  }
  out.addAll([
    '',
    'saliency ${top.config.name}',
    'classes ${List.generate(k, (i) => i).join(' ')}',
  ]);
  final counts = List.filled(k, 0),
      sums = List.generate(k, (_) => List.filled(w * h, 0.0)),
      levels = List.generate(k, (_) => List.filled(w * h, 0));
  for (final image in test) {
    final (_, input, _) = top.network.gradient(top.theta, image);
    counts[image.label]++;
    for (var i = 0; i < input.length; i++) {
      sums[image.label][i] += input[i].abs();
    }
  }
  for (var cl = 0; cl < k; cl++) {
    final count = counts[cl];
    if (count == 0) continue;
    var maximum = 0.0;
    for (var i = 0; i < w * h; i++) {
      sums[cl][i] /= count;
      maximum = max(maximum, sums[cl][i]);
    }
    if (maximum > 0) {
      for (var i = 0; i < w * h; i++) {
        levels[cl][i] = min(9, (10 * sums[cl][i] / maximum).floor());
      }
    }
  }
  out.addAll(levelLines(levels, w, h));
  out.addAll(['', 'hardest_training_examples ${top.config.name}']);
  final trainingResults = evaluate(top.network, top.theta, training).results,
      hardest = indices(training.length)
        ..sort((i, j) {
          final c = trainingResults[j].loss.compareTo(trainingResults[i].loss);
          return c != 0 ? c : i.compareTo(j);
        });
  for (final index in hardest.take(5)) {
    final image = training[index], result = trainingResults[index];
    out.add(
      '${image.id} label ${image.label} predicted ${result.predicted} loss ${fixed(result.loss, 6)}',
    );
  }
  out.addAll(['', 'misclassified_examples ${top.config.name}']);
  for (var i = 0; i < test.length; i++) {
    final image = test[i], result = top.test.results[i];
    if (result.predicted == image.label) continue;
    final predictions = [for (final r in runs) r.test.results[i].predicted];
    out.add(
      '${image.id} label ${image.label} predicted ${result.predicted} confidence ${fixed(result.confidence, 4)} true_score ${fixed(result.scores[image.label], 4)} runs ${predictions.join(' ')} ensemble ${ensemble[i]}',
    );
    var nearest = 0, distance = image.pixels.length + 1;
    for (var index = 0; index < all.length; index++) {
      final candidate = all[index];
      var d = 0;
      for (var p = 0; p < image.pixels.length; p++) {
        if (image.pixels[p] != candidate.pixels[p]) d++;
      }
      if (d < distance) {
        nearest = index;
        distance = d;
      }
    }
    out.add(
      'nearest ${all[nearest].id} label ${all[nearest].label} distance $distance',
    );
    out.addAll(imageLines(image, w, h));
  }
  return out;
}

void main() {
  final all = readImages('input/train.csv'),
      test = readImages('input/test.csv');
  final (networks, w, h) = readNetworks();
  final params = readParams(),
      m = all.length - all.length ~/ 5,
      training = all.sublist(0, m),
      validation = all.sublist(m);
  gradientCheck(networks, training, params);
  final byName = {for (final n in networks) n.name: n},
      runs = [
        for (final config in params.runs)
          trainRun(
            byName[config.network]!,
            config,
            params,
            training,
            validation,
            test,
          ),
      ];
  trainingOutputs(runs, training, validation, test);
  final noisy = <int, List<Image>>{}, flips = <int, int>{};
  for (final rate in params.noise) {
    final (images, count) = noisyImages(test, rate, params.seed);
    noisy[rate] = images;
    flips[rate] = count;
  }
  final k = networks.first.layers.last.units,
      out = dataOutput(training, validation, test, k, w, h);
  out.add('');
  for (final run in runs) {
    out.addAll(runOutput(run, params, training, validation, test, noisy));
    out.add('');
  }
  out.addAll(
    comparisonOutput(runs, params, all, training, test, w, h, k, flips),
  );
  writeLines('evaluation.txt', out);
}
