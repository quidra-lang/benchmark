import 'dart:math';
import 'items.dart';

class BomRow {
  final String parent, child;
  final int quantity, scrap;
  BomRow(List<String> fields) : parent = fields[0], child = fields[1], quantity = int.parse(fields[2]), scrap = int.parse(fields[3]);
}

int need(BomRow row, int quantity) => (quantity * row.quantity * (100 + row.scrap) + 99) ~/ 100;

class Bom {
  final Map<String, List<BomRow>> children, parents;
  Bom(Map<String, Item> items) : children = {for (final id in items.keys) id: []}, parents = {for (final id in items.keys) id: []};
  bool manufactured(String id) => children[id]!.isNotEmpty;
  List<String>? path(String id, String target, Set<String> visited) {
    if (id == target) return [id];
    visited.add(id);
    for (final row in children[id]!) {
      if (visited.contains(row.child)) continue;
      final rest = path(row.child, target, visited);
      if (rest != null) return [id, ...rest];
    }
    return null;
  }
  int code(String id, Map<String, int> codes) {
    if (codes.containsKey(id)) return codes[id]!;
    var value = 0;
    for (final row in parents[id]!) { value = max(value, code(row.parent, codes) + 1); }
    return codes[id] = value;
  }
  int cumulative(String id, Map<String, Item> items, Map<String, int> times) {
    if (times.containsKey(id)) return times[id]!;
    var longest = 0;
    for (final row in children[id]!) { longest = max(longest, cumulative(row.child, items, times)); }
    return times[id] = items[id]!.lead + longest;
  }
}

Bom readBom(Map<String, Item> items, List<String> errors) {
  final bom = Bom(items);
  for (final source in readRows('bom.csv')) {
    final row = BomRow(source.fields), parent = row.parent, child = row.child;
    String? reason;
    if (!items.containsKey(parent)) { reason = 'unknown item $parent'; }
    else if (!items.containsKey(child)) { reason = 'unknown item $child'; }
    else if (row.quantity < 1) { reason = 'bad quantity ${row.quantity}'; }
    else if (row.scrap > 50) { reason = 'bad scrap ${row.scrap}'; }
    else if (parent == child) { reason = 'cycle $parent -> $parent'; }
    else if (bom.children[parent]!.any((other) => other.child == child)) { reason = 'duplicate $parent -> $child'; }
    else {
      final path = bom.path(child, parent, {});
      if (path != null) reason = 'cycle $parent -> ${path.join(' -> ')}';
    }
    if (reason != null) { errors.add('bom.csv line ${source.line}: $reason'); continue; }
    bom.children[parent]!.add(row); bom.parents[child]!.add(row);
    bom.children[parent]!.sort((a, b) => a.child.compareTo(b.child));
    bom.parents[child]!.sort((a, b) => a.parent.compareTo(b.parent));
  }
  return bom;
}
