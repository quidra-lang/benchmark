import 'dart:math' as math;
import 'dataset.dart';
import 'impurity.dart';

String halfText(int point) => '${point ~/ 2}.${5 * (point % 2)}';

class Split {
  final Attribute attribute;
  final int point;
  Split(this.attribute, this.point);
  bool goesLeft(int value) => attribute.integer ? 2 * value <= point : value == point;
  String condition(bool left) => attribute.integer
      ? '${attribute.name} ${left ? '<=' : '>'} ${halfText(point)}'
      : '${attribute.name} ${left ? '=' : '!='} ${attribute.values[point]}';
}

class Surrogate {
  final Split split;
  final bool left;
  final int score;
  Surrogate(this.split, this.left, this.score);
}

class Candidate {
  final Split split;
  final List<Row> left, right;
  final Fraction value;
  Candidate(this.split, this.left, this.right, this.value);
}

class Node {
  final int number, depth;
  final Statistics stats;
  Split? split;
  List<Surrogate> surrogates = [];
  bool defaultLeft = true;
  Node? left, right;
  Node(this.number, this.depth, this.stats);
}

List<Split> splitCandidates(List<Row> rows, Attribute attribute) {
  final values = rows.map((row) => row.values[attribute.index]!).toSet().toList()..sort();
  if (values.length < 2) return [];
  return attribute.integer
      ? [for (var index = 1; index < values.length; index++) Split(attribute, values[index - 1] + values[index])]
      : [for (final value in values) Split(attribute, value)];
}

class TreeBuilder {
  final List<Attribute> attributes;
  final int classes;
  final Settings settings;
  TreeBuilder(this.attributes, this.classes, this.settings);

  Candidate? bestForAttribute(List<Row> rows, Attribute attribute) {
    Candidate? best;
    for (final split in splitCandidates(rows, attribute)) {
      final left = <Row>[], right = <Row>[];
      for (final row in rows) {
        (split.goesLeft(row.values[attribute.index]!) ? left : right).add(row);
      }
      if (left.length < settings.minLeaf || right.length < settings.minLeaf) continue;
      final value = quality(statistics(left, classes), statistics(right, classes));
      if (best == null || compareFractions(value, best.value) > 0) {
        best = Candidate(split, left, right, value);
      }
    }
    return best;
  }

  Candidate? bestSplit(List<Row> rows) {
    Candidate? best;
    for (final attribute in attributes) {
      final candidate = bestForAttribute(rows, attribute);
      if (candidate != null && (best == null || compareFractions(candidate.value, best.value) > 0)) best = candidate;
    }
    return best;
  }

  List<Surrogate> findSurrogates(List<Row> rows, Split primary, int leftCount, int rightCount) {
    final retained = <Surrogate>[];
    for (final attribute in attributes) {
      if (attribute.index == primary.attribute.index) continue;
      Surrogate? best;
      for (final split in splitCandidates(rows, attribute)) {
        var agreement = 0;
        for (final row in rows) {
          if (split.goesLeft(row.values[attribute.index]!) == primary.goesLeft(row.values[primary.attribute.index]!)) agreement++;
        }
        final left = agreement >= rows.length - agreement;
        final score = math.max(agreement, rows.length - agreement);
        if (best == null || score > best.score) best = Surrogate(split, left, score);
      }
      if (best != null && best.score > math.max(leftCount, rightCount)) retained.add(best);
    }
    retained.sort((a, b) {
      final order = b.score.compareTo(a.score);
      return order != 0 ? order : a.split.attribute.index.compareTo(b.split.attribute.index);
    });
    return retained.take(settings.maxSurrogates).toList();
  }

  Node grow(List<Row> rows) => growNode(rows, 1, 0);

  Node growNode(List<Row> rows, int number, int depth) {
    final node = Node(number, depth, statistics(rows, classes));
    if (node.stats.errors == 0 || depth == settings.maxDepth || rows.length < settings.minSplit) return node;
    final best = bestSplit(rows);
    if (best == null || !improves(best.value, node.stats)) return node;
    node.split = best.split;
    node.defaultLeft = best.left.length >= best.right.length;
    node.surrogates = findSurrogates(rows, best.split, best.left.length, best.right.length);
    node.left = growNode(best.left, 2 * number, depth + 1);
    node.right = growNode(best.right, 2 * number + 1, depth + 1);
    return node;
  }
}
