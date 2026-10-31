part of 'main.dart';

class HuffNode {
  final int weight, minimum, symbol;
  final HuffNode? left, right;
  HuffNode(this.weight, this.minimum, this.symbol, [this.left, this.right]);
}

List<int> treeLengths(List<int> frequencies) {
  final lengths = List.filled(frequencies.length, 0),
      nodes = [
        for (var s = 0; s < frequencies.length; s++)
          if (frequencies[s] > 0) HuffNode(frequencies[s], s, s),
      ];
  if (nodes.isEmpty) return lengths;
  if (nodes.length == 1) {
    lengths[nodes.first.symbol] = 1;
    return lengths;
  }
  while (nodes.length > 1) {
    nodes.sort((a, b) {
      final result = a.weight.compareTo(b.weight);
      return result != 0 ? result : a.minimum.compareTo(b.minimum);
    });
    final a = nodes.removeAt(0), b = nodes.removeAt(0);
    nodes.add(
      HuffNode(a.weight + b.weight, math.min(a.minimum, b.minimum), -1, a, b),
    );
  }
  void visit(HuffNode node, int depth) {
    if (node.symbol >= 0) {
      lengths[node.symbol] = depth;
    } else {
      visit(node.left!, depth + 1);
      visit(node.right!, depth + 1);
    }
  }

  visit(nodes.first, 0);
  return lengths;
}

(List<int>, int) limitedLengths(List<int> frequencies, int maximum) {
  var weights = [...frequencies], halvings = 0;
  while (true) {
    final lengths = treeLengths(weights);
    if (lengths.fold(0, math.max) <= maximum) return (lengths, halvings);
    weights = [for (final w in weights) (w + 1) ~/ 2];
    halvings++;
  }
}

List<int> canonicalCodes(List<int> lengths) {
  final order =
          [
            for (var s = 0; s < lengths.length; s++)
              if (lengths[s] > 0) s,
          ]..sort((a, b) {
            final result = lengths[a].compareTo(lengths[b]);
            return result != 0 ? result : a.compareTo(b);
          }),
      codes = List.filled(lengths.length, 0);
  var code = 0, previous = 0;
  for (var i = 0; i < order.length; i++) {
    final s = order[i];
    if (i > 0) code = (code + 1) << (lengths[s] - previous);
    codes[s] = code;
    previous = lengths[s];
  }
  return codes;
}
