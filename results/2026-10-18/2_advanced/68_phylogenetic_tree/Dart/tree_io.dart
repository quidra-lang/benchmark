part of 'main.dart';

String format(double x, int k) {
  final s = x.toStringAsFixed(k);
  return s.startsWith('-') && RegExp(r'^0(?:\.0+)?$').hasMatch(s.substring(1))
      ? s.substring(1)
      : s;
}

String symbol(int mask, int n) =>
    [for (var i = 0; i < n; i++) ((mask >> i) & 1) != 0 ? '*' : '.'].join();
List<int> sortedMasks(Iterable<int> set, int n) =>
    set.toList()..sort((a, b) => symbol(a, n).compareTo(symbol(b, n)));
String newick(
  Tree t,
  List<SequenceRecord> taxa,
  int outgroup,
  bool lengths,
  Map<int, int>? support,
) {
  final r = rootTree(t, taxa, outgroup);
  String visit(int v) {
    var s = '';
    if (v < taxa.length) {
      s = taxa[v].name;
    } else {
      s = '(${r.children[v]!.map(visit).join(',')})';
      if (v != r.root && support != null) s += '${support[r.masks[v]] ?? 0}';
    }
    if (v != r.root && lengths) s += ':${format(t.adj[v]![r.parent[v]]!, 5)}';
    return s;
  }

  return '${visit(r.root)};';
}

void cladogram(
  StringBuffer s,
  Tree t,
  List<SequenceRecord> taxa,
  int outgroup,
  Map<int, int> support,
) {
  final r = rootTree(t, taxa, outgroup);
  s.writeln('*');
  void visit(int v, String prefix, bool last) {
    final connector = last ? '`-- ' : '|-- ',
        label = v < taxa.length
            ? taxa[v].name
            : '[${support[r.masks[v]] ?? 0}]';
    s.writeln('$prefix$connector$label');
    final next = prefix + (last ? '    ' : '|   '),
        children = r.children[v] ?? <int>[];
    for (var i = 0; i < children.length; i++) {
      visit(children[i], next, i == children.length - 1);
    }
  }

  final children = r.children[r.root]!;
  for (var i = 0; i < children.length; i++) {
    visit(children[i], '', i == children.length - 1);
  }
}

void write(String path, StringBuffer s) =>
    File(path).writeAsStringSync(s.toString());
