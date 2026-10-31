import 'dart:io';
import 'dart:math' as math;
import 'tokenizer.dart';
import 'vocabulary.dart';
import 'naive_bayes.dart';
import 'rocchio.dart';
import 'evaluation.dart';

const modelNames = ['multinomial', 'bernoulli', 'complement', 'rocchio', 'vote'];
const modelPairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
List<String> readLines(String name) => File('input/$name').readAsLinesSync();
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
List<String> joinParts(List<List<String>> parts) {
  final lines = <String>[];
  for (final part in parts) {
    if (lines.isNotEmpty) lines.add('');
    lines.addAll(part);
  }
  return lines;
}
int hundredths(String text) {
  final parts = text.split('.');
  return int.parse(parts[0]) * 100 + int.parse(parts[1]);
}
String hundredthsText(int value) => '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
String classCountsText(List<String> names, List<int> counts) =>
    [for (var i = 0; i < names.length; i++) '${names[i]} ${counts[i]}'].join(' ');
int bucketOf(double value, List<double> boundaries) =>
    boundaries.where((boundary) => value >= boundary).length;
List<double> realBoundaries(List<int> values, double scale) =>
    values.map((value) => value / scale).toList();
int rounded4(double value) => (value * 10000).round();
String evaluationFields(Evaluation value) =>
    '${value.correct},${realText(value.micro)},${realText(value.macro)}';

class RatioEntry {
  final int p;
  final int q;
  final int term;
  RatioEntry(this.p, this.q, this.term);
}
void rankRatios(List<RatioEntry> entries) => entries.sort((a, b) {
  final compared = (b.p * a.q).compareTo(a.p * b.q);
  return compared != 0 ? compared : a.term.compareTo(b.term);
});

class Settings {
  late List<int> alphas;
  late int minDF;
  late int features;
  late bool bigrams;
  late int top;
  late List<int> curve;
  late List<int> sizes;
  late List<int> thresholds;
  late List<int> lengths;
  late int iterations;
  late int weight;
  late int resamples;
  late int seed;
  Settings(List<String> lines) {
    final values = <String, List<String>>{};
    for (final line in lines) {
      final fields = line.split(' ');
      values[fields[0]] = fields.sublist(1);
    }
    int value(String key) => int.parse(values[key]![0]);
    List<int> integers(String key) => values[key]!.map(int.parse).toList();
    alphas = values['ALPHAS']!.map(hundredths).toList();
    minDF = value('MIN_DF');
    features = value('FEATURES');
    bigrams = values['BIGRAMS']![0] == 'yes';
    top = value('TOP');
    curve = integers('CURVE');
    sizes = integers('SIZES');
    thresholds = values['THRESHOLDS']!.map(hundredths).toList();
    lengths = integers('LENGTHS');
    iterations = value('EM_ITERATIONS');
    weight = hundredths(values['EM_WEIGHT']![0]);
    resamples = value('BOOTSTRAP');
    seed = int.parse(values['BOOTSTRAP']![1]);
  }
}

class Document {
  final String name;
  final int label;
  final Tokens tokens;
  Document(this.name, this.label, this.tokens);
}
class FoldSummary {
  final int train;
  final int validate;
  final int candidates;
  final int vocabulary;
  FoldSummary(this.train, this.validate, this.candidates, this.vocabulary);
}
class CVRun {
  final List<int> predictions;
  final Evaluation evaluation;
  final List<int> foldCorrect;
  CVRun(this.predictions, this.evaluation, this.foldCorrect);
}

class Training {
  final bool bigrams;
  late Vocabulary vocabulary;
  late TrainingCounts counts;
  late Rocchio rocchio;
  List<NaiveBayes> models = [];
  Training(List<Document> documents, this.bigrams, int classCount, int minDF, int size) {
    final sequences = documents.map((document) => document.tokens.terms(bigrams)).toList();
    final labels = documents.map((document) => document.label).toList();
    vocabulary = Vocabulary(sequences, labels, classCount, minDF, size);
    final encoded = sequences.map(vocabulary.encode).toList();
    counts = TrainingCounts(encoded, labels, classCount, vocabulary.terms.length);
    rocchio = Rocchio(encoded, labels, classCount, vocabulary.frequencies);
  }
  void train(List<int> alphas) {
    models = [for (var kind = 0; kind < 3; kind++) trainModel(kind, counts, alphas[kind])];
  }
  List<int> encode(Document document) => vocabulary.encode(document.tokens.terms(bigrams));
  Prediction classify(int model, List<int> sequence) =>
      model == 3 ? rocchio.predict(sequence) : models[model].predict(sequence);
}

class Experiment {
  final Settings settings;
  late List<String> classes;
  final training = <Document>[];
  final tests = <Document>[];
  final unlabelled = <Document>[];
  final labelled = <int>[];
  final truths = <int>[];
  final folds = <FoldSummary>[];
  late List<List<CVRun>> cvRuns;
  late List<int> selected;
  late List<CVRun> selectedRuns;
  late Training finalTraining;
  late List<List<int>> testSequences;
  late List<List<Prediction>> predictions;
  late List<List<bool>> correct;
  Experiment() : settings = Settings(readLines('params.txt')) {
    final stopwords = readLines('stopwords.txt').toSet();
    final rows = readLines('train.txt').map((line) => line.split('\t')).toList();
    classes = rows.map((row) => row[0]).toSet().toList()..sort();
    final positions = {for (var i = 0; i < classes.length; i++) classes[i]: i};
    for (var i = 0; i < rows.length; i++) {
      training.add(Document('${i + 1}', positions[rows[i][0]]!, Tokens(rows[i][1], stopwords)));
    }
    for (final line in readLines('test.txt')) {
      final fields = line.split('\t');
      tests.add(Document(fields[0], fields[1] == '?' ? -1 : positions[fields[1]]!, Tokens(fields[2], stopwords)));
    }
    final texts = readLines('unlabelled.txt');
    for (var i = 0; i < texts.length; i++) {
      unlabelled.add(Document('${i + 1}', -1, Tokens(texts[i], stopwords)));
    }
    for (var i = 0; i < tests.length; i++) {
      if (tests[i].label >= 0) {
        labelled.add(i);
        truths.add(tests[i].label);
      }
    }
  }

  Training trained(List<Document> documents, bool bigrams, int size) =>
      Training(documents, bigrams, classes.length, settings.minDF, size)..train(selected);
  String alphaText(int model) => model < 3 ? hundredthsText(selected[model]) : '-';
  CVRun cvRun(List<int> predicted) {
    final truths = training.map((document) => document.label).toList();
    final foldCorrect = List.filled(5, 0);
    for (var i = 0; i < predicted.length; i++) {
      if (predicted[i] == truths[i]) foldCorrect[i % 5]++;
    }
    return CVRun(predicted, Evaluation(classes.length, truths, predicted), foldCorrect);
  }
  void crossValidate() {
    final count = training.length;
    final allPredictions = [
      for (var model = 0; model < 4; model++)
        List.generate(model == 3 ? 1 : settings.alphas.length, (_) => List.filled(count, 0))
    ];
    for (var fold = 0; fold < 5; fold++) {
      final members = [for (var i = 0; i < count; i++) if (i % 5 != fold) training[i]];
      final heldOut = [for (var i = 0; i < count; i++) if (i % 5 == fold) i];
      final fitted = Training(members, settings.bigrams, classes.length, settings.minDF, settings.features);
      folds.add(FoldSummary(members.length, heldOut.length, fitted.vocabulary.candidateCount, fitted.vocabulary.terms.length));
      final sequences = [for (final index in heldOut) fitted.encode(training[index])];
      for (var kind = 0; kind < 3; kind++) {
        for (var position = 0; position < settings.alphas.length; position++) {
          final model = trainModel(kind, fitted.counts, settings.alphas[position]);
          for (var i = 0; i < heldOut.length; i++) {
            allPredictions[kind][position][heldOut[i]] = model.predict(sequences[i]).label;
          }
        }
      }
      for (var i = 0; i < heldOut.length; i++) {
        allPredictions[3][0][heldOut[i]] = fitted.rocchio.predict(sequences[i]).label;
      }
    }
    cvRuns = [for (final runs in allPredictions) runs.map(cvRun).toList()];
  }
  void selectAlphas() {
    selected = [];
    selectedRuns = [];
    for (var kind = 0; kind < 3; kind++) {
      var best = 0;
      for (var position = 1; position < settings.alphas.length; position++) {
        if (rounded4(cvRuns[kind][position].evaluation.macro) > rounded4(cvRuns[kind][best].evaluation.macro)) best = position;
      }
      selected.add(settings.alphas[best]);
      selectedRuns.add(cvRuns[kind][best]);
    }
    selectedRuns.add(cvRuns[3][0]);
  }
  void trainFinal() {
    finalTraining = trained(training, settings.bigrams, settings.features);
    testSequences = tests.map(finalTraining.encode).toList();
    predictions = [for (var model = 0; model < 4; model++)
      [for (final sequence in testSequences) finalTraining.classify(model, sequence)]];
    final vote = <Prediction>[];
    for (var index = 0; index < tests.length; index++) {
      final labels = [for (var model = 0; model < 4; model++) predictions[model][index].label];
      final votes = List.filled(classes.length, 0);
      for (final label in labels) {
        votes[label]++;
      }
      var winner = labels[0];
      for (final label in labels) {
        if (votes[label] > votes[winner]) winner = label;
      }
      vote.add(Prediction(winner, votes[winner] / 4));
    }
    predictions.add(vote);
    correct = [for (var model = 0; model < 5; model++)
      [for (final index in labelled) predictions[model][index].label == tests[index].label]];
  }
  List<Evaluation> testEvaluations(Training fitted) {
    final sequences = [for (final index in labelled) fitted.encode(tests[index])];
    return [for (var model = 0; model < 4; model++) Evaluation(classes.length, truths,
      [for (final sequence in sequences) fitted.classify(model, sequence).label])];
  }

  List<String> vocabularyLines() {
    final vocabulary = finalTraining.vocabulary;
    return [
      'documents ${training.length} terms ${vocabulary.termCount} candidates ${vocabulary.candidateCount} vocabulary ${vocabulary.terms.length}',
      for (var i = 0; i < vocabulary.ranking.length; i++) vocabularyLine(i + 1, vocabulary.ranking[i]),
    ];
  }
  String vocabularyLine(int rank, RankedTerm entry) =>
      '$rank ${entry.term} ${entry.frequency} ${realText(entry.score)} ${classes[entry.bestClass]}';
  List<String> cvLines() => [
    'model,alpha,correct,accuracy,macro_f1,selected',
    for (var kind = 0; kind < 3; kind++)
      for (var i = 0; i < settings.alphas.length; i++)
        '${modelNames[kind]},${hundredthsText(settings.alphas[i])},${evaluationFields(cvRuns[kind][i].evaluation)},${settings.alphas[i] == selected[kind] ? 'yes' : 'no'}',
    'rocchio,-,${evaluationFields(cvRuns[3][0].evaluation)},yes',
  ];
  List<String> predictionLines() => [
    'id,model,label,score',
    for (var index = 0; index < tests.length; index++)
      for (var model = 0; model < 5; model++)
        '${tests[index].name},${modelNames[model]},${classes[predictions[model][index].label]},${realText(predictions[model][index].score)}',
  ];
  List<String> curveLines() {
    final lines = ['size,vocabulary,model,correct,accuracy,macro_f1'];
    for (final size in settings.curve) {
      final fitted = trained(training.sublist(0, size), settings.bigrams, settings.features);
      final evaluations = testEvaluations(fitted);
      for (var model = 0; model < 4; model++) {
        lines.add('$size,${fitted.vocabulary.terms.length},${modelNames[model]},${evaluationFields(evaluations[model])}');
      }
    }
    return lines;
  }
  List<String> featureLines() {
    final lines = ['terms,features,vocabulary,model,correct,accuracy,macro_f1'];
    for (final bigrams in [false, true]) {
      final kind = bigrams ? 'bigrams' : 'unigrams';
      for (final size in settings.sizes) {
        final fitted = trained(training, bigrams, size);
        final evaluations = testEvaluations(fitted);
        for (var model = 0; model < 4; model++) {
          lines.add('$kind,$size,${fitted.vocabulary.terms.length},${modelNames[model]},${evaluationFields(evaluations[model])}');
        }
      }
    }
    return lines;
  }

  List<String> dataPart() {
    final vocabulary = finalTraining.vocabulary;
    final lines = ['documents train ${training.length} test ${tests.length} labelled ${labelled.length} unlabelled ${unlabelled.length} classes ${classes.length}'];
    final trainCounts = List.filled(classes.length, 0);
    final testCounts = List.filled(classes.length, 0);
    for (final document in training) {
      trainCounts[document.label]++;
    }
    for (final truth in truths) {
      testCounts[truth]++;
    }
    for (var label = 0; label < classes.length; label++) {
      lines.add('class ${classes[label]} train ${trainCounts[label]} test ${testCounts[label]}');
    }
    var raw = 0;
    var stopwords = 0;
    var short = 0;
    var kept = 0;
    var bigrams = 0;
    final terms = <String>{};
    for (final document in training) {
      final tokens = document.tokens;
      raw += tokens.raw;
      stopwords += tokens.stopwords;
      short += tokens.short;
      kept += tokens.words.length;
      if (settings.bigrams) bigrams += tokens.bigrams.length;
      terms.addAll(tokens.terms(settings.bigrams));
    }
    final distinctBigrams = terms.where(isBigram).length;
    lines.add('train_tokens raw $raw stopwords $stopwords short $short unigrams $kept bigrams $bigrams');
    lines.add('train_terms unigrams ${terms.length - distinctBigrams} bigrams $distinctBigrams candidates ${vocabulary.candidateCount} vocabulary ${vocabulary.terms.length}');
    var total = 0;
    var inVocabulary = 0;
    final occurrences = <String, int>{};
    for (var index = 0; index < tests.length; index++) {
      total += tests[index].tokens.terms(settings.bigrams).length;
      inVocabulary += testSequences[index].length;
      for (final word in tests[index].tokens.words) {
        if (!vocabulary.index.containsKey(word)) occurrences[word] = (occurrences[word] ?? 0) + 1;
      }
    }
    lines.add('test_terms total $total in_vocabulary $inVocabulary');
    final ranked = occurrences.keys.toList()..sort((a, b) {
      final compared = occurrences[b]!.compareTo(occurrences[a]!);
      return compared != 0 ? compared : a.compareTo(b);
    });
    lines.add(['test_oov', for (final word in ranked.take(settings.top)) '$word ${occurrences[word]}'].join(' '));
    return lines;
  }
  List<String> foldsPart() => [
    'folds 5',
    for (var fold = 0; fold < folds.length; fold++)
      'fold ${fold + 1} train ${folds[fold].train} validate ${folds[fold].validate} candidates ${folds[fold].candidates} vocabulary ${folds[fold].vocabulary}',
  ];
  List<String> selectionPart() => [
    'selection',
    for (var model = 0; model < 4; model++)
      '${modelNames[model]} alpha ${alphaText(model)} correct ${proportionText(selectedRuns[model].evaluation.correct, training.length)} macro_f1 ${realText(selectedRuns[model].evaluation.macro)} folds ${selectedRuns[model].foldCorrect.join(' ')}',
  ];
  List<String> crossValidationPart(int model) => [
    'cross_validation ${modelNames[model]} alpha ${alphaText(model)}',
    ...selectedRuns[model].evaluation.lines(classes),
  ];
  List<String> testPart(int model) {
    final values = [for (final index in labelled) predictions[model][index]];
    final evaluation = Evaluation(classes.length, truths, values.map((prediction) => prediction.label).toList());
    final lines = ['test ${modelNames[model]} alpha ${alphaText(model)}',
      'labelled ${labelled.length} correct ${proportionText(evaluation.correct, labelled.length)}'];
    if (model < 4) {
      var topTwo = 0;
      for (var i = 0; i < values.length; i++) {
        if (values[i].ranking.take(2).contains(truths[i])) topTwo++;
      }
      lines.add('top2 ${proportionText(topTwo, labelled.length)}');
    }
    return [...lines, ...evaluation.lines(classes)];
  }

  List<String> probabilityPart(int model) {
    final thresholds = settings.thresholds;
    final limits = realBoundaries(thresholds, 100);
    final binRows = List.filled(limits.length + 1, 0);
    final binCorrect = List.filled(limits.length + 1, 0);
    final binSums = List.filled(limits.length + 1, 0.0);
    final accepted = List.filled(limits.length, 0);
    final acceptedCorrect = List.filled(limits.length, 0);
    var loss = 0.0;
    var brier = 0.0;
    for (var position = 0; position < labelled.length; position++) {
      final prediction = predictions[model][labelled[position]];
      final truth = truths[position];
      final hit = correct[model][position];
      final gap = prediction.scores[truth] - prediction.scores[prediction.label];
      loss += math.log(prediction.normalizer) - gap;
      var squares = 0.0;
      for (var label = 0; label < classes.length; label++) {
        final difference = prediction.probabilities[label] - (label == truth ? 1.0 : 0.0);
        squares += difference * difference;
      }
      brier += squares;
      final bucket = bucketOf(prediction.score, limits);
      binRows[bucket]++;
      binSums[bucket] += prediction.score;
      if (hit) binCorrect[bucket]++;
      for (var threshold = 0; threshold < limits.length; threshold++) {
        if (prediction.score >= limits[threshold]) {
          accepted[threshold]++;
          if (hit) acceptedCorrect[threshold]++;
        }
      }
    }
    final lines = ['probability ${modelNames[model]} alpha ${alphaText(model)}',
      'log_loss ${realText(loss / labelled.length)} brier ${realText(brier / labelled.length)}'];
    final bounds = [0, ...thresholds];
    for (var bucket = 0; bucket < bounds.length; bucket++) {
      final rows = binRows[bucket];
      var line = 'bin ${hundredthsText(bounds[bucket])} rows $rows';
      if (rows > 0) line += ' correct ${proportionText(binCorrect[bucket], rows)} mean ${realText(binSums[bucket] / rows)}';
      lines.add(line);
    }
    for (var i = 0; i < thresholds.length; i++) {
      final precise = accepted[i] > 0 ? proportionText(acceptedCorrect[i], accepted[i]) : '-';
      lines.add('threshold ${hundredthsText(thresholds[i])} covered ${proportionText(accepted[i], labelled.length)} correct $precise');
    }
    return lines;
  }
  List<String> lengthsPart() {
    final boundaries = realBoundaries(settings.lengths, 1);
    final rows = List.filled(boundaries.length + 1, 0);
    final hits = List.generate(5, (_) => List.filled(rows.length, 0));
    for (var position = 0; position < labelled.length; position++) {
      final bucket = bucketOf(testSequences[labelled[position]].length.toDouble(), boundaries);
      rows[bucket]++;
      for (var model = 0; model < 5; model++) {
        if (correct[model][position]) hits[model][bucket]++;
      }
    }
    final lines = ['lengths'];
    final bounds = [0, ...settings.lengths];
    for (var bucket = 0; bucket < rows.length; bucket++) {
      var line = 'length ${bounds[bucket]} rows ${rows[bucket]}';
      if (rows[bucket] > 0) {
        for (var model = 0; model < 5; model++) {
          line += ' ${modelNames[model]} ${proportionText(hits[model][bucket], rows[bucket])}';
        }
      }
      lines.add(line);
    }
    return lines;
  }
  List<String> comparisonPart() {
    final lines = ['comparison'];
    for (final (first, second) in modelPairs) {
      var agree = 0;
      var b = 0;
      var c = 0;
      for (var i = 0; i < tests.length; i++) {
        if (predictions[first][i].label == predictions[second][i].label) agree++;
      }
      for (var i = 0; i < labelled.length; i++) {
        if (correct[first][i] && !correct[second][i]) b++;
        if (correct[second][i] && !correct[first][i]) c++;
      }
      var statistic = fractionText(0, 1);
      if (b + c > 0) {
        var difference = (b - c).abs() - 1;
        if (difference < 0) difference = 0;
        statistic = fractionText(difference * difference, b + c);
      }
      lines.add('${modelNames[first]} ${modelNames[second]} agree ${proportionText(agree, tests.length)} b $b c $c statistic $statistic');
    }
    final errors = List.filled(5, 0);
    for (var i = 0; i < labelled.length; i++) {
      var wrong = 0;
      for (var model = 0; model < 4; model++) {
        if (!correct[model][i]) wrong++;
      }
      errors[wrong]++;
    }
    lines.add('errors ${[for (var wrong = 0; wrong < 5; wrong++) '$wrong ${errors[wrong]}'].join(' ')}');
    return lines;
  }
  List<String> bootstrapPart() {
    final count = labelled.length;
    var state = settings.seed;
    final totals = List.generate(5, (_) => <int>[]);
    for (var repetition = 0; repetition < settings.resamples; repetition++) {
      final hits = List.filled(5, 0);
      for (var draw = 0; draw < count; draw++) {
        state = (48271 * state) % 2147483647;
        final position = state % count;
        for (var model = 0; model < 5; model++) {
          if (correct[model][position]) hits[model]++;
        }
      }
      for (var model = 0; model < 5; model++) {
        totals[model].add(hits[model]);
      }
    }
    final rank = settings.resamples ~/ 40;
    final lines = ['bootstrap resamples ${settings.resamples} seed ${settings.seed}'];
    for (var model = 0; model < 5; model++) {
      final ordered = List.of(totals[model])..sort();
      final sum = ordered.fold<int>(0, (sum, value) => sum + value);
      lines.add('${modelNames[model]} mean ${realText(sum / (settings.resamples * count))} low ${proportionText(ordered[rank], count)} high ${proportionText(ordered[ordered.length - 1 - rank], count)}');
    }
    for (final (first, second) in modelPairs) {
      var wins = 0;
      var ties = 0;
      var losses = 0;
      for (var i = 0; i < settings.resamples; i++) {
        if (totals[first][i] > totals[second][i]) {
          wins++;
        } else if (totals[first][i] == totals[second][i]) {
          ties++;
        } else {
          losses++;
        }
      }
      lines.add('pair ${modelNames[first]} ${modelNames[second]} wins $wins ties $ties losses $losses');
    }
    return lines;
  }
  List<String> hardPart() {
    final hard = <int>[];
    final counts = List.filled(classes.length, 0);
    for (var i = 0; i < training.length; i++) {
      if (selectedRuns.every((run) => run.predictions[i] != training[i].label)) {
        hard.add(i);
        counts[training[i].label]++;
      }
    }
    return [
      'hard_documents ${hard.length} ${classCountsText(classes, counts)}',
      for (final index in hard.take(settings.top))
        '${training[index].name} true ${classes[training[index].label]} predicted ${selectedRuns.map((run) => classes[run.predictions[index]]).join(' ')}',
    ];
  }
  List<String> uncertainPart() {
    final order = List.generate(tests.length, (i) => i)..sort((a, b) {
      final compared = rounded4(predictions[0][a].margin).compareTo(rounded4(predictions[0][b].margin));
      return compared != 0 ? compared : a.compareTo(b);
    });
    final shown = order.take(settings.top).toList();
    final lines = ['uncertain multinomial ${shown.length}'];
    for (final index in shown) {
      final document = tests[index];
      final prediction = predictions[0][index];
      final truth = document.label < 0 ? '?' : classes[document.label];
      lines.add('${document.name} predicted ${classes[prediction.label]} runner_up ${classes[prediction.runnerUp]} margin ${realText(prediction.margin)} posterior ${realText(prediction.score)} true $truth');
    }
    return lines;
  }
  List<String> evidenceLines(List<int> sequence, int predicted, int truth) {
    final alpha = selected[0];
    final counts = finalTraining.counts.occurrences;
    final weights = finalTraining.models[0].weights;
    final entries = [for (final term in firstOccurrences(sequence))
      RatioEntry(100 * counts[predicted][term] + alpha, 100 * counts[truth][term] + alpha, term)];
    rankRatios(entries);
    return [for (final entry in entries.take(3))
      '  ${finalTraining.vocabulary.terms[entry.term]} count ${sequence.where((term) => term == entry.term).length} evidence ${realText(weights[predicted][entry.term] - weights[truth][entry.term])}'];
  }
  List<String> misclassifiedPart() {
    final wrong = labelled.where((index) => predictions[0][index].label != tests[index].label).toList();
    final lines = ['misclassified multinomial ${wrong.length}'];
    for (final index in wrong) {
      final document = tests[index];
      final prediction = predictions[0][index];
      lines.add('${document.name} true ${classes[document.label]} predicted ${classes[prediction.label]} posterior ${realText(prediction.score)}');
      lines.addAll(evidenceLines(testSequences[index], prediction.label, document.label));
    }
    return lines;
  }
  NaiveBayes maximization(List<Prediction> posteriors, List<List<int>> sequences) {
    final counts = finalTraining.counts;
    final occurrences = [for (final row in counts.occurrences) row.map((count) => count.toDouble()).toList()];
    final documents = counts.documents.map((count) => count.toDouble()).toList();
    final weight = settings.weight / 100;
    for (var i = 0; i < sequences.length; i++) {
      final frequencies = <int, int>{};
      for (final term in sequences[i]) {
        frequencies[term] = (frequencies[term] ?? 0) + 1;
      }
      final terms = firstOccurrences(sequences[i]);
      for (var label = 0; label < classes.length; label++) {
        final share = weight * posteriors[i].probabilities[label];
        documents[label] += share;
        for (final term in terms) {
          occurrences[label][term] += share * frequencies[term]!;
        }
      }
    }
    final size = finalTraining.vocabulary.terms.length;
    final weights = <List<double>>[];
    for (final row in occurrences) {
      var total = 0.0;
      for (final value in row) {
        total += value;
      }
      weights.add([for (final value in row) smoothedLog(value, total, selected[0], size)]);
    }
    final scale = training.length + (settings.weight * unlabelled.length) / 100;
    final priors = [for (final value in documents) math.log(value / scale)];
    return NaiveBayes(0, priors, List.filled(classes.length, 0.0), weights);
  }
  List<String> semiSupervisedPart() {
    final sequences = unlabelled.map(finalTraining.encode).toList();
    var model = finalTraining.models[0];
    final lines = ['semi_supervised multinomial alpha ${alphaText(0)} weight ${hundredthsText(settings.weight)} unlabelled ${unlabelled.length}'];
    List<int>? previous;
    for (var iteration = 0; iteration <= settings.iterations; iteration++) {
      final posteriors = sequences.map(model.predict).toList();
      final assignments = posteriors.map((posterior) => posterior.label).toList();
      final predicted = [for (final index in labelled) model.predict(testSequences[index]).label];
      final evaluation = Evaluation(classes.length, truths, predicted);
      var changed = '-';
      if (previous != null) {
        var count = 0;
        for (var i = 0; i < assignments.length; i++) {
          if (assignments[i] != previous[i]) count++;
        }
        changed = count.toString();
      }
      final assigned = List.filled(classes.length, 0);
      for (final label in assignments) {
        assigned[label]++;
      }
      lines.add('iteration $iteration correct ${proportionText(evaluation.correct, evaluation.total)} macro_f1 ${realText(evaluation.macro)} changed $changed assigned ${classCountsText(classes, assigned)}');
      if (iteration < settings.iterations) model = maximization(posteriors, sequences);
      previous = assignments;
    }
    return lines;
  }
  List<List<String>> metricsParts() => [
    dataPart(), foldsPart(), selectionPart(),
    for (var model = 0; model < 4; model++) crossValidationPart(model),
    for (var model = 0; model < 5; model++) testPart(model),
    for (var model = 0; model < 3; model++) probabilityPart(model),
    lengthsPart(), comparisonPart(), bootstrapPart(), hardPart(), uncertainPart(), misclassifiedPart(), semiSupervisedPart(),
  ];
  List<List<String>> characteristicParts(int kind) {
    final counts = finalTraining.counts;
    final terms = finalTraining.vocabulary.terms;
    final size = terms.length;
    final alpha = selected[kind];
    final table = kind == 0 ? counts.occurrences : counts.containing;
    final totals = kind == 0 ? counts.totals : counts.documents;
    final overall = kind == 0 ? counts.total : counts.documentTotal;
    final outcomes = kind == 0 ? size : 2;
    final termTotals = [for (var term = 0; term < size; term++) table.fold<int>(0, (sum, row) => sum + row[term])];
    final parts = <List<String>>[['model ${modelNames[kind]} alpha ${hundredthsText(alpha)} vocabulary $size top ${settings.top}']];
    for (var label = 0; label < classes.length; label++) {
      final total = totals[label];
      final other = overall - total;
      final lines = ['class ${classes[label]} total $total other $other'];
      final entries = [for (var term = 0; term < size; term++)
        RatioEntry(100 * table[label][term] + alpha, 100 * (termTotals[term] - table[label][term]) + alpha, term)];
      rankRatios(entries);
      final selectedEntries = entries.take(settings.top).toList();
      for (var rank = 0; rank < selectedEntries.length; rank++) {
        final term = selectedEntries[rank].term;
        final count = table[label][term];
        final otherCount = termTotals[term] - count;
        final odds = smoothedLog(count, total, alpha, outcomes) - smoothedLog(otherCount, other, alpha, outcomes);
        lines.add('${rank + 1} ${terms[term]} $count $otherCount ${realText(odds)}');
      }
      parts.add(lines);
    }
    return parts;
  }
  List<List<String>> topFeatureParts() => [...characteristicParts(0), ...characteristicParts(1)];
}

void main() {
  final experiment = Experiment();
  experiment.crossValidate();
  experiment.selectAlphas();
  experiment.trainFinal();
  Directory('output').createSync(recursive: true);
  writeLines('vocabulary.txt', experiment.vocabularyLines());
  writeLines('cv_results.csv', experiment.cvLines());
  writeLines('predictions.csv', experiment.predictionLines());
  writeLines('learning_curve.csv', experiment.curveLines());
  writeLines('feature_study.csv', experiment.featureLines());
  writeLines('metrics.txt', joinParts(experiment.metricsParts()));
  writeLines('top_features.txt', joinParts(experiment.topFeatureParts()));
}
