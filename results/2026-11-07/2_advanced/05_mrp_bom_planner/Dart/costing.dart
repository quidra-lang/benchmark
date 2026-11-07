import 'items.dart';
import 'bom.dart';

typedef Cost = ({int material, int labor, int total});

Map<String, Cost> standardCosts(Map<String, Item> items, Bom bom, List<String> order) {
  final costs = <String, Cost>{};
  for (final id in order.reversed) {
    var material = items[id]!.material, labor = items[id]!.labor;
    for (final row in bom.children[id]!) {
      final factor = row.quantity * (100 + row.scrap), child = costs[row.child]!;
      material += (factor * child.material + 50) ~/ 100; labor += (factor * child.labor + 50) ~/ 100;
    }
    costs[id] = (material: material, labor: labor, total: material + labor);
  }
  return costs;
}

Map<String, String> abcClasses(Map<String, int> values) {
  final ids = values.keys.toList()..sort((a, b) { final comparison = values[b]!.compareTo(values[a]!); return comparison != 0 ? comparison : a.compareTo(b); });
  final total = values.values.fold(0, (a, b) => a + b); var before = 0;
  final classes = <String, String>{};
  for (final id in ids) {
    final value = values[id]!; classes[id] = value == 0 ? 'C' : 100 * before < 80 * total ? 'A' : 100 * before < 95 * total ? 'B' : 'C'; before += value;
  }
  return classes;
}
