import 'dart:math';
import 'dataset.dart';
import 'scaling.dart';
import 'neighbors.dart';
import 'report.dart';

class Model {
  final int k;
  final String metric, weighting, scaling;
  Model(this.k, this.metric, this.weighting, this.scaling);
  String notation() => 'k=$k metric=$metric weighting=$weighting scaling=$scaling';
}

List<List<int>> stratifiedFolds(List<DataRow> rows, int count) {
  final ordered = List.generate(rows.length, (j) => j);
  ordered.sort((a, b) {
    final comparison = rows[a].label!.compareTo(rows[b].label!);
    return comparison == 0 ? rows[a].id.compareTo(rows[b].id) : comparison;
  });
  final folds = List.generate(count, (_) => <int>[]);
  for (var j = 0; j < ordered.length; j++) { folds[j % count].add(ordered[j]); }
  for (final fold in folds) { fold.sort(); }
  return folds;
}

List<DataRow> trainingRows(List<DataRow> rows, List<int> fold) {
  final excluded = fold.toSet(); return [for (var j = 0; j < rows.length; j++) if (!excluded.contains(j)) rows[j]];
}

List<List<Neighbor>> neighborOrders(List<DataRow> training, List<DataRow> queries, String method, String metric, List<int> features) {
  final scaling = Scaling(training, method);
  final references = [for (final row in training) (vector: scaling.transform(row.values, features), row: row)];
  final orders = <List<Neighbor>>[];
  for (final query in queries) {
    final vector = scaling.transform(query.values, features);
    orders.add(sortNeighbors([for (final reference in references) (gap: distance(vector, reference.vector, metric), row: reference.row)]));
  }
  return orders;
}

List<Prediction> predictRows(Model model, List<DataRow> training, List<DataRow> queries, List<int> features) => [for (final order in neighborOrders(training, queries, model.scaling, model.metric, features)) Prediction.fromOrder(order, model.k, model.weighting)];

double rootMeanSquare(List<double> errors) { var sum = 0.0; for (final error in errors) { sum += error * error; } return sqrt(sum / errors.length); }
double meanAbsolute(List<double> errors) { var sum = 0.0; for (final error in errors) { sum += error.abs(); } return sum / errors.length; }
double rSquared(List<double> errors, List<double> targets) {
  var sum = 0.0; for (final target in targets) { sum += target; } final mean = sum / targets.length;
  var residual = 0.0; for (final error in errors) { residual += error * error; }
  var spread = 0.0; for (final target in targets) { final difference = target - mean; spread += difference * difference; }
  return 1 - residual / spread;
}
int correctCount(List<Prediction> predictions, List<DataRow> rows) { var count = 0; for (var j = 0; j < rows.length; j++) { if (predictions[j].label == rows[j].label) count++; } return count; }

class CrossValidation {
  final Model model;
  final List<Prediction> predictions;
  late final List<bool> hits;
  late final int correct;
  late final double rmse;
  CrossValidation(this.model, List<DataRow> rows, this.predictions) {
    hits = [for (var j = 0; j < rows.length; j++) predictions[j].label == rows[j].label]; correct = hits.where((hit) => hit).length;
    rmse = rootMeanSquare([for (var j = 0; j < rows.length; j++) predictions[j].estimate - rows[j].target!]);
  }
}

List<CrossValidation> crossValidate(List<Model> models, List<DataRow> rows, int count, List<int> features) {
  final predictions = List.generate(models.length, (_) => List<Prediction?>.filled(rows.length, null));
  final spaces = <String, List<int>>{};
  for (var j = 0; j < models.length; j++) { spaces.putIfAbsent('${models[j].scaling}|${models[j].metric}', () => []).add(j); }
  for (final fold in stratifiedFolds(rows, count)) {
    final training = trainingRows(rows, fold), queries = [for (final j in fold) rows[j]];
    for (final indices in spaces.values) {
      final first = models[indices.first];
      final orders = neighborOrders(training, queries, first.scaling, first.metric, features);
      for (final j in indices) {
        final model = models[j];
        for (var p = 0; p < fold.length; p++) { predictions[j][fold[p]] = Prediction.fromOrder(orders[p], model.k, model.weighting, retain: false); }
      }
    }
  }
  return [for (var j = 0; j < models.length; j++) CrossValidation(models[j], rows, predictions[j].cast<Prediction>())];
}

CrossValidation bestClassifier(List<CrossValidation> results) { var best = results.first; for (final result in results) { if (result.correct > best.correct) best = result; } return best; }
CrossValidation bestRegressor(List<CrossValidation> results) { var best = results.first; for (final result in results) { if (fourDecimal(result.rmse) < fourDecimal(best.rmse)) best = result; } return best; }
