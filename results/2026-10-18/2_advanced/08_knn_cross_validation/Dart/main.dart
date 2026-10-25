import 'dart:io';
import 'dart:math';
import 'dataset.dart';
import 'scaling.dart';
import 'neighbors.dart';
import 'validation.dart';
import 'report.dart';

List<DataRow> idOrder(List<DataRow> rows) => [...rows]..sort((a, b) => a.id.compareTo(b.id));
String labelCounts(List<DataRow> rows, List<String> labels) {
  final counts = {for (final label in labels) label: 0};
  for (final row in rows) { counts[row.label!] = counts[row.label!]! + 1; }
  return [for (final label in labels) '$label ${counts[label]}'].join(' ');
}

List<String> evaluationLines(List<(String, String)> pairs, List<String> labels) {
  final matrix = {for (final label in labels) label: {for (final other in labels) other: 0}};
  for (final (truth, predicted) in pairs) { matrix[truth]![predicted] = matrix[truth]![predicted]! + 1; }
  final lines = ['true\\predicted ${labels.join(' ')}'];
  for (final label in labels) { lines.add('$label ${matrix[label]!.values.join(' ')}'); }
  final totals = [0.0, 0.0, 0.0], valued = [0, 0, 0];
  for (final label in labels) {
    final hits = matrix[label]![label]!; var predicted = 0, actual = 0;
    for (final other in labels) { predicted += matrix[other]![label]!; actual += matrix[label]![other]!; }
    final metrics = [(hits, predicted), (hits, actual), (2 * hits, predicted + actual)];
    for (var j = 0; j < metrics.length; j++) { final (a, b) = metrics[j]; if (b > 0) { totals[j] += a / b; valued[j]++; } }
    lines.add('class $label precision ${fraction(hits, predicted)} recall ${fraction(hits, actual)} f1 ${fraction(2 * hits, predicted + actual)} support $actual');
  }
  final averages = [for (var j = 0; j < 3; j++) valued[j] > 0 ? fixed(totals[j] / valued[j]) : '-'];
  lines.add('macro precision ${averages[0]} recall ${averages[1]} f1 ${averages[2]}'); return lines;
}

List<String> reliabilityLines(List<(Prediction, String)> pairs, List<double> bounds) {
  final lowers = [0.0, ...bounds], counts = List.filled(bounds.length + 1, 0), hits = List.filled(bounds.length + 1, 0), shares = List.filled(bounds.length + 1, 0.0);
  for (final (p, truth) in pairs) {
    final j = bounds.where((bound) => bound <= p.share).length; counts[j]++; if (p.label == truth) hits[j]++; shares[j] += p.share;
  }
  return [for (var j = 0; j < lowers.length; j++) 'bin ${fixed(lowers[j], 2)} rows ${counts[j]}${counts[j] == 0 ? '' : ' correct ${ratio(hits[j], counts[j])} share ${fixed(shares[j] / counts[j])}'}'];
}

class ClassifierSpace {
  final Model model;
  final distances = <String, Map<String, double>>{};
  ClassifierSpace(this.model, List<DataRow> train, List<DataRow> test) {
    final scaling = Scaling(train, model.scaling), features = List.generate(train.first.values.length, (j) => j);
    final references = [for (final row in train) scaling.transform(row.values, features)];
    for (final query in [...train, ...test]) {
      final vector = scaling.transform(query.values, features);
      distances[query.id] = {for (var j = 0; j < train.length; j++) train[j].id: distance(vector, references[j], model.metric)};
    }
  }
  List<Neighbor> order(DataRow query, List<DataRow> rows) => sortNeighbors([for (final row in rows) (gap: distances[query.id]![row.id]!, row: row)]);
  Prediction vote(DataRow query, List<DataRow> rows, int k) => Prediction.fromOrder(order(query, rows), k, model.weighting, retain: false);
  String nearestLabel(DataRow query, List<DataRow> rows) => order(query, rows).first.row.label!;
}

(List<DataRow>, List<List<(DataRow, Prediction)>>) wilsonEditing(ClassifierSpace space, List<DataRow> rows, int k) {
  final passes = <List<(DataRow, Prediction)>>[]; var current = rows;
  while (true) {
    final removals = <(DataRow, Prediction)>[];
    for (final row in current) {
      final p = space.vote(row, current.where((other) => !identical(other, row)).toList(), k);
      if (p.label != row.label) removals.add((row, p));
    }
    passes.add(removals); if (removals.isEmpty) return (current, passes);
    final removed = {for (final (row, _) in removals) row.id}; current = current.where((row) => !removed.contains(row.id)).toList();
  }
}

(List<DataRow>, int) hartCondensing(ClassifierSpace space, List<DataRow> rows) {
  final store = [rows.first], stored = {rows.first.id}; var scans = 0, added = true;
  while (added) {
    scans++; added = false;
    for (final row in rows) {
      if (!stored.contains(row.id) && space.nearestLabel(row, store) != row.label) { store.add(row); stored.add(row.id); added = true; }
    }
  }
  return (idOrder(store), scans);
}

class Experiment {
  final List<String> featureNames;
  final List<DataRow> train, test;
  final Settings settings;
  late final List<int> features;
  late final List<String> labels;
  late final List<DataRow> labelled, targeted;
  late final List<Model> grid;
  late final List<List<int>> folds;
  late final List<CrossValidation> results;
  late final CrossValidation classifier, regressor;
  late final List<Prediction> testPredictions;
  late final List<double> testEstimates;
  late final List<(DataRow, Prediction)> labelledPredictions;
  Experiment(this.featureNames, this.train, this.test, this.settings) {
    features = List.generate(featureNames.length, (j) => j); labels = train.map((row) => row.label!).toSet().toList()..sort();
    labelled = test.where((row) => row.label != null).toList(); targeted = test.where((row) => row.target != null).toList();
    grid = [for (final k in settings.kValues) for (final metric in settings.metrics) for (final weighting in settings.weightings) for (final scaling in settings.scalings) Model(k, metric, weighting, scaling)];
    folds = stratifiedFolds(train, settings.folds); results = crossValidate(grid, train, settings.folds, features);
    classifier = bestClassifier(results); regressor = bestRegressor(results);
    testPredictions = predictRows(classifier.model, train, test, features); testEstimates = predictRows(regressor.model, train, test, features).map((p) => p.estimate).toList();
    labelledPredictions = [for (var j = 0; j < test.length; j++) if (test[j].label != null) (test[j], testPredictions[j])];
  }
  String names(List<int> used) => used.map((j) => featureNames[j]).join(' ');
  String trainRatio(int count) => ratio(count, train.length);
  String classifierSummary(CrossValidation result) => '${result.model.notation()} correct ${trainRatio(result.correct)} rmse ${fixed(result.rmse)}';
  String regressorSummary(CrossValidation result) => '${result.model.notation()} rmse ${fixed(result.rmse)} correct ${trainRatio(result.correct)}';
  List<String> gridTable() => ['k,metric,weighting,scaling,correct,accuracy,rmse', for (final r in results) '${r.model.k},${r.model.metric},${r.model.weighting},${r.model.scaling},${r.correct},${fixed(r.correct / train.length)},${fixed(r.rmse)}'];
  List<String> predictionTable() => ['id,label,vote_share,estimate', for (var j = 0; j < test.length; j++) '${test[j].id},${testPredictions[j].label},${fixed(testPredictions[j].share)},${fixed(testEstimates[j])}'];
  List<String> dataPart() => ['data train ${train.length} test ${test.length} labelled ${labelled.length} targets ${targeted.length} features ${features.length} classes ${labels.length}', 'classes ${labelCounts(train, labels)}'];
  List<String> scalingPart(String method) {
    final scaling = Scaling(train, method);
    return ['scaling $method', for (var j = 0; j < features.length; j++) '${featureNames[j]} center ${fixed(scaling.centers[j], 6)} scale ${fixed(scaling.scales[j], 6)}'];
  }
  List<String> foldsPart() => ['folds ${settings.folds}', for (var j = 0; j < folds.length; j++) 'fold ${j + 1} size ${folds[j].length} ${labelCounts([for (final index in folds[j]) train[index]], labels)}'];
  List<String> topPart(bool accuracy) {
    final ranking = List.generate(results.length, (j) => j);
    ranking.sort((a, b) {
      final comparison = accuracy ? results[b].correct.compareTo(results[a].correct) : fourDecimal(results[a].rmse).compareTo(fourDecimal(results[b].rmse));
      return comparison == 0 ? a.compareTo(b) : comparison;
    });
    return ['top ${settings.top} by ${accuracy ? 'accuracy' : 'rmse'}', for (var j = 0; j < min(settings.top, ranking.length); j++) '${j + 1} ${accuracy ? classifierSummary(results[ranking[j]]) : regressorSummary(results[ranking[j]])}'];
  }
  List<List<String>> bestPerParts() {
    final items = <(String, List<String>, String Function(Model))>[
      ('k', settings.kValues.map((k) => '$k').toList(), (m) => '${m.k}'), ('metric', settings.metrics, (m) => m.metric),
      ('weighting', settings.weightings, (m) => m.weighting), ('scaling', settings.scalings, (m) => m.scaling),
    ];
    final parts = <List<String>>[];
    for (final (item, values, attribute) in items) {
      final lines = ['best per $item'];
      for (final value in values) {
        final group = results.where((r) => attribute(r.model) == value).toList();
        final cl = bestClassifier(group), reg = bestRegressor(group);
        lines.add('$item=$value classifier ${cl.model.notation()} accuracy ${fixed(cl.correct / train.length)} regressor ${reg.model.notation()} rmse ${fixed(reg.rmse)}');
      }
      parts.add(lines);
    }
    return parts;
  }
  List<List<String>> modelFoldParts() {
    final cl = ['classifier folds'], reg = ['regressor folds'];
    for (var j = 0; j < folds.length; j++) {
      final fold = folds[j], correct = folds[j].where((index) => classifier.hits[index]).length;
      final errors = [for (final index in fold) regressor.predictions[index].estimate - train[index].target!];
      cl.add('fold ${j + 1} correct ${ratio(correct, fold.length)}'); reg.add('fold ${j + 1} size ${fold.length} rmse ${fixed(rootMeanSquare(errors))}');
    }
    return [cl, reg];
  }
  List<String> mcnemarPart() {
    final lines = ['mcnemar'];
    for (final metric in settings.metrics) {
      final comparison = bestClassifier(results.where((r) => r.model.metric == metric).toList()); var b = 0, c = 0;
      for (var j = 0; j < train.length; j++) { if (classifier.hits[j] && !comparison.hits[j]) b++; else if (!classifier.hits[j] && comparison.hits[j]) c++; }
      final disagreements = b + c, difference = max(0, (b - c).abs() - 1), u = difference * difference;
      lines.add('${comparison.model.notation()} b $b c $c statistic ${disagreements == 0 ? '0/1 0.0000' : fraction(u, disagreements)} significant ${1000 * u > 3841 * disagreements ? 'yes' : 'no'}');
    }
    return lines;
  }
  List<List<String>> leaveOneOutParts() {
    final model = classifier.model, byK = {for (final k in settings.kValues) k: <Prediction>[]}, estimates = <double>[];
    for (var index = 0; index < train.length; index++) {
      final row = train[index], others = trainingRows(train, [index]);
      final order = neighborOrders(others, [row], model.scaling, model.metric, features).first;
      for (final k in settings.kValues) { byK[k]!.add(Prediction.fromOrder(order, k, model.weighting, retain: false)); }
      estimates.add(predictRows(regressor.model, others, [row], features).first.estimate);
    }
    final predictions = byK[model.k]!, errors = <(DataRow, Prediction)>[], classErrors = {for (final label in labels) label: 0};
    for (var j = 0; j < train.length; j++) {
      if (predictions[j].label != train[j].label) { errors.add((train[j], predictions[j])); classErrors[train[j].label!] = classErrors[train[j].label!]! + 1; }
    }
    errors.sort((a, b) => a.$1.id.compareTo(b.$1.id));
    final cl = ['leave_one_out classifier ${model.notation()}', 'errors ${trainRatio(errors.length)}', 'class_errors ${[for (final label in labels) '$label ${classErrors[label]}'].join(' ')}', for (final (row, p) in errors) '${row.id} true ${row.label} predicted ${p.label} share ${fixed(p.share)}'];
    final residuals = [for (var j = 0; j < train.length; j++) estimates[j] - train[j].target!], ranking = List.generate(train.length, (j) => j);
    ranking.sort((a, b) {
      final comparison = fourDecimal(residuals[b].abs()).compareTo(fourDecimal(residuals[a].abs())); return comparison == 0 ? train[a].id.compareTo(train[b].id) : comparison;
    });
    final reg = ['leave_one_out regressor ${regressor.model.notation()}', 'rmse ${fixed(rootMeanSquare(residuals))} mae ${fixed(meanAbsolute(residuals))}', 'largest ${settings.top} residuals', for (final j in ranking.take(settings.top)) '${train[j].id} target ${fixed(train[j].target!)} estimate ${fixed(estimates[j])} residual ${fixed(residuals[j])}'];
    final by = ['leave_one_out by k metric=${model.metric} weighting=${model.weighting} scaling=${model.scaling}'];
    for (final k in settings.kValues) {
      final errors = [for (var j = 0; j < train.length; j++) byK[k]![j].estimate - train[j].target!];
      by.add('k=$k correct ${trainRatio(correctCount(byK[k]!, train))} rmse ${fixed(rootMeanSquare(errors))}');
    }
    return [cl, reg, by];
  }
  List<String> nestedPart() {
    final lines = ['nested_cross_validation folds ${settings.folds}'], estimates = List.filled(train.length, 0.0); var total = 0;
    for (var j = 0; j < folds.length; j++) {
      final fold = folds[j], inner = trainingRows(train, folds[j]), queries = [for (final index in folds[j]) train[index]];
      final results = crossValidate(grid, inner, settings.folds, features);
      final cl = bestClassifier(results), reg = bestRegressor(results);
      final correct = correctCount(predictRows(cl.model, inner, queries, features), queries); total += correct;
      final predictions = predictRows(reg.model, inner, queries, features), errors = <double>[];
      for (var p = 0; p < fold.length; p++) { final index = fold[p]; estimates[index] = predictions[p].estimate; errors.add(estimates[index] - train[index].target!); }
      lines.add('fold ${j + 1} classifier ${cl.model.notation()} inner ${fixed(cl.correct / inner.length)} outer ${ratio(correct, fold.length)}');
      lines.add('fold ${j + 1} regressor ${reg.model.notation()} inner ${fixed(reg.rmse)} outer ${fixed(rootMeanSquare(errors))}');
    }
    final errors = [for (var j = 0; j < train.length; j++) estimates[j] - train[j].target!]; lines.add('nested accuracy ${trainRatio(total)} rmse ${fixed(rootMeanSquare(errors))}'); return lines;
  }
  List<String> featurePart() {
    final model = classifier.model; var current = [...features], selected = [...features], selectedCorrect = classifier.correct, step = 0;
    final lines = ['feature_selection ${model.notation()}', 'start features ${names(current)} correct ${trainRatio(selectedCorrect)}'];
    while (current.length >= 3) {
      step++; final candidates = <String>[]; var removed = current.first, correct = -1;
      for (final feature in current) {
        final remaining = current.where((other) => other != feature).toList();
        final result = crossValidate([model], train, settings.folds, remaining).first;
        candidates.add('${featureNames[feature]} ${result.correct}'); if (result.correct > correct) { correct = result.correct; removed = feature; }
      }
      current = current.where((other) => other != removed).toList(); lines.add('step $step remove ${featureNames[removed]} correct ${trainRatio(correct)} candidates ${candidates.join(' ')}');
      if (correct >= selectedCorrect) { selected = [...current]; selectedCorrect = correct; }
    }
    final predictions = predictRows(model, train, labelled, selected); lines.add('selected features ${names(selected)} correct ${trainRatio(selectedCorrect)}'); lines.add('selected test ${ratio(correctCount(predictions, labelled), labelled.length)}'); return lines;
  }
  List<String> uncertainPart() {
    final margins = [for (final p in testPredictions) p.share - p.runnerShare], ranking = List.generate(test.length, (j) => j);
    ranking.sort((a, b) { final c = fourDecimal(margins[a]).compareTo(fourDecimal(margins[b])); return c == 0 ? a.compareTo(b) : c; });
    return ['uncertain ${settings.top} test rows', for (final j in ranking.take(settings.top)) '${test[j].id} predicted ${testPredictions[j].label} share ${fixed(testPredictions[j].share)} runner_up ${testPredictions[j].runner ?? '-'} share ${fixed(testPredictions[j].runnerShare)} margin ${fixed(margins[j])} true ${test[j].label ?? '-'}'];
  }
  List<String> regressionPart() {
    final errors = <double>[], targets = <double>[], classErrors = {for (final label in labels) label: <double>[]};
    for (var j = 0; j < test.length; j++) {
      final row = test[j]; if (row.target == null) continue; final error = testEstimates[j] - row.target!;
      errors.add(error); targets.add(row.target!); if (row.label != null) classErrors[row.label]!.add(error);
    }
    return ['test regression ${regressor.model.notation()}', 'targets ${errors.length} rmse ${fixed(rootMeanSquare(errors))} mae ${fixed(meanAbsolute(errors))} r2 ${fixed(rSquared(errors, targets))}', for (final label in labels) 'class $label targets ${classErrors[label]!.length} rmse ${classErrors[label]!.isEmpty ? '-' : fixed(rootMeanSquare(classErrors[label]!))}'];
  }
  List<String> misclassifiedPart() {
    final lines = ['misclassified test rows']; var count = 0;
    for (final (row, p) in labelledPredictions) {
      if (p.label == row.label) continue; count++; lines.add('${row.id} true ${row.label} predicted ${p.label} share ${fixed(p.share)}');
      for (final neighbor in p.neighbors) { lines.add('  ${neighbor.row.id} ${neighbor.row.label} ${fixed(neighbor.gap)}'); }
    }
    lines.add('count $count'); return lines;
  }
  List<String> metricsReport() {
    final pairs = <(String, String)>[], shares = <(Prediction, String)>[];
    for (var j = 0; j < train.length; j++) { final p = classifier.predictions[j]; pairs.add((train[j].label!, p.label)); shares.add((p, train[j].label!)); }
    final testPairs = [for (final (row, p) in labelledPredictions) (row.label!, p.label)], testShares = [for (final (row, p) in labelledPredictions) (p, row.label!)];
    final correct = testPairs.where((pair) => pair.$1 == pair.$2).length;
    return joinParts([dataPart(), for (final method in settings.scalings) scalingPart(method), foldsPart(), ['grid ${grid.length}', 'best_classifier ${classifierSummary(classifier)}', 'best_regressor ${regressorSummary(regressor)}'], topPart(true), topPart(false), ...bestPerParts(), ...modelFoldParts(), ['cross_validation classes', ...evaluationLines(pairs, labels)], ['cross_validation reliability', ...reliabilityLines(shares, settings.bins)], mcnemarPart(), ...leaveOneOutParts(), nestedPart(), featurePart(), ['test classification ${classifier.model.notation()}', 'labelled ${testPairs.length} correct ${ratio(correct, testPairs.length)}', ...evaluationLines(testPairs, labels)], ['test reliability', ...reliabilityLines(testShares, settings.bins)], uncertainPart(), regressionPart(), misclassifiedPart()]);
  }
  List<String> learningCurveTable() {
    final lines = ['n,train_size,correct,accuracy,rmse'];
    for (final limit in settings.curve) {
      final taken = {for (final label in labels) label: 0}, rows = <DataRow>[];
      for (final row in train) { if (taken[row.label!]! < limit) { taken[row.label!] = taken[row.label!]! + 1; rows.add(row); } }
      final correct = correctCount(predictRows(classifier.model, rows, labelled, features), labelled), predictions = predictRows(regressor.model, rows, targeted, features);
      final errors = [for (var j = 0; j < targeted.length; j++) predictions[j].estimate - targeted[j].target!];
      lines.add('$limit,${rows.length},$correct,${fixed(correct / labelled.length)},${fixed(rootMeanSquare(errors))}');
    }
    return lines;
  }
  String prototypeLine(ClassifierSpace space, String name, List<DataRow> rows) {
    var knn = 0, nearest = 0;
    for (final row in labelled) { if (space.vote(row, rows, classifier.model.k).label == row.label) knn++; if (space.nearestLabel(row, rows) == row.label) nearest++; }
    return 'set $name size ${rows.length} ${labelCounts(rows, labels)} knn ${ratio(knn, labelled.length)} 1nn ${ratio(nearest, labelled.length)}';
  }
  List<String> bordersPart(ClassifierSpace space, List<DataRow> ordered) {
    final lines = ['borders']; var total = 0;
    for (final label in labels) {
      final members = ordered.where((row) => row.label == label).toList(); var borders = 0, sameTotal = 0.0, otherTotal = 0.0;
      for (final row in members) {
        final order = space.order(row, ordered.where((other) => !identical(other, row)).toList());
        if (order.first.row.label != label) borders++; sameTotal += order.firstWhere((neighbor) => neighbor.row.label == label).gap; otherTotal += order.firstWhere((neighbor) => neighbor.row.label != label).gap;
      }
      total += borders; lines.add('class $label size ${members.length} border $borders same ${fixed(sameTotal / members.length)} other ${fixed(otherTotal / members.length)}');
    }
    lines.add('border total ${trainRatio(total)}'); return lines;
  }
  List<String> hubsPart() {
    final occurrences = {for (final row in train) row.id: 0};
    for (final p in testPredictions) { for (final neighbor in p.neighbors) { final id = neighbor.row.id; occurrences[id] = occurrences[id]! + 1; } }
    final ranked = [...train]..sort((a, b) { final c = occurrences[b.id]!.compareTo(occurrences[a.id]!); return c == 0 ? a.id.compareTo(b.id) : c; });
    return ['hubs k=${classifier.model.k} queries ${test.length}', for (final row in ranked.take(settings.top)) '${row.id} ${row.label} ${occurrences[row.id]}', 'anti_hubs ${occurrences.values.where((count) => count == 0).length}'];
  }
  List<String> prototypesReport() {
    final space = ClassifierSpace(classifier.model, train, test), ordered = idOrder(train);
    final (edited, passes) = wilsonEditing(space, ordered, settings.editK);
    final (condensed, scans) = hartCondensing(space, ordered);
    final (editedCondensed, editedScans) = hartCondensing(space, edited);
    final editing = ['editing k=${settings.editK}'];
    for (var j = 0; j < passes.length; j++) { editing.add('pass ${j + 1} removed ${passes[j].length}'); for (final (row, p) in passes[j]) { editing.add('  ${row.id} true ${row.label} predicted ${p.label} share ${fixed(p.share)}'); } }
    editing.add('edited size ${edited.length} removed ${train.length - edited.length}');
    List<String> idLines(List<DataRow> rows) => [for (var start = 0; start < rows.length; start += 10) rows.skip(start).take(10).map((row) => row.id).join(' ')];
    return joinParts([['space ${classifier.model.notation()}'], editing, ['condensing original scans $scans size ${condensed.length}', 'condensing edited scans $editedScans size ${editedCondensed.length}'], [prototypeLine(space, 'original', ordered), prototypeLine(space, 'edited', edited), prototypeLine(space, 'condensed', condensed), prototypeLine(space, 'edited_condensed', editedCondensed)], ['prototypes condensed', ...idLines(condensed)], ['prototypes edited_condensed', ...idLines(editedCondensed)], bordersPart(space, ordered), hubsPart()]);
  }
}

void main() {
  final (featureNames, train) = readRows('train.csv');
  final (_, test) = readRows('test.csv');
  final experiment = Experiment(featureNames, train, test, Settings('input/params.txt'));
  Directory('output').createSync(recursive: true);
  writeLines('cv_grid.csv', experiment.gridTable()); writeLines('predictions.csv', experiment.predictionTable()); writeLines('metrics.txt', experiment.metricsReport());
  writeLines('learning_curve.csv', experiment.learningCurveTable()); writeLines('prototypes.txt', experiment.prototypesReport());
}
