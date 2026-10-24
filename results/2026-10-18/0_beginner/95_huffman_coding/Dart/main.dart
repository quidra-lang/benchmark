import 'dart:math' as math;

class HNode {
    final int weight, minimum;
    final int ? symbol;
    final HNode? left, right;
    HNode(this.weight, this.minimum, { this.symbol, this.left, this.right });
}

void main() {
    const text = 'she sells sea shells by the sea shore';
    final frequency = <int, int>{};
    for (final c in text.codeUnits)
        frequency[c] = (frequency[c] ?? 0) + 1;
    final active = [for (final e in frequency.entries) HNode(e.value, e.key, symbol: e.key)];
    int compare(HNode a, HNode b) {
        final c = a.weight.compareTo(b.weight);
        return c != 0 ? c : a.minimum.compareTo(b.minimum);
    }
    while (active.length > 1) {
        active.sort(compare);
        final left = active.removeAt(0);
        final right = active.removeAt(0);
        active.add(HNode(left.weight + right.weight, math.min(left.minimum, right.minimum), left: left,
            right: right));
    }
    final codes = <int, String>{};
    void assign(HNode node, String path) {
        if (node.symbol != null) {
            codes[node.symbol!] = path;
            return;
        }
        assign(node.left!, path + '0');
        assign(node.right!, path + '1');
    }
    assign(active.single, '');
    final symbols = frequency.keys.toList()..sort();
    var bits = 0;
    for (final c in symbols) {
        print("'${String.fromCharCode(c)}' freq=${frequency[c]} code=${codes[c]}");
        bits += frequency[c]! * codes[c]!.length;
    }
    print('encoded bits: $bits\nfixed 8-bit: ${text.length*8}');
}
