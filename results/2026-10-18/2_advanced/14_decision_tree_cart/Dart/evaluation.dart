import 'dart:math' as math;
import 'dataset.dart';
import 'impurity.dart';
import 'tree_builder.dart';

class RouteStep {
  final Node node;
  final bool left;
  final String method;
  RouteStep(this.node, this.left, this.method);
}

class Route {
  final Node leaf;
  final List<Node> path;
  final List<RouteStep> steps;
  Route(this.leaf, this.path, this.steps);
}

class Tree {
  final Node root;
  final Set<int> cuts;
  Tree(this.root, [Set<int>? cuts]) : cuts = cuts ?? {};
  bool isLeaf(Node node) => node.split == null || cuts.contains(node.number);

  List<Node> preorder([Node? start]) {
    final nodes = <Node>[], pending = [start ?? root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      nodes.add(node);
      if (!isLeaf(node)) { pending.add(node.right!); pending.add(node.left!); }
    }
    return nodes;
  }

  List<Node> get leaves => preorder().where(isLeaf).toList();
  List<Node> get internal => preorder().where((node) => !isLeaf(node)).toList();
  int get depth => leaves.map((node) => node.depth).reduce(math.max);
  int get trainingErrors => sum(leaves.map((node) => node.stats.errors));

  Route route(Row row) {
    var node = root;
    final path = <Node>[], steps = <RouteStep>[];
    while (true) {
      path.add(node);
      if (isLeaf(node)) return Route(node, path, steps);
      var left = node.defaultLeft, method = 'default';
      final split = node.split!, value = row.values[split.attribute.index];
      if (value != null) {
        left = split.goesLeft(value);
        method = 'primary';
      } else {
        for (final surrogate in node.surrogates) {
          final observed = row.values[surrogate.split.attribute.index];
          if (observed == null) continue;
          left = surrogate.split.goesLeft(observed) == surrogate.left;
          method = 'surrogate';
          break;
        }
      }
      steps.add(RouteStep(node, left, method));
      node = left ? node.left! : node.right!;
    }
  }

  int predict(Row row) => route(row).leaf.stats.majority;
  int correct(List<Row> rows) => rows.where((row) => predict(row) == row.label).length;
}

String realText(double value, [int places = 4]) {
  final text = value.toStringAsFixed(places);
  return double.parse(text) == 0 ? 0.0.toStringAsFixed(places) : text;
}

String ratioText(int numerator, int denominator) => denominator == 0
    ? '0/0 -' : '$numerator/$denominator ${realText(numerator / denominator)}';

String fractionText(int numerator, int denominator, [int places = 4]) {
  if (denominator == 0) return '- -';
  final divisor = numerator.abs().gcd(denominator);
  return '${numerator ~/ divisor}/${denominator ~/ divisor} ${realText(numerator / denominator, places)}';
}

List<String> classificationLines(String title, List<String> classes, List<Row> rows, List<int> predicted) {
  final matrix = List.generate(classes.length, (_) => List.filled(classes.length, 0));
  var correct = 0;
  for (var index = 0; index < rows.length; index++) {
    matrix[rows[index].label][predicted[index]]++;
    if (rows[index].label == predicted[index]) correct++;
  }
  final lines = [
    'confusion $title correct $correct/${rows.length} accuracy ${fractionText(correct, rows.length)}',
    'actual\\predicted ${classes.join(' ')}',
    for (var index = 0; index < classes.length; index++) '${classes[index]} ${matrix[index].join(' ')}',
  ];
  var macro = 0.0, defined = 0;
  for (var index = 0; index < classes.length; index++) {
    final hits = matrix[index][index], predictedTotal = sum(matrix.map((counts) => counts[index])), support = sum(matrix[index]);
    final denominator = predictedTotal + support;
    if (denominator > 0) { macro += 2 * hits / denominator; defined++; }
    lines.add('class ${classes[index]} precision ${fractionText(hits, predictedTotal)} recall ${fractionText(hits, support)} f1 ${fractionText(2 * hits, denominator)} support $support');
  }
  lines.add('macro_f1 ${defined == 0 ? '-' : realText(macro / defined)}');
  return lines;
}
