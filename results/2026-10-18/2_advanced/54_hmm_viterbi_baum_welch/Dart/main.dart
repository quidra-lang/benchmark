import 'dart:io';
import 'dart:math';

part 'model_io.dart';
part 'inference.dart';
part 'training.dart';
part 'evaluation.dart';
part 'sampler.dart';

class Candidate {
  final String text;
  final double value;
  Candidate(this.text, this.value);
}

class Params {
  late final int iterations,
      folds,
      minLength,
      maxMissing,
      target,
      mergeGap,
      minSegment,
      minRich,
      minMotif,
      boundaryTolerance,
      posteriorSeed,
      posteriorSamples,
      sampleSeed,
      sampleCount,
      sampleLength;
  late final double pseudocount, confidence;
  late final List<Candidate> smoothing;
  late final List<int> motif;
  late final Set<int> rich;
  Params(Map<String, List<String>> raw, Model model) {
    int integer(String key) => int.parse(raw[key]![0]);
    iterations = integer('iterations');
    pseudocount = double.parse(raw['pseudocount']![0]);
    smoothing = [
      for (final text in raw['smoothing']!) Candidate(text, double.parse(text)),
    ];
    folds = integer('folds');
    minLength = integer('min_sequence_length');
    maxMissing = integer('max_missing_percent');
    target = model.states.indexOf(raw['segment_state']![0]);
    mergeGap = integer('merge_gap');
    minSegment = integer('min_segment_length');
    motif = [for (final symbol in raw['motif']!) model.symbols.indexOf(symbol)];
    rich = {
      for (final symbol in raw['rich_symbols']!) model.symbols.indexOf(symbol),
    };
    minRich = integer('min_rich_percent');
    minMotif = integer('min_motif_percent');
    confidence = double.parse(raw['confidence']![0]);
    boundaryTolerance = integer('boundary_tolerance');
    posteriorSeed = integer('posterior_seed');
    posteriorSamples = integer('posterior_samples');
    sampleSeed = integer('sample_seed');
    sampleCount = integer('sample_count');
    sampleLength = integer('sample_length');
  }
}

class SequenceRecord {
  final String name, role, upper;
  final List<int> observations, path;
  final int missing;
  SequenceRecord(
    this.name,
    this.role,
    this.upper,
    this.observations,
    this.path,
    this.missing,
  );
}

class Validated {
  final List<SequenceRecord> unlabeled, train, test;
  final List<String> rejections;
  final int unlabeledRejected, labeledRejected;
  Validated(
    this.unlabeled,
    this.train,
    this.test,
    this.rejections,
    this.unlabeledRejected,
    this.labeledRejected,
  );
}

(List<SequenceRecord>, List<String>) validate(
  List<RawRecord> raws,
  bool labeled,
  Model model,
  Params p,
) {
  final seen = <String>{}, accepted = <SequenceRecord>[], rejected = <String>[];
  for (final raw in raws) {
    var reason = seen.add(raw.name) ? '' : 'duplicate name';
    final upper = raw.observation.toUpperCase(),
        observations = <int>[],
        path = <int>[];
    var missing = 0;
    if (reason.isEmpty) {
      for (var i = 0; i < upper.length; i++) {
        final letter = upper[i], index = model.symbols.indexOf(letter);
        if (index < 0 && letter != model.missing) {
          reason = 'invalid symbol $letter at position ${i + 1}';
          break;
        }
        observations.add(index);
        if (index < 0) {
          missing++;
        }
      }
    }
    if (reason.isEmpty && labeled) {
      for (var i = 0; i < raw.labels.length; i++) {
        final letter = raw.labels[i], index = model.states.indexOf(letter);
        if (index < 0) {
          reason = 'invalid label $letter at position ${i + 1}';
          break;
        }
        path.add(index);
      }
    }
    if (reason.isEmpty && labeled && upper.length != raw.labels.length) {
      reason = 'length mismatch ${upper.length} ${raw.labels.length}';
    }
    if (reason.isEmpty && upper.length < p.minLength) {
      reason = 'too short ${upper.length}';
    }
    if (reason.isEmpty && 100 * missing > p.maxMissing * upper.length) {
      reason = 'too many missing $missing';
    }
    if (reason.isNotEmpty) {
      rejected.add(
        'REJECT ${labeled ? 'labeled.txt' : 'sequences.txt'} line ${raw.line} ${raw.name} $reason',
      );
    } else {
      accepted.add(
        SequenceRecord(raw.name, raw.role, upper, observations, path, missing),
      );
    }
  }
  return (accepted, rejected);
}

Validated validateInputs(RawInputs raw, Params p) {
  final (unlabeled, rejected1) = validate(raw.sequences, false, raw.initial, p);
  final (labeled, rejected2) = validate(raw.labeled, true, raw.initial, p);
  return Validated(
    unlabeled,
    labeled.where((r) => r.role == 'TRAIN').toList(),
    labeled.where((r) => r.role == 'TEST').toList(),
    [...rejected1, ...rejected2],
    rejected1.length,
    rejected2.length,
  );
}

List<List<int>> observationLists(List<SequenceRecord> records) => [
  for (final record in records) record.observations,
];
List<TrainingPair> truePairs(List<SequenceRecord> records) => [
  for (final record in records) TrainingPair(record.observations, record.path),
];
int totalPositions(List<SequenceRecord> records) =>
    records.fold(0, (a, r) => a + r.observations.length);
int totalMissing(List<SequenceRecord> records) =>
    records.fold(0, (a, r) => a + r.missing);
String ratio(int a, int b) => b == 0 ? '-' : number(a / b);
List<Segment> segments(List<int> path, Params p) {
  final result = <Segment>[];
  for (final run in runs(path)) {
    if (run.state != p.target) {
      continue;
    }
    if (result.isNotEmpty && run.start - result.last.end - 1 <= p.mergeGap) {
      result[result.length - 1] = Segment(result.last.start, run.end);
    } else {
      result.add(Segment(run.start, run.end));
    }
  }
  return result.where((s) => s.end - s.start + 1 >= p.minSegment).toList();
}

List<Segment> trueRegions(List<int> path, int target) => [
  for (final run in runs(path))
    if (run.state == target) Segment(run.start, run.end),
];

class Composition {
  int observed = 0, rich = 0, pairs = 0, first = 0, second = 0;
  bool island = false;
}

Composition composition(List<int> observations, Segment segment, Params p) {
  final result = Composition();
  for (var t = segment.start; t <= segment.end; t++) {
    final symbol = observations[t];
    if (symbol >= 0) {
      result.observed++;
      if (p.rich.contains(symbol)) {
        result.rich++;
      }
      if (symbol == p.motif[0]) {
        result.first++;
      }
      if (symbol == p.motif[1]) {
        result.second++;
      }
    }
    if (t < segment.end &&
        symbol == p.motif[0] &&
        observations[t + 1] == p.motif[1]) {
      result.pairs++;
    }
  }
  final denominator = result.first * result.second;
  result.island =
      denominator > 0 &&
      100 * result.rich >= p.minRich * result.observed &&
      100 * result.pairs * result.observed >= p.minMotif * denominator;
  return result;
}

class BWTrace {
  final double loglik, heldout, change, maxChange;
  final bool violation;
  BWTrace(
    this.loglik,
    this.heldout, {
    this.change = 0,
    this.maxChange = 0,
    this.violation = false,
  });
}

class BWTraining {
  Model model;
  final trace = <BWTrace>[];
  int bestHeldout = 0, violations = 0;
  BWTraining(this.model);
}

double maxChange(Model a, Model b) {
  var maximum = 0.0;
  for (var i = 0; i < a.initial.length; i++) {
    maximum = max(maximum, (a.initial[i] - b.initial[i]).abs());
  }
  for (var i = 0; i < a.transition.length; i++) {
    for (var j = 0; j < a.transition[i].length; j++) {
      maximum = max(maximum, (a.transition[i][j] - b.transition[i][j]).abs());
    }
  }
  for (var i = 0; i < a.emission.length; i++) {
    for (var c = 0; c < a.emission[i].length; c++) {
      maximum = max(maximum, (a.emission[i][c] - b.emission[i][c]).abs());
    }
  }
  return maximum;
}

BWTraining trainBaumWelch(
  Model initial,
  List<List<int>> unlabeled,
  List<List<int>> heldout,
  Params p,
) {
  final result = BWTraining(initial);
  result.trace.add(
    BWTrace(totalLoglik(initial, unlabeled), totalLoglik(initial, heldout)),
  );
  for (var t = 1; t <= p.iterations; t++) {
    final next = baumWelchStep(result.model, unlabeled, p.pseudocount),
        loglik = totalLoglik(next, unlabeled),
        previous = result.trace[t - 1].loglik;
    final record = BWTrace(
      loglik,
      totalLoglik(next, heldout),
      change: loglik - previous,
      maxChange: maxChange(next, result.model),
      violation: loglik < previous - 0.000001 * previous.abs(),
    );
    if (record.violation) {
      result.violations++;
    }
    result.trace.add(record);
    if (record.heldout > result.trace[result.bestHeldout].heldout) {
      result.bestHeldout = t;
    }
    result.model = next;
  }
  return result;
}

List<String> bwTraceLines(BWTraining training) => [
  'iteration,loglik,heldout,change,max_change,status',
  for (var t = 0; t < training.trace.length; t++)
    t == 0
        ? '0,${number(training.trace[t].loglik)},${number(training.trace[t].heldout)},,,'
        : '$t,${number(training.trace[t].loglik)},${number(training.trace[t].heldout)},${number(training.trace[t].change)},${numberDigits(training.trace[t].maxChange, 6)},${training.trace[t].violation ? 'violation' : 'ok'}',
];

class ViterbiTrace {
  double logprob = 0, loglik = 0;
  int changed = 0;
}

class ViterbiTraining {
  Model model;
  final trace = <ViterbiTrace>[];
  bool converged = false;
  ViterbiTraining(this.model);
}

(List<List<int>>, ViterbiTrace) viterbiTrainingValues(
  Model model,
  List<List<int>> sequences,
) {
  final paths = <List<int>>[], record = ViterbiTrace();
  for (final observations in sequences) {
    final (path, logprob) = viterbi(model, observations);
    paths.add(path);
    record.logprob += logprob;
    record.loglik += scaledForward(model, observations).loglik;
  }
  return (paths, record);
}

ViterbiTraining trainViterbi(
  Model initial,
  List<List<int>> sequences,
  Params p,
) {
  var (paths, first) = viterbiTrainingValues(initial, sequences);
  final result = ViterbiTraining(initial)..trace.add(first);
  for (var t = 1; t <= p.iterations; t++) {
    final pairs = [
          for (var i = 0; i < sequences.length; i++)
            TrainingPair(sequences[i], paths[i]),
        ],
        model = estimateByCounting(
          initial,
          pairs,
          p.pseudocount,
          'VITERBI_TRAINING',
        );
    final (nextPaths, record) = viterbiTrainingValues(model, sequences);
    for (var i = 0; i < paths.length; i++) {
      record.changed += paths[i].length - correctCount(paths[i], nextPaths[i]);
    }
    result.trace.add(record);
    result.model = model;
    paths = nextPaths;
    if (record.changed == 0) {
      result.converged = true;
      break;
    }
  }
  return result;
}

List<String> viterbiTraceLines(ViterbiTraining training) => [
  'iteration,logprob,loglik,changed',
  for (var t = 0; t < training.trace.length; t++)
    '$t,${number(training.trace[t].logprob)},${number(training.trace[t].loglik)},${t == 0 ? '' : training.trace[t].changed}',
];

class FoldResult {
  final int records, positions;
  int correct = 0;
  FoldResult(this.records, this.positions);
}

class CVResult {
  final Candidate candidate;
  final folds = <FoldResult>[];
  int correct = 0;
  final List<List<int>> confusion;
  CVResult(this.candidate, int k) : confusion = intMatrix(k, k);
}

class SupervisedTraining {
  late Model model;
  final candidates = <CVResult>[], learning = <int>[];
  int selected = 0;
}

SupervisedTraining trainSupervised(
  Model initial,
  List<SequenceRecord> training,
  List<SequenceRecord> testing,
  Params p,
) {
  final result = SupervisedTraining();
  for (final candidate in p.smoothing) {
    final record = CVResult(candidate, initial.states.length);
    for (var f = 0; f < p.folds; f++) {
      final fitting = <SequenceRecord>[], validation = <SequenceRecord>[];
      for (var i = 0; i < training.length; i++) {
        (i % p.folds == f ? validation : fitting).add(training[i]);
      }
      final model = estimateByCounting(
            initial,
            truePairs(fitting),
            candidate.value,
            'SUPERVISED',
          ),
          fold = FoldResult(validation.length, totalPositions(validation));
      for (final item in validation) {
        final (path, _) = viterbi(model, item.observations);
        fold.correct += correctCount(item.path, path);
        addConfusion(record.confusion, item.path, path);
      }
      record.correct += fold.correct;
      record.folds.add(fold);
    }
    result.candidates.add(record);
    if (record.correct > result.candidates[result.selected].correct) {
      result.selected = result.candidates.length - 1;
    }
  }
  final chosen = result.candidates[result.selected].candidate.value;
  result.model = estimateByCounting(
    initial,
    truePairs(training),
    chosen,
    'SUPERVISED',
  );
  for (var r = 1; r <= training.length; r++) {
    final model = estimateByCounting(
      initial,
      truePairs(training.sublist(0, r)),
      chosen,
      'SUPERVISED',
    );
    var correct = 0;
    for (final record in testing) {
      final (path, _) = viterbi(model, record.observations);
      correct += correctCount(record.path, path);
    }
    result.learning.add(correct);
  }
  return result;
}

class ModelEvaluation {
  final blocks = <List<String>>[],
      correct = <int>[0, 0],
      decodings = <Decoding>[];
}

ModelEvaluation evaluateModel(
  Model model,
  List<SequenceRecord> testing,
  Params p,
) {
  final result = ModelEvaluation();
  for (final record in testing) {
    result.decodings.add(decode(model, record.observations));
  }
  for (var decoder = 0; decoder < 2; decoder++) {
    final name = decoder == 0 ? 'VITERBI' : 'POSTERIOR',
        table = intMatrix(model.states.length, model.states.length),
        calibration = List.filled(10, 0),
        calibrationCorrect = List.filled(10, 0),
        recordLines = <String>[];
    var predictedRegions = 0,
        trueRegionCount = 0,
        matchedPredictedRegions = 0,
        matchedTrueRegions = 0,
        predictedBoundaries = 0,
        trueBoundaryCount = 0,
        matchedPredictedBoundaries = 0,
        matchedTrueBoundaries = 0;
    for (var i = 0; i < testing.length; i++) {
      final record = testing[i],
          d = result.decodings[i],
          path = decoder == 0 ? d.viterbi : d.posterior,
          correct = correctCount(record.path, path);
      result.correct[decoder] += correct;
      addConfusion(table, record.path, path);
      final predicted = segments(path, p),
          truth = trueRegions(record.path, p.target);
      final (a, b) = regionMatches(predicted, truth);
      predictedRegions += predicted.length;
      trueRegionCount += truth.length;
      matchedPredictedRegions += a;
      matchedTrueRegions += b;
      final predictedB = boundaries(path), truthB = boundaries(record.path);
      final (ba, bb) = boundaryMatches(predictedB, truthB, p.boundaryTolerance);
      predictedBoundaries += predictedB.length;
      trueBoundaryCount += truthB.length;
      matchedPredictedBoundaries += ba;
      matchedTrueBoundaries += bb;
      if (decoder == 1) {
        for (var t = 0; t < d.confidence.length; t++) {
          final bin = min(9, (10 * d.confidence[t]).floor());
          calibration[bin]++;
          if (path[t] == record.path[t]) {
            calibrationCorrect[bin]++;
          }
        }
      }
      recordLines.add(
        'RECORD ${record.name} length ${record.path.length} correct $correct',
      );
    }
    final lines = <String>[
      'EVALUATION ${model.name} $name',
      ...confusionLines(table, model.states),
      ...metricsLines(table, model.states),
      'REGIONS ${model.states[p.target]} predicted $predictedRegions true $trueRegionCount precision ${fraction(matchedPredictedRegions, predictedRegions)} recall ${fraction(matchedTrueRegions, trueRegionCount)}',
      'BOUNDARIES predicted $predictedBoundaries true $trueBoundaryCount precision ${fraction(matchedPredictedBoundaries, predictedBoundaries)} recall ${fraction(matchedTrueBoundaries, trueBoundaryCount)}',
    ];
    if (decoder == 1) {
      for (var bin = 0; bin < 10; bin++) {
        final count = calibration[bin];
        if (count == 0) {
          continue;
        }
        final interval = bin == 9 ? '0.9-1.0' : '0.$bin-0.${bin + 1}';
        lines.add(
          'CALIBRATION $interval positions $count correct ${calibrationCorrect[bin]} accuracy ${fraction(calibrationCorrect[bin], count)}',
        );
      }
    }
    lines.addAll(recordLines);
    result.blocks.add(lines);
  }
  return result;
}

List<String> combineBlocks(List<List<String>> blocks) {
  final lines = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) {
      lines.add('');
    }
    lines.addAll(blocks[i]);
  }
  return lines;
}

List<String> evaluationFile(
  List<Model> models,
  List<ModelEvaluation> evaluations,
  SupervisedTraining supervised,
  List<SequenceRecord> training,
  List<SequenceRecord> testing,
  Params p,
) {
  final blocks = <List<String>>[
        for (final evaluation in evaluations) ...evaluation.blocks,
      ],
      positions = totalPositions(training),
      lines = <String>['CROSS_VALIDATION folds ${p.folds}'];
  for (final result in supervised.candidates) {
    lines.add(
      'SMOOTHING ${result.candidate.text} positions $positions correct ${result.correct} accuracy ${fraction(result.correct, positions)}',
    );
  }
  final selected = supervised.candidates[supervised.selected];
  lines.add('SELECTED ${selected.candidate.text}');
  for (var f = 0; f < selected.folds.length; f++) {
    final fold = selected.folds[f];
    lines.add(
      'FOLD ${f + 1} records ${fold.records} positions ${fold.positions} correct ${fold.correct} accuracy ${fraction(fold.correct, fold.positions)}',
    );
  }
  lines.addAll([
    ...confusionLines(selected.confusion, models.first.states),
    ...metricsLines(selected.confusion, models.first.states),
  ]);
  blocks.add(lines);
  blocks.add([
    'LEARNING_CURVE',
    for (var i = 0; i < supervised.learning.length; i++)
      'RECORDS ${i + 1} correct ${supervised.learning[i]} accuracy ${fraction(supervised.learning[i], totalPositions(testing))}',
  ]);
  return combineBlocks(blocks);
}

(List<String>, List<String>) annotationFiles(
  List<SequenceRecord> records,
  Model model,
  List<Decoding> decodings,
  Params p,
) {
  final decodingLines = <String>[],
      segmentLines = <String>[
        'sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island',
      ],
      rng = Minstd(p.posteriorSeed);
  for (var i = 0; i < records.length; i++) {
    final record = records[i], d = decodings[i], samplePaths = <List<int>>[];
    var totalSegments = 0;
    for (var sample = 0; sample < p.posteriorSamples; sample++) {
      final path = posteriorPath(model, d.fb.forward.values, rng);
      samplePaths.add(path);
      totalSegments += segments(path, p).length;
    }
    final differences =
            record.observations.length - correctCount(d.viterbi, d.posterior),
        confident = [for (final state in d.posterior) model.states[state]],
        imputed = record.upper.split('');
    var uncertain = 0;
    for (var t = 0; t < d.confidence.length; t++) {
      if (d.confidence[t] < p.confidence) {
        uncertain++;
        confident[t] = '.';
      }
      if (record.observations[t] < 0) {
        final weights = List.filled(model.symbols.length, 0.0);
        for (var c = 0; c < weights.length; c++) {
          for (var state = 0; state < model.states.length; state++) {
            weights[c] += d.fb.posterior[t][state] * model.emission[state][c];
          }
        }
        imputed[t] = model.symbols[maximumIndex(weights)].toLowerCase();
      }
    }
    decodingLines.addAll([
      'SEQUENCE ${record.name} length ${record.observations.length} loglik ${number(d.fb.forward.loglik)} viterbi ${number(d.viterbiLogprob)} differences $differences uncertain $uncertain expected_segments ${number(totalSegments / p.posteriorSamples)}',
      'VITERBI ${encode(d.viterbi, model.states)}',
      'POSTERIOR ${encode(d.posterior, model.states)}',
      'CONFIDENT ${confident.join()}',
      'IMPUTED ${imputed.join()}',
    ]);
    final paths = [d.viterbi, d.posterior];
    for (var decoder = 0; decoder < 2; decoder++) {
      final name = decoder == 0 ? 'viterbi' : 'posterior';
      for (final segment in segments(paths[decoder], p)) {
        final length = segment.end - segment.start + 1;
        var posterior = 0.0, support = 0;
        for (var t = segment.start; t <= segment.end; t++) {
          posterior += d.fb.posterior[t][p.target];
        }
        for (final sample in samplePaths) {
          var targetCount = 0;
          for (var t = segment.start; t <= segment.end; t++) {
            if (sample[t] == p.target) {
              targetCount++;
            }
          }
          if (2 * targetCount > length) {
            support++;
          }
        }
        final c = composition(record.observations, segment, p);
        segmentLines.add(
          '${record.name},$name,${segment.start + 1},${segment.end + 1},$length,${number(posterior / length)},$support,${ratio(c.rich, c.observed)},${ratio(c.pairs * c.observed, c.first * c.second)},${c.island ? 'yes' : 'no'}',
        );
      }
    }
  }
  return (decodingLines, segmentLines);
}

List<String> sampleFile(Model model, Params p) {
  final rng = Minstd(p.sampleSeed), lines = <String>[];
  var viterbiCorrect = 0, posteriorCorrect = 0;
  for (var sample = 1; sample <= p.sampleCount; sample++) {
    final (states, observations) = syntheticSequence(
      model,
      p.sampleLength,
      rng,
    );
    final d = decode(model, observations),
        vc = correctCount(states, d.viterbi),
        pc = correctCount(states, d.posterior);
    viterbiCorrect += vc;
    posteriorCorrect += pc;
    lines.addAll([
      'SAMPLE $sample loglik ${number(d.fb.forward.loglik)} viterbi ${number(d.viterbiLogprob)} viterbi_correct $vc posterior_correct $pc',
      'STATES ${encode(states, model.states)}',
      'SYMBOLS ${encode(observations, model.symbols)}',
      'VITERBI ${encode(d.viterbi, model.states)}',
      'POSTERIOR ${encode(d.posterior, model.states)}',
    ]);
  }
  final positions = p.sampleCount * p.sampleLength;
  lines.add(
    'TOTAL positions $positions viterbi_accuracy ${fraction(viterbiCorrect, positions)} posterior_accuracy ${fraction(posteriorCorrect, positions)}',
  );
  return lines;
}

List<double> stationary(Model model) {
  final k = model.states.length,
      a = matrix(model.states.length, model.states.length + 1);
  for (var j = 0; j < k - 1; j++) {
    for (var i = 0; i < k; i++) {
      a[j][i] = model.transition[i][j];
      if (i == j) {
        a[j][i] -= 1;
      }
    }
  }
  for (var i = 0; i < k; i++) {
    a[k - 1][i] = 1;
  }
  a[k - 1][k] = 1;
  for (var column = 0; column < k; column++) {
    var pivot = column;
    for (var row = column + 1; row < k; row++) {
      if (a[row][column].abs() > a[pivot][column].abs()) {
        pivot = row;
      }
    }
    final old = a[column];
    a[column] = a[pivot];
    a[pivot] = old;
    final divisor = a[column][column];
    for (var j = column; j <= k; j++) {
      a[column][j] /= divisor;
    }
    for (var row = 0; row < k; row++) {
      if (row == column) {
        continue;
      }
      final factor = a[row][column];
      for (var j = column; j <= k; j++) {
        a[row][j] -= factor * a[column][j];
      }
    }
  }
  return [for (var i = 0; i < k; i++) a[i][k]];
}

class PathStats {
  final List<int> positions, runs;
  int total = 0;
  PathStats(int k) : positions = List.filled(k, 0), runs = List.filled(k, 0);
}

PathStats pathStatistics(List<List<int>> paths, int k) {
  final result = PathStats(k);
  for (final path in paths) {
    result.total += path.length;
    for (final state in path) {
      result.positions[state]++;
    }
    for (final run in runs(path)) {
      result.runs[run.state]++;
    }
  }
  return result;
}

List<List<int>> truePaths(List<SequenceRecord> records) => [
  for (final record in records) record.path,
];
List<String> truthLines(
  List<SequenceRecord> records,
  String role,
  List<String> states,
) {
  final stats = pathStatistics(truePaths(records), states.length);
  return [
    for (var i = 0; i < states.length; i++)
      'TRUTH $role ${states[i]} occupancy ${ratio(stats.positions[i], stats.total)} mean_run ${ratio(stats.positions[i], stats.runs[i])}',
  ];
}

(List<int>, int) alignment(Model model, List<SequenceRecord> training) {
  final k = model.states.length,
      table = intMatrix(model.states.length, model.states.length),
      used = List.filled(model.states.length, false);
  var best = <int>[], maximum = -1;
  for (final record in training) {
    final (path, _) = viterbi(model, record.observations);
    addConfusion(table, record.path, path);
  }
  void visit(List<int> permutation) {
    if (permutation.length == k) {
      var agreement = 0;
      for (var j = 0; j < k; j++) {
        agreement += table[permutation[j]][j];
      }
      if (agreement > maximum) {
        maximum = agreement;
        best = List<int>.of(permutation);
      }
      return;
    }
    for (var state = 0; state < k; state++) {
      if (!used[state]) {
        used[state] = true;
        visit([...permutation, state]);
        used[state] = false;
      }
    }
  }

  visit([]);
  return (best, maximum);
}

List<String> modelReport(
  Model model,
  List<SequenceRecord> unlabeled,
  List<SequenceRecord> training,
  List<SequenceRecord> testing,
  List<Decoding> decodings,
  Params p,
) {
  final paths = <List<int>>[];
  var loglik = 0.0, segmentCount = 0, totalSegmentLength = 0, islands = 0;
  for (var i = 0; i < unlabeled.length; i++) {
    final record = unlabeled[i], d = decodings[i];
    loglik += d.fb.forward.loglik;
    paths.add(d.viterbi);
    for (final segment in segments(d.viterbi, p)) {
      segmentCount++;
      totalSegmentLength += segment.end - segment.start + 1;
      if (composition(record.observations, segment, p).island) {
        islands++;
      }
    }
  }
  final phi = stationary(model),
      stats = pathStatistics(paths, model.states.length);
  final (permutation, agreement) = alignment(model, training);
  final mapping = [
        for (var j = 0; j < model.states.length; j++)
          '${model.states[j]}=${model.states[permutation[j]]}',
      ],
      observed = totalPositions(unlabeled) - totalMissing(unlabeled);
  return [
    'MODEL ${model.name}',
    'LOGLIK unlabeled ${number(loglik)} per_symbol ${number(loglik / observed)} test ${number(totalLoglik(model, observationLists(testing)))}',
    'SEGMENTS count $segmentCount mean_length ${ratio(totalSegmentLength, segmentCount)} islands $islands',
    'ALIGNMENT ${mapping.join(' ')} agreement ${fraction(agreement, totalPositions(training))}',
    for (var i = 0; i < model.states.length; i++)
      'STATE ${model.states[i]} stationary ${number(phi[i])} duration ${number(1 / (1 - model.transition[i][i]))} occupancy ${ratio(stats.positions[i], stats.total)} mean_run ${ratio(stats.positions[i], stats.runs[i])}',
  ];
}

List<String> reportFile(
  Model initial,
  Validated input,
  List<Model> models,
  List<List<Decoding>> allDecodings,
  List<ModelEvaluation> evaluations,
  BWTraining bw,
  ViterbiTraining vt,
  SupervisedTraining supervised,
  Params p,
) {
  final unlabeled = input.unlabeled,
      training = input.train,
      testing = input.test,
      symbolCounts = List.filled(initial.symbols.length, 0);
  var observed = 0;
  final lines = <String>[
    'INPUT',
    'SEQUENCES accepted ${unlabeled.length} rejected ${input.unlabeledRejected} positions ${totalPositions(unlabeled)} missing ${totalMissing(unlabeled)}',
    'LABELED train ${training.length} test ${testing.length} rejected ${input.labeledRejected} positions ${totalPositions(training) + totalPositions(testing)} missing ${totalMissing(training) + totalMissing(testing)}',
    ...input.rejections,
  ];
  for (final record in unlabeled) {
    for (final symbol in record.observations) {
      if (symbol >= 0) {
        symbolCounts[symbol]++;
        observed++;
      }
    }
  }
  var compositionLine = 'COMPOSITION';
  for (var c = 0; c < initial.symbols.length; c++) {
    compositionLine +=
        ' ${initial.symbols[c]} ${ratio(symbolCounts[c], observed)}';
  }
  lines.addAll([
    compositionLine,
    ...truthLines(training, 'TRAIN', initial.states),
    ...truthLines(testing, 'TEST', initial.states),
  ]);
  final blocks = <List<String>>[lines];
  final trainingLines = <String>[
        'TRAINING BAUM_WELCH iterations ${p.iterations} initial_loglik ${number(bw.trace.first.loglik)} final_loglik ${number(bw.trace.last.loglik)} violations ${bw.violations} best_heldout_iteration ${bw.bestHeldout}',
        'TRAINING VITERBI_TRAINING iterations ${vt.trace.length - 1} converged ${vt.converged ? 'yes' : 'no'}',
        'TRAINING SUPERVISED smoothing ${supervised.candidates[supervised.selected].candidate.text}',
      ],
      preference = List.filled(models.length, 0);
  for (var i = 0; i < unlabeled.length; i++) {
    var best = 0;
    for (var m = 1; m < models.length; m++) {
      if (allDecodings[m][i].fb.forward.loglik >
          allDecodings[best][i].fb.forward.loglik) {
        best = m;
      }
    }
    preference[best]++;
  }
  var preferenceLine = 'PREFERENCE';
  for (var m = 0; m < models.length; m++) {
    preferenceLine += ' ${models[m].name} ${preference[m]}';
  }
  trainingLines.add(preferenceLine);
  for (var a = 0; a < models.length; a++) {
    for (var b = a + 1; b < models.length; b++) {
      var correct = 0;
      for (var i = 0; i < unlabeled.length; i++) {
        correct += correctCount(
          allDecodings[a][i].viterbi,
          allDecodings[b][i].viterbi,
        );
      }
      trainingLines.add(
        'AGREEMENT ${models[a].name} ${models[b].name} ${fraction(correct, totalPositions(unlabeled))}',
      );
    }
  }
  for (var decoder = 0; decoder < 2; decoder++) {
    var best = 0;
    for (var m = 1; m < models.length; m++) {
      if (evaluations[m].correct[decoder] >
          evaluations[best].correct[decoder]) {
        best = m;
      }
    }
    trainingLines.add(
      'BEST ${decoder == 0 ? 'VITERBI' : 'POSTERIOR'} ${models[best].name} accuracy ${fraction(evaluations[best].correct[decoder], totalPositions(testing))}',
    );
  }
  blocks.add(trainingLines);
  for (var m = 0; m < models.length; m++) {
    blocks.add(
      modelReport(models[m], unlabeled, training, testing, allDecodings[m], p),
    );
  }
  return combineBlocks(blocks);
}

void main() {
  final raw = readInputs(),
      p = Params(raw.params, raw.initial),
      input = validateInputs(raw, p),
      unlabeled = observationLists(input.unlabeled),
      heldout = [
        ...observationLists(input.train),
        ...observationLists(input.test),
      ],
      bw = trainBaumWelch(raw.initial, unlabeled, heldout, p),
      vt = trainViterbi(raw.initial, unlabeled, p),
      supervised = trainSupervised(raw.initial, input.train, input.test, p),
      models = <Model>[raw.initial, bw.model, vt.model, supervised.model],
      evaluations = <ModelEvaluation>[],
      allDecodings = <List<Decoding>>[];
  for (final model in models) {
    evaluations.add(evaluateModel(model, input.test, p));
    allDecodings.add([
      for (final record in input.unlabeled) decode(model, record.observations),
    ]);
  }
  final blocks = [for (final model in models.skip(1)) modelLines(model)];
  final (decodingLines, segmentLines) = annotationFiles(
    input.unlabeled,
    bw.model,
    allDecodings[1],
    p,
  );
  writeLines('trained_model.txt', combineBlocks(blocks));
  writeLines('loglik_trace.csv', bwTraceLines(bw));
  writeLines('viterbi_trace.csv', viterbiTraceLines(vt));
  writeLines('decodings.txt', decodingLines);
  writeLines('segments.csv', segmentLines);
  writeLines('samples.txt', sampleFile(bw.model, p));
  writeLines(
    'evaluation.txt',
    evaluationFile(models, evaluations, supervised, input.train, input.test, p),
  );
  writeLines(
    'report.txt',
    reportFile(
      raw.initial,
      input,
      models,
      allDecodings,
      evaluations,
      bw,
      vt,
      supervised,
      p,
    ),
  );
}
