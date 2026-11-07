import 'dart:math';
import 'items.dart';
import 'bom.dart';

class WorkCenter {
  final String id, description;
  final int minutes, efficiency, available;
  WorkCenter(List<String> f) : id = f[0], minutes = int.parse(f[1]), efficiency = int.parse(f[2]), description = f[3], available = int.parse(f[1]) * int.parse(f[2]) ~/ 100;
}

class Operation {
  final String item, center;
  final int number, setup, run;
  Operation(List<String> f) : item = f[0], number = int.parse(f[1]), center = f[2], setup = int.parse(f[3]), run = int.parse(f[4]);
  int minutes(int quantity) => setup + quantity * run;
}

Map<String, WorkCenter> readCenters(List<String> errors) {
  final centers = <String, WorkCenter>{};
  for (final row in readRows('workcenters.csv')) {
    final id = row.fields[0], efficiency = int.parse(row.fields[2]);
    final reason = centers.containsKey(id) ? 'duplicate center $id' : efficiency < 50 || efficiency > 150 ? 'bad efficiency $efficiency' : null;
    if (reason != null) { errors.add('workcenters.csv line ${row.line}: $reason'); } else { centers[id] = WorkCenter(row.fields); }
  }
  return centers;
}

Map<String, List<Operation>> readRoutings(Map<String, Item> items, Map<String, WorkCenter> centers, Bom bom, List<String> errors) {
  final routings = <String, List<Operation>>{};
  for (final row in readRows('routings.csv')) {
    final op = Operation(row.fields), id = op.item, center = op.center;
    String? reason;
    if (!items.containsKey(id)) { reason = 'unknown item $id'; }
    else if (!centers.containsKey(center)) { reason = 'unknown center $center'; }
    else if (!bom.manufactured(id)) { reason = 'purchased item $id'; }
    else if (op.run < 1) { reason = 'bad run time ${op.run}'; }
    else if ((routings[id] ?? []).any((other) => other.number == op.number)) { reason = 'duplicate $id operation ${op.number}'; }
    if (reason != null) { errors.add('routings.csv line ${row.line}: $reason'); } else { (routings[id] ??= []).add(op); }
  }
  for (final operations in routings.values) { operations.sort((a, b) => a.number.compareTo(b.number)); }
  return routings;
}

int operationWeek(int receipt, int lead, int index, int count) => max(receipt - lead + index * lead ~/ count, 1);

List<int> levelLoads(List<int> loads, int available) {
  final leveled = List.filled(loads.length, 0); var carry = 0;
  for (var week = loads.length - 1; week >= 2; week--) {
    final total = loads[week] + carry; leveled[week] = min(total, available); carry = total - leveled[week];
  }
  leveled[1] = loads[1] + carry;
  return leveled;
}
