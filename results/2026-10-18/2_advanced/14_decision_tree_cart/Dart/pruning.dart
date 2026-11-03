import 'dataset.dart';
import 'impurity.dart';
import 'tree_builder.dart';
import 'evaluation.dart';

class Decision {
  final Node node;
  final int rows, leafError, subtreeError;
  final bool pruned;
  Decision(this.node, this.rows, this.leafError, this.subtreeError, this.pruned);
}

class SequenceTree {
  final Fraction alpha;
  final Tree tree;
  SequenceTree(this.alpha, this.tree);
}

(Tree, List<Decision>) reducedErrorPruning(Node root, List<Row> rows) {
  final original = Tree(root), reached = <int, List<Row>>{};
  for (final row in rows) {
    for (final node in original.route(row).path) { reached.putIfAbsent(node.number, () => []).add(row); }
  }
  final cuts = <int>{}, decisions = <Decision>[];
  int decide(Node node) {
    final visits = reached[node.number] ?? <Row>[];
    final leafError = visits.where((row) => row.label != node.stats.majority).length;
    if (node.split == null) return leafError;
    final subtreeError = decide(node.left!) + decide(node.right!);
    final pruned = leafError <= subtreeError;
    decisions.add(Decision(node, visits.length, leafError, subtreeError, pruned));
    if (pruned) { cuts.add(node.number); return leafError; }
    return subtreeError;
  }
  decide(root);
  return (Tree(root, cuts), decisions);
}

List<SequenceTree> costComplexitySequence(Node root) {
  var tree = Tree(root);
  final sequence = [SequenceTree((0, 1), tree)];
  while (!tree.isLeaf(root)) {
    Fraction? alpha;
    final weakest = <int>{};
    for (final node in tree.internal) {
      final leaves = tree.preorder(node).where(tree.isLeaf).toList();
      final strength = (node.stats.errors - sum(leaves.map((leaf) => leaf.stats.errors)), leaves.length - 1);
      final comparison = alpha == null ? -1 : compareFractions(strength, alpha);
      if (comparison < 0) {
        alpha = strength;
        weakest.clear();
        weakest.add(node.number);
      } else if (comparison == 0) { weakest.add(node.number); }
    }
    tree = Tree(root, {...tree.cuts, ...weakest});
    sequence.add(SequenceTree(alpha!, tree));
  }
  return sequence;
}
