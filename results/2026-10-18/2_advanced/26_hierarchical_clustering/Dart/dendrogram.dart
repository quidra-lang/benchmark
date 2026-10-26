import 'dart:math' as math;
import 'agglomerative.dart';

List<(int, int)> orderedChildren(List<Merge> merges, int count) {
  final minimum = List.generate(count, (i) => i);
  final children = <(int, int)>[];
  for (final merge in merges) {
    children.add(minimum[merge.a] < minimum[merge.b] ? (merge.a, merge.b) : (merge.b, merge.a));
    minimum.add(math.min(minimum[merge.a], minimum[merge.b]));
  }
  return children;
}
List<int> leafOrder(List<(int, int)> children, int count) {
  final order = <int>[];
  final pending = [count + children.length - 1];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node < count) {
      order.add(node);
    } else {
      final (upper, lower) = children[node - count];
      pending.addAll([lower, upper]);
    }
  }
  return order;
}
int column(double height, double maximum, int width) {
  final position = height / maximum * width;
  return position >= width + 1 ? width + 1 : position.floor();
}
List<String> dendrogramRows(List<Merge> merges, List<(int, int)> children, List<int> order,
    List<String> idents, List<String> labels, double maximum, List<int> cutColumns, int width) {
  final count = order.length;
  final grid = List.generate(count, (_) => List.filled(width + 1, 0));
  void mark(int row, int x, int level) { grid[row][x] = math.max(grid[row][x], level); }
  final anchor = List.filled(2 * count - 1, 0);
  for (var row = 0; row < count; row++) { anchor[order[row]] = row; }
  for (final x in cutColumns) {
    if (x <= width) for (var row = 0; row < count; row++) { mark(row, x, 1); }
  }
  final columns = merges.map((merge) => column(merge.height, maximum, width)).toList();
  for (var step = 0; step < children.length; step++) {
    final (upper, lower) = children[step];
    final x = columns[step];
    mark(anchor[upper], x, 4);
    mark(anchor[lower], x, 4);
    for (var row = anchor[upper] + 1; row < anchor[lower]; row++) { mark(row, x, 3); }
    for (final child in [upper, lower]) {
      final start = child < count ? 0 : columns[child - count] + 1;
      for (var position = start; position < x; position++) { mark(anchor[child], position, 2); }
    }
    anchor[count + step] = (anchor[upper] + anchor[lower]) ~/ 2;
  }
  final idWidth = idents.map((ident) => ident.length).reduce((a, b) => math.max(a, b));
  final labelWidth = labels.map((label) => label.length).reduce((a, b) => math.max(a, b));
  final rows = <String>[];
  for (var row = 0; row < count; row++) {
    final leaf = order[row];
    final cells = grid[row].map((level) => ' :-|+'[level]).join();
    rows.add('${idents[leaf].padRight(idWidth)} ${labels[leaf].padRight(labelWidth)} $cells'.trimRight());
  }
  final scale = List.generate(width + 1, (x) => x % 10 == 0 ? '+' : '-').join();
  rows.add('${List.filled(idWidth + labelWidth + 2, ' ').join()}$scale');
  return rows;
}
