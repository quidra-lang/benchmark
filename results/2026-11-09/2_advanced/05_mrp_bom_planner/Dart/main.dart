import 'dart:io';
import 'dart:math';
import 'items.dart';
import 'bom.dart';
import 'lot_sizing.dart';
import 'capacity.dart';
import 'costing.dart';
import 'report.dart';

const demandKinds = ['MPS', 'ORDER', 'DEPENDENT'];
const rootKinds = ['MPS', 'ORDER', 'SAFETY'];
const supplyKinds = ['STOCK', 'RECEIPT', 'ORDER'];
const messageKinds = ['BELOW_SAFETY', 'PAST_DUE', 'RELEASE', 'EXPEDITE', 'DEFER', 'CANCEL', 'NO_ROUTING', 'NO_DEMAND', 'OVERLOAD'];
List<String> sortedIds(Map<String, Object?> map) => map.keys.toList()..sort();
int total(Iterable<int> values) => values.fold(0, (a, b) => a + b);

class ScheduleRow {
  final String item;
  final int week, quantity, line;
  ScheduleRow(List<String> f, this.line) : item = f[0], week = int.parse(f[1]), quantity = int.parse(f[2]);
}

class Inquiry {
  final String id, item;
  final int quantity, week, line;
  Inquiry(List<String> f, this.line) : id = f[0], item = f[1], quantity = int.parse(f[2]), week = int.parse(f[3]);
}

class Demand {
  final String item, kind, orderId, parent;
  final int week, quantity, line, parentNumber;
  Demand(this.item, this.kind, this.week, this.quantity, {this.orderId = '', this.line = 0, this.parent = '', this.parentNumber = 0});
  String get text => switch (kind) {
    'SAFETY' => 'SAFETY $item',
    'MPS' => 'MPS $item week $week',
    'ORDER' => 'ORDER $orderId $item week $week',
    _ => '$parent order $parentNumber week $week'
  };
  String get rootKey => '$item\x00$kind\x00$week\x00$orderId';
}

int compareDemands(Demand a, Demand b) {
  for (final comparison in [a.week.compareTo(b.week), demandKinds.indexOf(a.kind).compareTo(demandKinds.indexOf(b.kind)), a.line.compareTo(b.line), a.parent.compareTo(b.parent), a.parentNumber.compareTo(b.parentNumber)]) {
    if (comparison != 0) return comparison;
  }
  return 0;
}

int compareRoots(Demand a, Demand b) {
  for (final comparison in [a.item.compareTo(b.item), rootKinds.indexOf(a.kind).compareTo(rootKinds.indexOf(b.kind)), a.week.compareTo(b.week), a.orderId.compareTo(b.orderId)]) {
    if (comparison != 0) return comparison;
  }
  return 0;
}

class PlannedOrder {
  final String item;
  final int number, receipt, quantity, originalRelease, release;
  PlannedOrder(this.item, this.number, this.receipt, this.quantity, int lead) : originalRelease = receipt - lead, release = max(1, receipt - lead);
}

class Supply {
  final String kind;
  final int week, quantity, line;
  final PlannedOrder? order;
  int remaining;
  final List<(Demand, int)> allocations = [];
  List<Demand> roots = [];
  Supply(this.kind, this.week, this.quantity, {this.line = 0, this.order}) : remaining = quantity;
  String get header {
    if (kind == 'STOCK') return 'STOCK quantity $quantity';
    if (kind == 'RECEIPT') return 'RECEIPT line $line week $week quantity $quantity';
    final o = order!; return 'ORDER ${o.number} receipt ${o.receipt} release ${o.release} quantity ${o.quantity}';
  }
  bool serves(String id) => roots.any((root) => root.kind == 'ORDER' && root.orderId == id);
}

class ItemPlan {
  final Item item;
  final List<int> receipts, gross, onHand, net, plannedReceipts, plannedReleases;
  final List<Demand> demands = [];
  final List<PlannedOrder> orders = [];
  List<Supply> supplies = [], orderSupplies = [];
  ItemPlan(this.item, int horizon, this.receipts)
      : gross = List.filled(horizon + 1, 0), onHand = List.filled(horizon + 1, 0), net = List.filled(horizon + 1, 0),
        plannedReceipts = List.filled(horizon + 1, 0), plannedReleases = List.filled(horizon + 1, 0) { onHand[0] = item.onHand; }
  int get pastDue => total(orders.where((o) => o.originalRelease < 1).map((o) => o.quantity));
}

class Plan {
  final Map<String, ItemPlan> items;
  final Map<String, List<int>> loads, overloads;
  Plan(this.items, this.loads, Map<String, WorkCenter> centers) : overloads = {
    for (final entry in loads.entries) entry.key: entry.value.map((load) => max(0, load - centers[entry.key]!.available)).toList()
  };
}

class Promise {
  final Inquiry inquiry;
  int week = 0, materialWeek = 0;
  String reason = '';
  Promise(this.inquiry);
  String get status => week == 0 ? 'rejected' : week == inquiry.week ? 'on_time' : 'late';
}

String? scheduleError(String item, int week, int quantity, Map<String, Item> items, int horizon) {
  if (!items.containsKey(item)) return 'unknown item $item';
  if (week < 1 || week > horizon) return 'week $week outside horizon';
  if (quantity < 1) return 'bad quantity $quantity';
  return null;
}

List<ScheduleRow> readSchedule(String name, Map<String, Item> items, int horizon, List<String> errors, bool unique) {
  final rows = <ScheduleRow>[], seen = <String>{};
  for (final source in readRows(name)) {
    final row = ScheduleRow(source.fields, source.line), key = '${source.fields[0]}\x00${source.fields[1]}';
    var reason = scheduleError(row.item, row.week, row.quantity, items, horizon);
    if (reason == null && unique && seen.contains(key)) reason = 'duplicate ${row.item} week ${row.week}';
    if (reason != null) { errors.add('$name line ${row.line}: $reason'); } else { rows.add(row); seen.add(key); }
  }
  return rows;
}

class PlanningData {
  final List<String> errors = [], peg = [];
  final Map<String, int> codes = {}, cumulative = {};
  final List<Inquiry> inquiries = [];
  final List<Demand> mps = [];
  late final Map<String, Item> items;
  late final Bom bom;
  late final Map<String, WorkCenter> centers;
  late final Map<String, List<Operation>> routings;
  late final List<String> order, centerOrder;
  late final List<int> weeks;
  late final Map<String, List<ScheduleRow>> receipts;
  late final Map<String, List<int>> scheduled;
  int horizon = 0, treeQuantity = 0;
  PlanningData() {
    for (final line in File('input/params.txt').readAsLinesSync()) {
      final words = line.split(' ');
      switch (words[0]) {
        case 'horizon': horizon = int.parse(words[1]);
        case 'peg': peg.addAll(words.skip(1));
        case 'tree_quantity': treeQuantity = int.parse(words[1]);
      }
    }
    items = readItems(errors); bom = readBom(items, errors); centers = readCenters(errors); routings = readRoutings(items, centers, bom, errors);
    final mpsRows = readSchedule('mps.csv', items, horizon, errors, true);
    final receiptRows = readSchedule('receipts.csv', items, horizon, errors, false), seen = <String>{};
    for (final row in readRows('orders.csv')) {
      final inquiry = Inquiry(row.fields, row.line);
      final reason = seen.contains(inquiry.id) ? 'duplicate order ${inquiry.id}' : scheduleError(inquiry.item, inquiry.week, inquiry.quantity, items, horizon);
      if (reason != null) { errors.add('orders.csv line ${row.line}: $reason'); } else { inquiries.add(inquiry); seen.add(inquiry.id); }
    }
    for (final row in mpsRows) { mps.add(Demand(row.item, 'MPS', row.week, row.quantity)); }
    for (final id in items.keys) { bom.code(id, codes); bom.cumulative(id, items, cumulative); }
    order = sortedIds(items)..sort((a, b) { final comparison = codes[a]!.compareTo(codes[b]!); return comparison != 0 ? comparison : a.compareTo(b); });
    centerOrder = sortedIds(centers); weeks = List.generate(horizon, (i) => i + 1);
    receipts = {for (final id in items.keys) id: []}; scheduled = {for (final id in items.keys) id: List.filled(horizon + 1, 0)};
    receiptRows.sort((a, b) { final comparison = a.week.compareTo(b.week); return comparison != 0 ? comparison : a.line.compareTo(b.line); });
    for (final row in receiptRows) { receipts[row.item]!.add(row); scheduled[row.item]![row.week] += row.quantity; }
  }
}

Plan runMrp(PlanningData data, List<Demand> orders) {
  final plans = {for (final id in data.order) id: ItemPlan(data.items[id]!, data.horizon, data.scheduled[id]!)};
  for (final demand in [...data.mps, ...orders]) { plans[demand.item]!.demands.add(demand); }
  for (final id in data.order) {
    final plan = plans[id]!, item = plan.item;
    for (final demand in plan.demands) { plan.gross[demand.week] += demand.quantity; }
    var projected = item.onHand;
    for (final week in data.weeks) {
      projected += plan.receipts[week] - plan.gross[week];
      if (projected < item.safety) {
        final quantity = lotSize(item, week, projected, plan.receipts, plan.gross, data.horizon);
        final order = PlannedOrder(id, plan.orders.length + 1, week, quantity, item.lead); plan.orders.add(order);
        plan.net[week] = item.safety - projected; plan.plannedReceipts[week] = quantity; plan.plannedReleases[order.release] += quantity; projected += quantity;
      }
      plan.onHand[week] = projected;
    }
    for (final order in plan.orders) {
      for (final row in data.bom.children[id]!) { plans[row.child]!.demands.add(Demand(row.child, 'DEPENDENT', order.release, need(row, order.quantity), parent: id, parentNumber: order.number)); }
    }
  }
  final loads = {for (final id in data.centers.keys) id: List.filled(data.horizon + 1, 0)};
  for (final entry in data.routings.entries) {
    for (final order in plans[entry.key]!.orders) {
      for (final (index, op) in entry.value.indexed) { loads[op.center]![operationWeek(order.receipt, data.items[entry.key]!.lead, index, entry.value.length)] += op.minutes(order.quantity); }
    }
  }
  return Plan(plans, loads, data.centers);
}

({List<Promise> promises, Plan finalPlan}) promiseInquiries(PlanningData data, Plan base) {
  var current = base;
  final promised = <Demand>[], promises = <Promise>[];
  for (final inquiry in data.inquiries) {
    final promise = Promise(inquiry);
    for (var week = inquiry.week; week <= data.horizon; week++) {
      final demand = Demand(inquiry.item, 'ORDER', week, inquiry.quantity, orderId: inquiry.id, line: inquiry.line);
      final trial = runMrp(data, [...promised, demand]); String? reason;
      for (final id in data.order) { if (trial.items[id]!.pastDue > current.items[id]!.pastDue) { reason = id; break; } }
      if (reason == null) {
        if (promise.materialWeek == 0) promise.materialWeek = week;
        capacity: for (final id in data.centerOrder) {
          for (final w in data.weeks) { if (trial.overloads[id]![w] > current.overloads[id]![w]) { reason = '$id week $w'; break capacity; } }
        }
      }
      if (reason == null) { promise.week = week; promised.add(demand); current = trial; break; }
      if (week == inquiry.week) promise.reason = reason;
    }
    promises.add(promise);
  }
  return (promises: promises, finalPlan: current);
}

Supply parentSupply(Plan plan, Demand demand) => plan.items[demand.parent]!.orderSupplies[demand.parentNumber - 1];

void pegPlan(PlanningData data, Plan plan) {
  for (final id in data.order) {
    final p = plan.items[id]!, item = p.item, demands = [...p.demands]..sort(compareDemands);
    if (item.safety > 0) demands.insert(0, Demand(id, 'SAFETY', 0, item.safety));
    final supplies = <Supply>[];
    if (item.onHand > 0) supplies.add(Supply('STOCK', 0, item.onHand));
    for (final receipt in data.receipts[id]!) { supplies.add(Supply('RECEIPT', receipt.week, receipt.quantity, line: receipt.line)); }
    for (final order in p.orders) { supplies.add(Supply('ORDER', order.receipt, order.quantity, order: order)); }
    supplies.sort((a, b) {
      for (final comparison in [a.week.compareTo(b.week), supplyKinds.indexOf(a.kind).compareTo(supplyKinds.indexOf(b.kind)), a.line.compareTo(b.line)]) { if (comparison != 0) return comparison; }
      return 0;
    });
    var index = 0;
    for (final demand in demands) {
      var remaining = demand.quantity;
      while (remaining > 0) {
        while (supplies[index].remaining == 0) { index++; }
        final supply = supplies[index], share = min(remaining, supply.remaining);
        supply.allocations.add((demand, share)); supply.remaining -= share; remaining -= share;
      }
    }
    p.supplies = supplies; p.orderSupplies = supplies.where((s) => s.kind == 'ORDER').toList();
    for (final supply in p.orderSupplies) {
      final roots = <String, Demand>{};
      for (final (demand, _) in supply.allocations) {
        for (final root in demand.kind == 'DEPENDENT' ? parentSupply(plan, demand).roots : [demand]) { roots[root.rootKey] = root; }
      }
      supply.roots = roots.values.toList()..sort(compareRoots);
    }
  }
}

String depthLabel(int depth) => '${'.' * depth}$depth';

List<String> gridLines(PlanningData data, Plan plan) {
  final lines = <String>[];
  for (final id in data.order) {
    final p = plan.items[id]!, item = p.item;
    lines.add('ITEM $id LLC ${data.codes[id]} LT ${item.lead} LOT ${item.lotLabel} SS ${item.safety} OH ${item.onHand} ${item.description}');
    lines.add(tableRow('WEEK', data.weeks, 6));
    for (final entry in {'GROSS': p.gross, 'RECEIPTS': p.receipts, 'ON_HAND': p.onHand, 'NET': p.net, 'PLAN_RCPT': p.plannedReceipts, 'PLAN_REL': p.plannedReleases}.entries) {
      lines.add(tableRow(entry.key, entry.value.skip(1), 6));
    }
    lines.add('TOTAL gross ${total(p.gross)} receipts ${total(p.receipts)} planned ${total(p.plannedReceipts)} orders ${p.orders.length} ending ${p.onHand[data.horizon]}');
  }
  return lines;
}

void whereUsed(Bom bom, String id, int depth, int extension, List<String> lines) {
  for (final row in bom.parents[id]!) {
    final next = extension * row.quantity;
    lines.add('${depthLabel(depth)} ${row.parent} qty ${row.quantity} ext $next'); whereUsed(bom, row.parent, depth + 1, next, lines);
  }
}

void allocationLines(Plan plan, Supply supply, int depth, List<String> lines) {
  for (final (demand, share) in supply.allocations) {
    lines.add('${' ' * (2 * depth)}ALLOC $share ${demand.text}');
    if (supply.kind == 'ORDER' && demand.kind == 'DEPENDENT') allocationLines(plan, parentSupply(plan, demand), depth + 1, lines);
  }
}

List<String> peggingLines(PlanningData data, Plan plan) {
  final lines = <String>[];
  for (final id in data.peg) {
    final p = plan.items[id]!; lines.add('PEG $id orders ${p.orders.length}'); whereUsed(data.bom, id, 1, 1, lines);
    for (final kind in supplyKinds) {
      for (final supply in p.supplies.where((s) => s.kind == kind)) {
        lines.add(supply.header); allocationLines(plan, supply, 1, lines);
        if (supply.remaining > 0) lines.add('  EXCESS ${supply.remaining}');
        for (final root in supply.roots) { lines.add('  ROOT ${root.text}'); }
      }
    }
  }
  return lines;
}

void explodeLines(PlanningData data, String id, int gross, int extension, int depth, List<String> lines, Map<String, int> totals) {
  for (final row in data.bom.children[id]!) {
    final child = data.items[row.child]!, next = extension * row.quantity, quantity = need(row, gross);
    totals[row.child] = (totals[row.child] ?? 0) + quantity;
    lines.add('${depthLabel(depth)} ${row.child} qty ${row.quantity} scrap ${row.scrap} ext $next gross $quantity lt ${child.lead} cum ${data.cumulative[row.child]} ${child.description}');
    explodeLines(data, row.child, quantity, next, depth + 1, lines, totals);
  }
}

List<String> bomTreeLines(PlanningData data) {
  final lines = <String>[];
  for (final id in sortedIds(data.items)) {
    if (!data.bom.manufactured(id) || data.bom.parents[id]!.isNotEmpty) continue;
    final item = data.items[id]!;
    lines.add('TREE $id quantity ${data.treeQuantity}'); lines.add('0 $id ext 1 gross ${data.treeQuantity} lt ${item.lead} cum ${data.cumulative[id]} ${item.description}');
    final totals = <String, int>{}; explodeLines(data, id, data.treeQuantity, 1, 1, lines, totals);
    for (final child in sortedIds(totals)) { lines.add('SUM $child ${totals[child]}'); }
    final path = [id]; var current = id;
    while (data.bom.manufactured(current)) {
      var best = data.bom.children[current]!.first;
      for (final row in data.bom.children[current]!) { if (data.cumulative[row.child]! > data.cumulative[best.child]!) best = row; }
      current = best.child; path.add(current);
    }
    lines.add('CRITICAL ${path.join(' -> ')} cum ${data.cumulative[id]}');
  }
  return lines;
}

List<String> costLines(PlanningData data, Plan plan, Map<String, Cost> costs) {
  final usage = {for (final id in data.items.keys) id: total(plan.items[id]!.gross)};
  final values = {for (final id in data.items.keys) id: usage[id]! * costs[id]!.total}, lines = ['item,material,labor,total,usage,value,class'];
  final classes = abcClasses(values);
  for (final id in sortedIds(data.items)) {
    final cost = costs[id]!; lines.add('$id,${money(cost.material)},${money(cost.labor)},${money(cost.total)},${usage[id]},${money(values[id]!)},${classes[id]}');
  }
  return lines;
}

List<String> exceptionLines(PlanningData data, Plan plan) {
  final messages = <String>[];
  for (final id in data.order) {
    final p = plan.items[id]!, item = p.item;
    if (item.onHand < item.safety) messages.add('BELOW_SAFETY $id on hand ${item.onHand} safety ${item.safety}');
    for (final order in p.orders) {
      if (order.originalRelease < 1) { messages.add('PAST_DUE $id order ${order.number} receipt ${order.receipt} release ${order.originalRelease} late ${1 - order.originalRelease} quantity ${order.quantity}'); }
      else if (order.originalRelease == 1) { messages.add('RELEASE $id order ${order.number} receipt ${order.receipt} quantity ${order.quantity}'); }
    }
    final balances = <int, int>{}; var balance = item.onHand;
    for (final week in data.weeks) { balance -= p.gross[week]; balances[week] = balance; }
    var covered = 0;
    for (final receipt in data.receipts[id]!) {
      var needed = 0;
      for (final week in data.weeks) { if (balances[week]! + covered < item.safety) { needed = week; break; } }
      final text = '$id receipt line ${receipt.line} week ${receipt.week} quantity ${receipt.quantity}';
      if (needed == 0) { messages.add('CANCEL $text'); }
      else if (needed < receipt.week) { messages.add('EXPEDITE $text to $needed'); }
      else if (needed > receipt.week) { messages.add('DEFER $text to $needed'); }
      covered += receipt.quantity;
    }
    if (data.bom.manufactured(id) && !data.routings.containsKey(id)) messages.add('NO_ROUTING $id');
    if (total(p.gross) == 0 && item.onHand > 0) messages.add('NO_DEMAND $id on hand ${item.onHand}');
  }
  for (final id in data.centerOrder) {
    for (final week in data.weeks) { if (plan.overloads[id]![week] > 0) messages.add('OVERLOAD $id week $week load ${plan.loads[id]![week]} available ${data.centers[id]!.available}'); }
  }
  final counts = {for (final kind in messageKinds) kind: 0};
  for (final message in messages) { final kind = message.split(' ').first; counts[kind] = counts[kind]! + 1; }
  final summary = ['SUMMARY errors ${data.errors.length}', for (final entry in counts.entries) '${entry.key.toLowerCase()} ${entry.value}'].join(' ');
  return [...data.errors.map((error) => 'ERROR $error'), ...messages, summary];
}

List<String> capacityLines(PlanningData data, Plan plan) {
  final lines = <String>[], totals = <String, int>{};
  for (final id in data.centerOrder) {
    final center = data.centers[id]!, loads = plan.loads[id]!.sublist(1), overloads = plan.overloads[id]!.sublist(1), leveled = levelLoads(plan.loads[id]!, center.available);
    final loadTotal = totals[id] = total(loads), capacity = center.available * data.horizon;
    final peak = loadTotal > 0 ? loads.indexOf(loads.reduce(max)) + 1 : 0, overloaded = overloads.where((v) => v > 0).length, backlog = max(0, leveled[1] - center.available);
    lines.add('CENTER $id minutes ${center.minutes} efficiency ${center.efficiency} available ${center.available} ${center.description}');
    for (final entry in {'WEEK': data.weeks, 'LOAD': loads, 'UTIL': loads.map((load) => percent(load, center.available)).toList(), 'OVER': overloads, 'LEVELED': leveled.sublist(1)}.entries) {
      lines.add(tableRow(entry.key, entry.value, 7));
    }
    lines.add('TOTAL load $loadTotal available $capacity utilization ${percent(loadTotal, capacity)} overloaded $overloaded peak $peak backlog $backlog');
  }
  final ranked = [...data.centerOrder]..sort((a, b) {
    final comparison = (totals[b]! * data.centers[a]!.available).compareTo(totals[a]! * data.centers[b]!.available);
    return comparison != 0 ? comparison : a.compareTo(b);
  });
  for (final (index, id) in ranked.indexed) { lines.add('RANK ${index + 1} $id load ${totals[id]} utilization ${percent(totals[id]!, data.centers[id]!.available * data.horizon)}'); }
  return lines;
}

List<String> promiseLines(PlanningData data, List<Promise> promises, Plan base, Plan finalPlan) {
  final lines = <String>[], counts = {'on_time': 0, 'late': 0, 'rejected': 0};
  for (final promise in promises) {
    final inquiry = promise.inquiry, status = promise.status;
    counts[status] = counts[status]! + 1;
    final head = 'ORDER ${inquiry.id} ${inquiry.item} quantity ${inquiry.quantity} requested ${inquiry.week}', material = promise.materialWeek > 0 ? '${promise.materialWeek}' : 'none';
    if (status == 'rejected') { lines.add('$head rejected material $material reason ${promise.reason}'); continue; }
    lines.add(status == 'on_time' ? '$head promised ${promise.week}' : '$head promised ${promise.week} late ${promise.week - inquiry.week} material $material reason ${promise.reason}');
    for (final id in data.order) {
      for (final supply in finalPlan.items[id]!.orderSupplies) {
        if (supply.serves(inquiry.id)) { final order = supply.order!; lines.add('  SUPPLY $id order ${order.number} receipt ${order.receipt} release ${order.release} quantity ${order.quantity}'); }
      }
    }
  }
  for (final id in data.order) {
    final before = base.items[id]!, after = finalPlan.items[id]!; var changed = 0;
    for (final week in data.weeks) { if (before.plannedReceipts[week] != after.plannedReceipts[week]) { changed = week; break; } }
    if (changed > 0) lines.add('CHANGE $id from $changed planned ${total(before.plannedReceipts)} -> ${total(after.plannedReceipts)} orders ${before.orders.length} -> ${after.orders.length}');
  }
  lines.add('SUMMARY orders ${promises.length} on_time ${counts['on_time']} late ${counts['late']} rejected ${counts['rejected']}');
  return lines;
}

List<String> releaseLines(PlanningData data, Plan plan) {
  final orders = [for (final id in data.order) ...plan.items[id]!.orders.where((order) => order.release == 1)];
  orders.sort((a, b) {
    for (final comparison in [a.originalRelease.compareTo(b.originalRelease), a.item.compareTo(b.item), a.number.compareTo(b.number)]) { if (comparison != 0) return comparison; }
    return 0;
  });
  final available = {for (final entry in data.items.entries) entry.key: entry.value.onHand + data.scheduled[entry.key]![1]}, lines = <String>[];
  var made = 0, readyCount = 0, bought = 0, purchase = 0;
  for (final order in orders) {
    final id = order.item, item = data.items[id]!, late = order.originalRelease < 1 ? ' late ${1 - order.originalRelease}' : '';
    final head = '$id order ${order.number} receipt ${order.receipt} quantity ${order.quantity}';
    if (!data.bom.manufactured(id)) {
      final value = order.quantity * item.material; bought++; purchase += value; lines.add('BUY $head$late value ${money(value)}'); continue;
    }
    final picks = [for (final row in data.bom.children[id]!) (row.child, need(row, order.quantity), available[row.child]!)];
    final ready = picks.every((pick) => pick.$2 <= pick.$3);
    made++; if (ready) readyCount++;
    lines.add('MAKE $head$late ${ready ? 'READY' : 'SHORT'}');
    for (final (child, quantity, have) in picks) {
      lines.add('  PICK $child need $quantity available $have short ${max(0, quantity - have)}'); if (ready) available[child] = available[child]! - quantity;
    }
    final operations = data.routings[id] ?? <Operation>[];
    for (final (index, operation) in operations.indexed) { lines.add('  OPERATION ${operation.number} ${operation.center} week ${operationWeek(order.receipt, item.lead, index, operations.length)} minutes ${operation.minutes(order.quantity)}'); }
  }
  lines.add('SUMMARY make $made ready $readyCount short ${made - readyCount} buy $bought value ${money(purchase)}');
  return lines;
}

List<String> valueLines(PlanningData data, Plan plan, Map<String, Cost> costs) {
  final lines = ['week,inventory,purchases,labor'];
  for (final week in data.weeks) {
    var inventory = 0, purchases = 0, labor = 0;
    for (final id in data.order) {
      final p = plan.items[id]!, released = p.plannedReleases[week]; inventory += p.onHand[week] * costs[id]!.total;
      if (data.bom.manufactured(id)) { labor += released * p.item.labor; } else { purchases += released * p.item.material; }
    }
    lines.add('$week,${money(inventory)},${money(purchases)},${money(labor)}');
  }
  return lines;
}

void main() {
  final data = PlanningData(), base = runMrp(data, []), result = promiseInquiries(data, base), finalPlan = result.finalPlan;
  pegPlan(data, finalPlan);
  final costs = standardCosts(data.items, data.bom, data.order);
  final reports = {
    'mrp_grid.txt': gridLines(data, finalPlan), 'pegging.txt': peggingLines(data, finalPlan), 'bom_tree.txt': bomTreeLines(data),
    'cost_rollup.csv': costLines(data, finalPlan, costs), 'exceptions.txt': exceptionLines(data, finalPlan), 'capacity.txt': capacityLines(data, finalPlan),
    'promises.txt': promiseLines(data, result.promises, base, finalPlan), 'releases.txt': releaseLines(data, finalPlan), 'value_plan.csv': valueLines(data, finalPlan, costs)
  };
  for (final entry in reports.entries) { writeReport(entry.key, entry.value); }
}
