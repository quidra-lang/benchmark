import 'dart:io';
import 'dart:math' as math;

int amount(String s) {
  final p = s.split('.');
  return int.parse(p[0]) * 100 + int.parse(p[1]);
}
String money(int c) => '${c < 0 ? '-' : ''}${c.abs() ~/ 100}.${(c.abs() % 100).toString().padLeft(2, '0')}';
String signed(int n) => '${n > 0 ? '+' : ''}$n';
String signedMoney(int n) => '${n > 0 ? '+' : ''}${money(n)}';
String margin(int profit, int revenue) {
  if (revenue == 0) return 'n/a';
  final q = profit.abs() * 1000 ~/ revenue;
  return '${profit < 0 && q > 0 ? '-' : ''}${q ~/ 10}.${q % 10}%';
}
const categories = ['received', 'returned', 'adjusted-in', 'adjusted-out', 'shipped', 'written-down', 'expired', 'recalled'];
class InventoryError implements Exception {
  final String reason;
  InventoryError(this.reason);
}
Never fail(String s) => throw InventoryError(s);
class Warehouse {
  final String code;
  final int index;
  Warehouse(this.code, this.index);
}
class CardEntry {
  final int day, quantity, value;
  final String kind;
  final Warehouse warehouse;
  CardEntry(this.day, this.kind, this.warehouse, this.quantity, this.value);
}
class Item {
  final String code;
  String name;
  int level, orderCount = 0, sold = 0, revenue = 0, cogs = 0;
  int? lastCost;
  final lots = <Lot>[];
  final card = <CardEntry>[];
  Item(this.code, this.level, this.name);
}
class Lot {
  final int number, day, initialQuantity, initialCost;
  final Item item;
  final Warehouse warehouse;
  final String kind;
  int cost, removed = 0;
  final held = List.filled(20, 0);
  Lot(this.number, this.item, this.day, this.initialQuantity, this.initialCost, this.warehouse, this.kind) : cost = initialCost;
}
class Part {
  final Lot lot;
  final int quantity, cost;
  Part(this.lot, this.quantity, this.cost);
}
class Issue {
  final List<Part> parts;
  final int cost;
  Issue(this.parts, this.cost);
}
class Order {
  final int number, day, price, ordered;
  final Warehouse warehouse;
  final Item item;
  int shipped = 0, backorder, cancelled = 0, returned = 0, revenue = 0, cogs = 0;
  final issues = <Part>[];
  Order(this.number, this.warehouse, this.item, this.day, this.price, this.ordered) : backorder = ordered;
}
class Inventory {
  int day = 1;
  final warehouses = <String, Warehouse>{};
  final items = <String, Item>{};
  final lots = <Lot>[];
  final orders = <Order>[];
  final quantities = List.filled(8, 0), values = List.filled(8, 0);
  List<Warehouse> warehouseList() => warehouses.values.toList()..sort((a, b) => a.code.compareTo(b.code));
  List<Item> itemList() => items.values.toList()..sort((a, b) => a.code.compareTo(b.code));
  Warehouse warehouse(String s) => warehouses[s] ?? fail('unknown warehouse $s');
  Item item(String s) => items[s] ?? fail('unknown item $s');
  Order order(String s) {
    final n = int.parse(s);
    if (n < 1 || n > orders.length) fail('unknown order $s');
    return orders[n - 1];
  }
  Lot lot(String s) {
    final n = int.parse(s);
    if (n < 1 || n > lots.length) fail('unknown lot $s');
    return lots[n - 1];
  }
  (int, int) stock(Item item, [Warehouse? w]) {
    var q = 0, v = 0;
    for (final lot in item.lots) {
      final held = w == null ? lot.held.fold(0, (a, b) => a + b) : lot.held[w.index];
      q += held;
      v += held * lot.cost;
    }
    return (q, v);
  }
  int backorder(Item item, [Warehouse? w]) => orders.where((o) => o.item == item && (w == null || o.warehouse == w)).fold(0, (n, o) => n + o.backorder);
  void tally(int category, int quantity, int value) {
    quantities[category] += quantity;
    values[category] += value;
  }
  void card(Item item, String kind, Warehouse w, int q, int v) => item.card.add(CardEntry(day, kind, w, q, v));
  Lot create(Item item, Warehouse w, int q, int cost, int lotDay, String kind) {
    final lot = Lot(lots.length + 1, item, lotDay, q, cost, w, kind);
    lot.held[w.index] = q;
    lots.add(lot);
    item.lots.add(lot);
    item.lots.sort((a, b) {
      final c = a.day.compareTo(b.day);
      return c != 0 ? c : a.number.compareTo(b.number);
    });
    return lot;
  }
  Issue issue(Item item, Warehouse w, int q, {bool removed = false}) {
    var cost = 0;
    final parts = <Part>[];
    for (final lot in item.lots) {
      final take = math.min(q, lot.held[w.index]);
      if (take == 0) continue;
      parts.add(Part(lot, take, lot.cost));
      lot.held[w.index] -= take;
      q -= take;
      cost += take * lot.cost;
      if (removed) lot.removed += take;
      if (q == 0) break;
    }
    return Issue(parts, cost);
  }
  void ship(Order o, int q, Issue issued) {
    o.shipped += q;
    o.backorder -= q;
    o.revenue += q * o.price;
    o.cogs += issued.cost;
    o.issues.addAll(issued.parts);
    o.item.sold += q;
    o.item.revenue += q * o.price;
    o.item.cogs += issued.cost;
    if (q > 0) tally(4, q, issued.cost);
  }
  void allocate(Warehouse w, Item item, StringBuffer out) {
    for (final o in orders) {
      if (o.warehouse != w || o.item != item || o.backorder == 0) continue;
      final q = math.min(o.backorder, stock(item, w).$1);
      if (q == 0) break;
      final issued = issue(item, w, q);
      ship(o, q, issued);
      card(item, 'fill', w, -q, -issued.cost);
      out.writeln('  FILL order ${o.number} qty $q revenue ${money(q * o.price)} cogs ${money(issued.cost)} profit ${money(q * o.price - issued.cost)} backorder ${o.backorder}');
    }
  }
  void requireQuantity(int q) {
    if (q == 0) fail('invalid quantity');
  }
  void requireStock(Item item, Warehouse w, int q) {
    final h = stock(item, w).$1;
    if (h < q) fail('insufficient stock ${w.code} ${item.code} $h');
  }
  void execute(List<String> a, StringBuffer out) {
    final op = a[0], id = a.length > 1 ? a[1] : '';
    if (op == 'DAY') {
      final d = int.parse(id);
      if (d <= day) fail('invalid day $id');
      day = d;
      out.writeln('DAY $d');
    } else if (op == 'WAREHOUSE') {
      if (warehouses.containsKey(id)) fail('duplicate warehouse $id');
      warehouses[id] = Warehouse(id, warehouses.length);
      out.writeln('WAREHOUSE $id');
    } else if (op == 'ITEM') {
      final added = !items.containsKey(id), level = int.parse(a[2]);
      final s = items.putIfAbsent(id, () => Item(id, level, a[3]));
      s.level = level;
      s.name = a[3];
      out.writeln('ITEM $id ${added ? 'added' : 'updated'} ${s.name} level $level');
    } else if (['RECEIVE', 'SHIP', 'ADJUST', 'COUNT'].contains(op)) {
      final w = warehouse(id);
      final s = item(a[2]);
      final prefix = '$op $id ${a[2]}';
      if (op == 'RECEIVE') {
        final q = int.parse(a[3]), c = amount(a[4]), d = int.parse(a[5]);
        requireQuantity(q);
        if (d > day) fail('future day ${a[5]}');
        final l = create(s, w, q, c, d, 'receive');
        s.lastCost = c;
        tally(0, q, q * c);
        card(s, 'receive', w, q, q * c);
        out.writeln('$prefix lot ${l.number} qty $q cost ${money(c)} day $d value ${money(q * c)}');
        allocate(w, s, out);
      } else if (op == 'SHIP') {
        final q = int.parse(a[3]), price = amount(a[4]);
        requireQuantity(q);
        final o = Order(orders.length + 1, w, s, day, price, q);
        orders.add(o);
        s.orderCount++;
        final f = math.min(q, stock(s, w).$1);
        final issued = issue(s, w, f);
        ship(o, f, issued);
        if (f > 0) card(s, 'ship', w, -f, -issued.cost);
        out.writeln('SHIP order ${o.number} $id ${s.code} shipped $f revenue ${money(o.revenue)} cogs ${money(o.cogs)} profit ${money(o.revenue - o.cogs)} backorder ${o.backorder}');
      } else if (op == 'ADJUST') {
        final positive = a[3][0] == '+', q = int.parse(a[3].substring(1));
        requireQuantity(q);
        if (positive) {
          final c = amount(a[4]);
          final l = create(s, w, q, c, day, 'adjust');
          tally(2, q, q * c);
          card(s, 'adjust', w, q, q * c);
          out.writeln('$prefix +$q lot ${l.number} value ${money(q * c)}');
          allocate(w, s, out);
        } else {
          requireStock(s, w, q);
          final issued = issue(s, w, q, removed: true);
          tally(3, q, issued.cost);
          card(s, 'adjust', w, -q, -issued.cost);
          out.writeln('$prefix -$q value ${money(issued.cost)}');
        }
      } else {
        final actual = int.parse(a[3]), h = stock(s, w).$1;
        if (actual == h) {
          out.writeln('$prefix qty $actual ok');
        } else if (actual < h) {
          final q = h - actual;
          final issued = issue(s, w, q, removed: true);
          tally(3, q, issued.cost);
          card(s, 'count', w, -q, -issued.cost);
          out.writeln('$prefix qty $h -> $actual shortage $q value ${money(issued.cost)}');
        } else {
          final q = actual - h, c = s.lastCost ?? 0;
          final l = create(s, w, q, c, day, 'count');
          tally(2, q, q * c);
          card(s, 'count', w, q, q * c);
          out.writeln('$prefix qty $h -> $actual surplus $q lot ${l.number} value ${money(q * c)}');
          allocate(w, s, out);
        }
      }
    } else if (op == 'CANCEL') {
      final o = order(id);
      if (o.backorder == 0) fail('no backorder $id');
      final q = o.backorder;
      o.cancelled += q;
      o.backorder = 0;
      out.writeln('CANCEL order ${o.number} qty $q');
    } else if (op == 'TRANSFER') {
      final from = warehouse(id);
      final to = warehouse(a[2]);
      if (from == to) fail('same warehouse $id');
      final s = item(a[3]), q = int.parse(a[4]);
      requireQuantity(q);
      requireStock(s, from, q);
      final issued = issue(s, from, q);
      for (final p in issued.parts) p.lot.held[to.index] += p.quantity;
      card(s, 'transfer-out', from, -q, -issued.cost);
      card(s, 'transfer-in', to, q, issued.cost);
      out.writeln('TRANSFER $id -> ${to.code} ${s.code} qty $q value ${money(issued.cost)} lots ${issued.parts.length}');
      allocate(to, s, out);
    } else if (op == 'RETURN') {
      final o = order(id), q = int.parse(a[2]);
      requireQuantity(q);
      if (q > o.shipped - o.returned) fail('return exceeds shipped $id ${o.shipped - o.returned}');
      final c = amount(a[3]);
      final l = create(o.item, o.warehouse, q, c, day, 'return');
      o.returned += q;
      o.revenue -= q * o.price;
      o.cogs -= q * c;
      o.item.sold -= q;
      o.item.revenue -= q * o.price;
      o.item.cogs -= q * c;
      tally(1, q, q * c);
      card(o.item, 'return', o.warehouse, q, q * c);
      out.writeln('RETURN order ${o.number} ${o.warehouse.code} ${o.item.code} qty $q lot ${l.number} refund ${money(q * o.price)} value ${money(q * c)}');
      allocate(o.warehouse, o.item, out);
    } else if (op == 'MARKET') {
      final s = item(id), price = amount(a[2]);
      var changed = 0, q = 0, loss = 0;
      for (final w in warehouseList()) {
        var warehouseLoss = 0;
        for (final l in s.lots) {
          if (l.cost <= price || l.held[w.index] == 0) continue;
          final h = l.held[w.index], value = h * (l.cost - price);
          changed++;
          q += h;
          loss += value;
          warehouseLoss += value;
        }
        if (warehouseLoss > 0) card(s, 'writedown', w, 0, -warehouseLoss);
      }
      for (final l in s.lots) if (l.cost > price && l.held.any((q) => q > 0)) l.cost = price;
      tally(5, q, loss);
      out.writeln('MARKET $id price ${money(price)} lots $changed qty $q loss ${money(loss)}');
    } else if (op == 'RECALL') {
      final l = lot(id), held = warehouseList().where((w) => l.held[w.index] > 0).toList();
      if (held.isEmpty) fail('nothing to recall $id');
      final q = held.fold(0, (s, w) => s + l.held[w.index]);
      out.writeln('RECALL lot ${l.number} ${l.item.code} qty $q value ${money(q * l.cost)}');
      for (final w in held) {
        final h = l.held[w.index];
        card(l.item, 'recall', w, -h, -h * l.cost);
        out.writeln('  ${w.code} qty $h value ${money(h * l.cost)}');
        l.held[w.index] = 0;
      }
      l.removed += q;
      tally(7, q, q * l.cost);
    } else if (op == 'EXPIRE') {
      final age = int.parse(id);
      var totalQ = 0, totalV = 0;
      out.writeln('EXPIRE $age');
      final ws = warehouseList();
      for (final s in itemList()) {
        for (final w in ws) {
          var count = 0, q = 0, value = 0;
          for (final l in s.lots) {
            if (l.held[w.index] == 0 || day - l.day <= age) continue;
            final h = l.held[w.index];
            count++;
            q += h;
            value += h * l.cost;
            l.removed += h;
            l.held[w.index] = 0;
          }
          if (count > 0) {
            tally(6, q, value);
            card(s, 'expire', w, -q, -value);
            totalQ += q;
            totalV += value;
            out.writeln('  ${s.code} ${w.code} lots $count qty $q value ${money(value)}');
          }
        }
      }
      out.writeln('  total qty $totalQ value ${money(totalV)}');
    } else if (op == 'VALUE' || op == 'AGING') {
      final w = a.length > 1 ? warehouse(id) : null;
      final ws = warehouseList();
      if (op == 'VALUE') {
        out.writeln('VALUE${w == null ? '' : ' ${w.code}'}');
        var totalQ = 0, totalV = 0;
        for (final s in itemList()) {
          final (q, value) = stock(s, w);
          if (q == 0) continue;
          out.writeln('  ${s.code} qty $q value ${money(value)} avg ${money(value ~/ q)}');
          totalQ += q;
          totalV += value;
          if (w == null) {
            for (final wh in ws) {
              final h = stock(s, wh);
              if (h.$1 > 0) out.writeln('    ${wh.code} qty ${h.$1} value ${money(h.$2)}');
            }
          }
        }
        out.writeln('  total qty $totalQ value ${money(totalV)}');
      } else {
        out.writeln('AGING${w == null ? '' : ' ${w.code}'} day $day');
        final totalQ = List.filled(4, 0), totalV = List.filled(4, 0);
        const labels = ['0-30', '31-60', '61-90', '91+'];
        for (final s in itemList()) {
          final qs = List.filled(4, 0);
          for (final l in s.lots) {
            final h = w == null ? l.held.fold(0, (a, b) => a + b) : l.held[w.index];
            final age = day - l.day;
            final bucket = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3;
            qs[bucket] += h;
            totalQ[bucket] += h;
            totalV[bucket] += h * l.cost;
          }
          if (qs.any((q) => q > 0)) out.writeln('  ${s.code} ${List.generate(4, (k) => '${labels[k]} ${qs[k]}').join(' ')}');
        }
        out.writeln('  total ${List.generate(4, (k) => '${labels[k]} ${totalQ[k]}').join(' ')}');
        out.writeln('  value ${List.generate(4, (k) => '${labels[k]} ${money(totalV[k])}').join(' ')}');
      }
    } else if (op == 'LOTS') {
      final w = warehouse(id);
      final s = item(a[2]);
      var count = 0;
      out.writeln('LOTS $id ${s.code}');
      for (final l in s.lots)
        if (l.held[w.index] > 0) {
          final q = l.held[w.index];
          count++;
          out.writeln('  lot ${l.number} day ${l.day} qty $q cost ${money(l.cost)} value ${money(q * l.cost)} age ${day - l.day}');
        }
      for (final o in orders)
        if (o.warehouse == w && o.item == s && o.backorder > 0) {
          count++;
          out.writeln('  backorder order ${o.number} qty ${o.backorder}');
        }
      if (count == 0) out.writeln('  (none)');
    } else if (op == 'REORDER' || op == 'ITEMS') {
      out.writeln(op);
      var count = 0;
      for (final s in itemList()) {
        final h = stock(s).$1, b = backorder(s);
        if (op == 'REORDER') {
          if (h - b > s.level) continue;
          out.writeln('  ${s.code} ${s.name} onhand $h backorder $b level ${s.level}');
        } else {
          out.writeln('  ${s.code} ${s.name} level ${s.level} onhand $h backorder $b cost ${s.lastCost == null ? 'none' : money(s.lastCost!)}');
        }
        count++;
      }
      if (count == 0) out.writeln('  (none)');
    } else if (op == 'MARGIN' || op == 'TOP') {
      final selected = itemList().where((s) => s.orderCount > 0).toList();
      if (op == 'MARGIN') {
        out.writeln('MARGIN');
        var sold = 0, revenue = 0, cogs = 0;
        for (final s in selected) {
          out.writeln('  ${s.code} sold ${s.sold} revenue ${money(s.revenue)} cogs ${money(s.cogs)} profit ${money(s.revenue - s.cogs)} margin ${margin(s.revenue - s.cogs, s.revenue)}');
          sold += s.sold;
          revenue += s.revenue;
          cogs += s.cogs;
        }
        out.writeln('  total sold $sold revenue ${money(revenue)} cogs ${money(cogs)} profit ${money(revenue - cogs)} margin ${margin(revenue - cogs, revenue)}');
      } else {
        final k = int.parse(id);
        selected.sort((a, b) {
          var c = (b.revenue - b.cogs).compareTo(a.revenue - a.cogs);
          if (c == 0) c = b.revenue.compareTo(a.revenue);
          return c != 0 ? c : a.code.compareTo(b.code);
        });
        out.writeln('TOP $k');
        for (var i = 0; i < math.min(k, selected.length); i++) {
          final s = selected[i];
          out.writeln('  ${i + 1} ${s.code} profit ${money(s.revenue - s.cogs)} revenue ${money(s.revenue)} margin ${margin(s.revenue - s.cogs, s.revenue)}');
        }
        if (selected.isEmpty) out.writeln('  (none)');
      }
    } else if (op == 'BACKORDERS') {
      out.writeln('BACKORDERS');
      var count = 0;
      for (final o in orders)
        if (o.backorder > 0) {
          count++;
          out.writeln('  order ${o.number} ${o.warehouse.code} ${o.item.code} qty ${o.backorder} day ${o.day} price ${money(o.price)}');
        }
      if (count == 0) out.writeln('  (none)');
    } else if (op == 'ORDER') {
      final o = order(id);
      out.writeln('ORDER ${o.number} ${o.warehouse.code} ${o.item.code} day ${o.day} price ${money(o.price)}');
      out.writeln('  ordered ${o.ordered} shipped ${o.shipped} backorder ${o.backorder} cancelled ${o.cancelled} returned ${o.returned}');
      for (final p in o.issues) out.writeln('  lot ${p.lot.number} qty ${p.quantity} cost ${money(p.cost)}');
      out.writeln('  revenue ${money(o.revenue)} cogs ${money(o.cogs)} profit ${money(o.revenue - o.cogs)}');
    } else if (op == 'TRACE') {
      final l = lot(id);
      out.writeln('TRACE lot ${l.number} ${l.item.code} ${l.kind} ${l.warehouse.code} day ${l.day} qty ${l.initialQuantity} cost ${money(l.initialCost)}');
      for (final w in warehouseList()) if (l.held[w.index] > 0) out.writeln('  held ${w.code} qty ${l.held[w.index]} cost ${money(l.cost)}');
      for (final o in orders) {
        final q = o.issues.where((p) => p.lot == l).fold(0, (s, p) => s + p.quantity);
        if (q > 0) out.writeln('  order ${o.number} qty $q');
      }
      if (l.removed > 0) out.writeln('  removed qty ${l.removed}');
    } else if (op == 'CARD') {
      final s = item(id);
      out.writeln('CARD $id ${s.name}');
      var q = 0, value = 0;
      for (final e in s.card) {
        q += e.quantity;
        value += e.value;
        out.writeln('  day ${e.day} ${e.kind} ${e.warehouse.code} ${signed(e.quantity)} ${signedMoney(e.value)} balance $q ${money(value)}');
      }
      if (s.card.isEmpty) out.writeln('  (none)');
    } else if (op == 'STATUS') {
      out.writeln('STATUS');
      for (final w in warehouseList()) {
        var skus = 0, q = 0, value = 0, b = 0;
        for (final s in items.values) {
          final h = stock(s, w);
          if (h.$1 > 0) skus++;
          q += h.$1;
          value += h.$2;
        }
        for (final o in orders) if (o.warehouse == w) b += o.backorder;
        out.writeln('  ${w.code} skus $skus qty $q value ${money(value)} backorder $b');
      }
      if (warehouses.isEmpty) out.writeln('  (none)');
    } else if (op == 'SUMMARY') {
      out.writeln('SUMMARY');
      for (var i = 0; i < 8; i++) out.writeln('  ${categories[i]} qty ${quantities[i]} value ${money(values[i])}');
      var q = 0, value = 0, open = 0, b = 0;
      for (final s in items.values) {
        final h = stock(s);
        q += h.$1;
        value += h.$2;
      }
      for (final o in orders) {
        if (o.backorder > 0) open++;
        b += o.backorder;
      }
      out.writeln('  on-hand qty $q value ${money(value)}');
      out.writeln('  orders ${orders.length} open $open backorder $b');
    }
  }
}
void main() {
  final inventory = Inventory(), n = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < n; i++) {
    final draft = StringBuffer(), a = stdin.readLineSync()!.split(' ');
    try {
      inventory.execute(a, draft);
      stdout.write(draft);
    } on InventoryError catch (e) {
      print('ERROR ${e.reason}');
    }
  }
}
