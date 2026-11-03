import 'baskets.dart';

typedef WeightedPattern = (Itemset, int);

class FPNode {
  final String? item;
  final int? parent;
  int count = 0;
  final Map<String, int> children = {};
  FPNode(this.item, this.parent);
}

class FPTree {
  late final Itemset header;
  final List<FPNode> nodes = [FPNode(null, null)];
  final Map<String, List<int>> links = {};
  FPTree(List<WeightedPattern> base, int minimum) {
    final supports = <String, int>{};
    for (final (items, weight) in base) { for (final item in items) { supports[item] = (supports[item] ?? 0) + weight; } }
    header = supports.keys.where((item) => supports[item]! >= minimum).toList()..sort((a, b) { final comparison = supports[b]!.compareTo(supports[a]!); return comparison != 0 ? comparison : a.compareTo(b); });
    final order = {for (final (index, item) in header.indexed) item: index};
    for (final item in header) { links[item] = []; }
    for (final (items, weight) in base) {
      final path = items.where(order.containsKey).toList()..sort((a, b) => order[a]!.compareTo(order[b]!)); var node = 0;
      for (final item in path) {
        if (!nodes[node].children.containsKey(item)) {
          final index = nodes.length; nodes.add(FPNode(item, node)); nodes[node].children[item] = index; links[item]!.add(index);
        }
        node = nodes[node].children[item]!; nodes[node].count += weight;
      }
    }
  }
  int support(String item) => links[item]!.fold(0, (sum, index) => sum + nodes[index].count);
  List<WeightedPattern> conditionalBase(String item) {
    final base = <WeightedPattern>[];
    for (final index in links[item]!) {
      final path = <String>[]; var ancestor = nodes[index].parent!;
      while (ancestor != 0) { path.add(nodes[ancestor].item!); ancestor = nodes[ancestor].parent!; }
      base.add((path.reversed.toList(), nodes[index].count));
    }
    return base;
  }
}

class GrowthResult {
  final int header, nodes;
  int conditionalTrees = 0, conditionalNodes = 0;
  final Frequent itemsets = {};
  GrowthResult(this.header, this.nodes);
}

GrowthResult fpGrowth(List<WeightedPattern> base, int minimum, int maxSize) {
  final tree = FPTree(base, minimum), result = GrowthResult(tree.header.length, tree.nodes.length - 1), stack = <(FPTree, Itemset)>[(tree, [])];
  while (stack.isNotEmpty) {
    final (current, suffix) = stack.removeLast();
    for (final item in current.header.reversed) {
      final items = [...suffix, item]..sort(); result.itemsets[setKey(items)] = (items: items, count: current.support(item));
      if (items.length < maxSize) {
        final conditional = FPTree(current.conditionalBase(item), minimum);
        if (conditional.nodes.length > 1) { stack.add((conditional, items)); result.conditionalTrees++; result.conditionalNodes += conditional.nodes.length - 1; }
      }
    }
  }
  return result;
}
