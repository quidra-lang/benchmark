import 'dart:math';
import 'items.dart';

int smallestMultiple(int quantity, int factor) => (quantity + factor - 1) ~/ factor * factor;

int lotSize(Item item, int week, int projected, List<int> receipts, List<int> gross, int horizon) {
  final net = item.safety - projected;
  if (item.rule == 'LFL') return net;
  if (item.rule == 'FOQ') return smallestMultiple(net, item.lot[0]);
  if (item.rule == 'MIN') return smallestMultiple(max(net, item.lot[0]), item.lot[1]);
  var quantity = net;
  for (var later = week + 1; later <= min(week + item.lot[0] - 1, horizon); later++) {
    projected += receipts[later] - gross[later]; quantity = max(quantity, item.safety - projected);
  }
  return quantity;
}
