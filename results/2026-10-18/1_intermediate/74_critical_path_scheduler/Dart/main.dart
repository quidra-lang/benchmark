import 'dart:io';
import 'dart:math' as math;

class Task {
  final String id, resource;
  final int base, units;
  int notBefore = 0, used = 0;
  (int, int)? crash;
  (int, int, int)? pert;
  Task(this.id, this.base, this.resource, this.units);
  int get duration => base - used;
}
class Dependency {
  final String a, b, kind;
  final int lag;
  Dependency(this.a, this.b, this.kind, this.lag);
}
class Timing {
  final int duration, es, ef;
  int ls = 0, lf = 0, tf = 0, ff = 0;
  Timing(this.duration, this.es) : ef = es + duration;
}
class Schedule {
  final Map<String, Timing> rows;
  final int total;
  Schedule(this.rows, this.total);
}
class Baseline {
  final int total;
  final Map<String, (int, int)> rows;
  Baseline(this.total, this.rows);
}
class ScheduleError implements Exception {
  final String message;
  ScheduleError(this.message);
}
final tasks = <String, Task>{};
var dependencies = <Dependency>[];
final capacities = <String, int>{};
final holidays = <int>{};
final output = <String>[];
int? startDate, deadline;
Baseline? baseline;
final epoch = DateTime.utc(2000, 1, 1);
Never fail(String message) => throw ScheduleError('error: $message');
List<String> names() => tasks.keys.toList()..sort();
Task task(String name) {
  final result = tasks[name];
  if (result == null) fail('unknown task $name');
  return result;
}
String signed(int value) => value >= 0 ? '+$value' : '$value';
String decimal(int numerator, int denominator) {
  final hundredths = numerator * 100 ~/ denominator;
  return '${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}';
}
List<Dependency> predecessors(String name) => dependencies.where((dep) => dep.b == name).toList()
    ..sort((a, b) => a.a.compareTo(b.a));
List<Dependency> successors(String name) => dependencies.where((dep) => dep.a == name).toList()
    ..sort((a, b) => a.b.compareTo(b.b));
(List<String>, Set<String>) topological() {
  final remaining = names().toSet(), order = <String>[];
  while (true) {
    String? next;
    for (final name in remaining) {
      if (predecessors(name).every((dep) => !remaining.contains(dep.a))) {
        next = name;
        break;
      }
    }
    if (next == null) return (order, remaining);
    remaining.remove(next);
    order.add(next);
  }
}
String? cycle() {
  final remaining = topological().$2;
  if (remaining.isEmpty) return null;
  final trail = <String>[remaining.first];
  while (true) {
    final next = predecessors(trail.last).firstWhere((dep) => remaining.contains(dep.a)).a;
    final at = trail.indexOf(next);
    if (at >= 0) {
      final loop = [next, ...trail.sublist(at + 1).reversed];
      final smallest = (loop.toList()..sort()).first, first = loop.indexOf(smallest);
      final rotated = [...loop.sublist(first), ...loop.sublist(0, first)];
      return [...rotated, rotated.first].join(' -> ');
    }
    trail.add(next);
  }
}
Schedule schedule([Map<String, int> overrides = const {}]) {
  final order = topological().$1, rows = <String, Timing>{};
  var total = 0;
  for (final name in order) {
    final item = tasks[name]!, d = overrides[name] ?? tasks[name]!.duration;
    var es = item.notBefore;
    for (final dep in predecessors(name)) {
      final old = rows[dep.a]!;
      es = math.max(es, (dep.kind == 'SS' ? old.es : old.ef) + dep.lag - (dep.kind == 'FF' ? d : 0));
    }
    rows[name] = Timing(d, es);
    total = math.max(total, es + d);
  }
  for (final name in order.reversed) {
    final row = rows[name]!;
    var lf = total;
    for (final dep in successors(name)) {
      final next = rows[dep.b]!;
      lf = math.min(lf, (dep.kind == 'FF' ? next.lf : next.ls) - dep.lag + (dep.kind == 'SS' ? row.duration : 0));
    }
    row.lf = lf;
    row.ls = lf - row.duration;
    row.tf = row.ls - row.es;
  }
  for (final name in order) {
    final row = rows[name]!;
    row.ff = total - row.ef;
    for (final dep in successors(name)) { row.ff = math.min(row.ff, margin(dep, rows)); }
  }
  return Schedule(rows, total);
}
int margin(Dependency dep, Map<String, Timing> rows) {
  final a = rows[dep.a]!, b = rows[dep.b]!;
  return (dep.kind == 'FF' ? b.ef : b.es) - (dep.kind == 'SS' ? a.es : a.ef) - dep.lag;
}
List<String> critical(Schedule schedule) => names().where((name) => schedule.rows[name]!.tf == 0).toList();
List<List<String>> criticalPaths(Schedule schedule) {
  final criticalNames = critical(schedule).toSet();
  final links = dependencies.where((dep) => criticalNames.contains(dep.a) &&
      criticalNames.contains(dep.b) && margin(dep, schedule.rows) == 0).toList();
  final roots = criticalNames.where((name) => !links.any((dep) => dep.b == name));
  final result = <List<String>>[];
  void visit(List<String> path) {
    final next = links.where((dep) => dep.a == path.last).map((dep) => dep.b).toList()..sort();
    if (next.isEmpty) result.add(path);
    for (final name in next) { visit([...path, name]); }
  }
  for (final name in roots) { visit([name]); }
  return result;
}
int parseDate(String word) {
  final parts = word.split('-').map(int.parse).toList();
  final value = DateTime.utc(parts[0], parts[1], parts[2]);
  if (value.year != parts[0] || value.month != parts[1] || value.day != parts[2]) fail('invalid date $word');
  return value.difference(epoch).inDays;
}
int weekday(int day) => (day + 5) % 7;
String dateText(int day) {
  final date = epoch.add(Duration(days: day));
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday(day)]}';
}
bool working(int day) => weekday(day) < 5 && !holidays.contains(day);
List<int> dayDates(int count) {
  final result = <int>[];
  for (var day = startDate!; result.length < count; day++) {
    if (working(day)) result.add(day);
  }
  return result;
}
int workingBetween(int a, int b) {
  var count = 0;
  for (var day = a + 1; day <= b; day++) {
    if (working(day)) count++;
  }
  return count;
}
List<String> resources() => tasks.values.map((item) => item.resource).toSet().toList()..sort();
List<int> usage(String resource, Schedule schedule) {
  final result = List<int>.filled(schedule.total, 0);
  for (final item in tasks.values) {
    if (item.resource != resource) continue;
    final row = schedule.rows[item.id]!;
    for (var day = row.es; day < row.ef; day++) { result[day] += item.units; }
  }
  return result;
}
void level(int limit, Schedule original) {
  int capacity(String resource) => capacities[resource] ?? limit;
  for (final name in names()) {
    final item = tasks[name]!;
    if (item.units > capacity(item.resource)) fail('capacity ${capacity(item.resource)} too small for $name');
  }
  final undecided = names().toSet(), decided = <String, (int, int)>{};
  final used = <String, Map<int, int>>{for (final name in resources()) name: {}}, order = <String>[];
  while (undecided.isNotEmpty) {
    final available = undecided.where((name) => predecessors(name).every((dep) => decided.containsKey(dep.a))).toList();
    available.sort((a, b) {
      final comparison = original.rows[a]!.ls.compareTo(original.rows[b]!.ls);
      return comparison == 0 ? a.compareTo(b) : comparison;
    });
    final name = available.first, item = tasks[available.first]!;
    final d = item.duration, days = used[item.resource]!;
    var start = item.notBefore;
    for (final dep in predecessors(name)) {
      final old = decided[dep.a]!;
      start = math.max(start, (dep.kind == 'SS' ? old.$1 : old.$2) + dep.lag - (dep.kind == 'FF' ? d : 0));
    }
    while (true) {
      var valid = true;
      for (var day = start; day < start + d; day++) {
        if ((days[day] ?? 0) + item.units > capacity(item.resource)) { valid = false; break; }
      }
      if (valid) break;
      start++;
    }
    for (var day = start; day < start + d; day++) { days[day] = (days[day] ?? 0) + item.units; }
    decided[name] = (start, start + d);
    undecided.remove(name);
    order.add(name);
  }
  final finish = decided.values.map((row) => row.$2).reduce(math.max);
  output.add('level capacity $limit: duration ${original.total} -> $finish');
  for (final name in order) {
    final row = decided[name]!;
    output.add('$name start ${row.$1} finish ${row.$2} shift ${row.$1 - original.rows[name]!.es}');
  }
  for (final resource in resources()) {
    final peak = usage(resource, original).reduce(math.max);
    final next = used[resource]!.values.fold<int>(0, math.max);
    output.add('resource $resource capacity ${capacity(resource)} peak $peak -> $next');
  }
}
void execute(String commandLine) {
  final words = commandLine.split(' '), command = words.first, args = words.skip(1).toList();
  final a = args.isEmpty ? '' : args[0], b = args.length < 2 ? '' : args[1];
  if (command == 'TASK') {
    if (tasks.containsKey(a)) fail('task $a already exists');
    tasks[a] = Task(a, int.parse(b), args[2], int.parse(args[3]));
    output.add('task $a added');
    return;
  }
  if (command == 'DEP' || command == 'UNDEP') {
    task(a);
    task(b);
    final at = dependencies.indexWhere((dep) => dep.a == a && dep.b == b);
    if (command == 'DEP') {
      if (a == b) fail('self dependency $a');
      if (at >= 0) fail('dependency $a -> $b already exists');
      dependencies.add(Dependency(a, b, args[2], int.parse(args[3])));
      output.add('dependency $a -> $b ${args[2]}${signed(int.parse(args[3]))} added');
    } else {
      if (at < 0) fail('no dependency $a -> $b');
      dependencies.removeAt(at);
      output.add('dependency $a -> $b removed');
    }
    return;
  }
  if (['REMOVE', 'NOTBEFORE', 'CRASHCOST', 'UNCRASH', 'PERT', 'SHOW', 'IMPACT'].contains(command)) {
    final item = task(a);
    if (command == 'REMOVE') {
      final before = dependencies.length;
      dependencies.removeWhere((dep) => dep.a == a || dep.b == a);
      tasks.remove(a);
      output.add('task $a removed with ${before - dependencies.length} dependencies');
    } else if (command == 'NOTBEFORE') {
      item.notBefore = int.parse(b);
      output.add('notbefore $a $b');
    } else if (command == 'CRASHCOST') {
      if (int.parse(b) >= item.base) fail('crash limit too large for $a');
      if (int.parse(b) < item.used) fail('crash limit below used days for $a');
      item.crash = (int.parse(b), int.parse(args[2]));
      output.add('crash $a max $b cost ${args[2]}');
    } else if (command == 'UNCRASH') {
      output.add('uncrash $a restored ${item.used} days');
      item.used = 0;
    } else if (command == 'PERT') {
      final o = int.parse(args[1]), m = int.parse(args[2]), p = int.parse(args[3]);
      if (o > m || m > p) fail('invalid estimate');
      item.pert = (o, m, p);
      output.add('pert $a expected ${decimal(o + 4 * m + p, 6)} variance ${decimal((p - o) * (p - o), 36)}');
    } else if (command == 'IMPACT') {
      final seen = <String>{a}, queue = <String>[a];
      for (var i = 0; i < queue.length; i++) {
        for (final dep in successors(queue[i])) {
          if (seen.add(dep.b)) queue.add(dep.b);
        }
      }
      seen.remove(a);
      final affected = seen.toList()..sort();
      output.add('impact $a: ${affected.isEmpty ? 'none' : affected.join(' ')}');
    } else {
      final preds = predecessors(a).map((dep) => '${dep.a} ${dep.kind}${signed(dep.lag)}').join(', ');
      final succs = successors(a).map((dep) => '${dep.b} ${dep.kind}${signed(dep.lag)}').join(', ');
      output.addAll(['task $a duration ${item.duration} resource ${item.resource} units ${item.units}${item.notBefore != 0 ? ' notbefore ${item.notBefore}' : ''}',
        'preds: ${preds.isEmpty ? 'none' : preds}', 'succs: ${succs.isEmpty ? 'none' : succs}',
        item.crash == null ? 'crash: none' : 'crash: max ${item.crash!.$1} used ${item.used} cost ${item.crash!.$2}',
        item.pert == null ? 'pert: none' : 'pert: ${item.pert!.$1} ${item.pert!.$2} ${item.pert!.$3}']);
      if (cycle() != null) {
        output.add('schedule: unavailable');
      } else {
        final row = schedule().rows[a]!;
        output.add('schedule: ES ${row.es} EF ${row.ef} LS ${row.ls} LF ${row.lf} TF ${row.tf} FF ${row.ff}${row.tf == 0 ? ' critical' : ''}');
      }
    }
    return;
  }
  if (command == 'CAPACITY') {
    capacities[a] = int.parse(b);
    output.add('capacity $a $b');
    return;
  }
  if (['START', 'HOLIDAY', 'DEADLINE'].contains(command)) {
    final day = parseDate(a);
    if (command == 'HOLIDAY' && holidays.contains(day)) fail('duplicate holiday $a');
    if (command == 'START') { startDate = day; }
    else if (command == 'DEADLINE') { deadline = day; }
    else { holidays.add(day); }
    output.add('${command.toLowerCase()} ${dateText(day)}');
    return;
  }
  if (command == 'LIST') {
    output.add('tasks ${tasks.length}, dependencies ${dependencies.length}, holidays ${holidays.length}');
    for (final name in names()) {
      final item = tasks[name]!, preds = predecessors(name).map((dep) => dep.a).join(' ');
      output.add('$name duration ${item.duration} resource ${item.resource} units ${item.units} preds ${preds.isEmpty ? 'none' : preds}');
    }
    return;
  }
  if (tasks.isEmpty) fail('no tasks');
  final foundCycle = cycle();
  if (foundCycle != null) fail('cycle $foundCycle');
  if (command == 'CALENDAR' && startDate == null) fail('no start date');
  if (command == 'LOAD' && !resources().contains(a)) fail('unknown resource $a');
  if (command == 'WHATIF') task(a);
  if (command == 'VARIANCE' && baseline == null) fail('no baseline');
  final current = schedule(), byStart = names();
  byStart.sort((a, b) {
    final comparison = current.rows[a]!.es.compareTo(current.rows[b]!.es);
    return comparison == 0 ? a.compareTo(b) : comparison;
  });
  switch (command) {
    case 'CPM':
      final width = names().map((name) => name.length).fold<int>(4, math.max);
      output.add('TASK'.padRight(width) + ['DUR', 'ES', 'EF', 'LS', 'LF', 'TF', 'FF'].map((word) => word.padLeft(5)).join());
      for (final name in names()) {
        final row = current.rows[name]!;
        output.add(name.padRight(width) + [row.duration, row.es, row.ef, row.ls, row.lf, row.tf, row.ff]
            .map((value) => value.toString().padLeft(5)).join() + (row.tf == 0 ? ' *' : ''));
      }
      output.add('project duration ${current.total}');
    case 'CRITICAL':
      final paths = criticalPaths(current);
      output.add('critical paths: ${paths.length}');
      output.addAll(paths.map((path) => path.join(' -> ')));
    case 'SLACK':
      final floats = current.rows.values.map((row) => row.tf).toSet().toList()..sort();
      for (final value in floats) {
        output.add('float $value: ${names().where((name) => current.rows[name]!.tf == value).join(' ')}');
      }
    case 'DRAG':
      for (final name in critical(current)) { output.add('$name drag ${current.total - schedule({name: 0}).total}'); }
    case 'STATS':
      final count = critical(current).length, floats = current.rows.values.fold<int>(0, (sum, row) => sum + row.tf);
      final work = resources().map((resource) => '$resource ${tasks.values.where((item) => item.resource == resource).fold<int>(0, (sum, item) => sum + item.duration * item.units)}').join(', ');
      output.addAll(['tasks ${tasks.length}, critical $count, dependencies ${dependencies.length} (FS ${dependencies.where((dep) => dep.kind == 'FS').length}, SS ${dependencies.where((dep) => dep.kind == 'SS').length}, FF ${dependencies.where((dep) => dep.kind == 'FF').length})',
        'work $work', 'float total $floats, average ${decimal(floats, tasks.length)}',
        'duration ${current.total}, critical share ${decimal(100 * count, tasks.length)}%']);
    case 'CALENDAR':
      final dates = dayDates(current.total), first = dates.first, last = dates.last;
      for (final name in byStart) {
        final row = current.rows[name]!;
        output.add('$name ${dateText(dates[row.es])} - ${dateText(dates[row.ef - 1])}');
      }
      output.add('project ${dateText(first)} - ${dateText(last)}, ${current.total} working days, ${last - first + 1} calendar days');
      if (deadline != null) {
        output.add(last <= deadline! ? 'deadline ${dateText(deadline!)} met, ${workingBetween(last, deadline!)} working days to spare'
            : 'deadline ${dateText(deadline!)} missed by ${workingBetween(deadline!, last)} working days');
      }
      final within = holidays.where((day) => weekday(day) < 5 && day >= first && day <= last).toList()..sort();
      output.add('holidays in span: ${within.isEmpty ? 'none' : within.map(dateText).join(', ')}');
    case 'GANTT':
      if (current.total > 60) fail('chart too wide (${current.total} days)');
      final width = names().map((name) => name.length).reduce(math.max);
      output.add(''.padRight(width) + ' |${List.generate(current.total, (i) => i % 10).join()}|');
      for (final name in byStart) {
        final row = current.rows[name]!;
        final bar = List.generate(current.total, (day) => day >= row.es && day < row.ef
            ? row.tf == 0 ? '=' : '-' : day >= row.ef && day < row.lf ? '.' : ' ').join();
        output.add('${name.padRight(width)} |$bar|');
      }
    case 'LEVEL':
      level(int.parse(a), current);
    case 'LOAD':
      final days = usage(a, current), peak = days.reduce(math.max);
      output.addAll(['load $a: ${days.join(' ')}', 'peak $peak on day ${days.indexOf(peak)}']);
      if (capacities.containsKey(a)) output.add('capacity ${capacities[a]} exceeded on ${days.where((value) => value > capacities[a]!).length} days');
    case 'PERTSUM':
      for (final path in criticalPaths(current)) {
        var expected = 0, variance = 0;
        for (final name in path) {
          final item = tasks[name]!;
          final (o, m, p) = item.pert ?? (item.duration, item.duration, item.duration);
          expected += o + 4 * m + p;
          variance += (p - o) * (p - o);
        }
        output.add('${path.join(' -> ')}: expected ${decimal(expected, 6)} variance ${decimal(variance, 36)}');
      }
    case 'CRASH':
      var remaining = int.parse(a), count = 0, total = current.total, reason = '';
      while (true) {
        final now = schedule();
        final candidates = critical(now).where((name) {
          final item = tasks[name]!;
          return item.crash != null && item.used < item.crash!.$1 && schedule({name: item.duration - 1}).total < now.total;
        }).toList();
        candidates.sort((a, b) {
          final comparison = tasks[a]!.crash!.$2.compareTo(tasks[b]!.crash!.$2);
          return comparison == 0 ? a.compareTo(b) : comparison;
        });
        if (candidates.isEmpty) { reason = 'no candidate'; break; }
        final name = candidates.first, item = tasks[candidates.first]!;
        final cost = item.crash!.$2;
        if (cost > remaining) { reason = 'insufficient budget'; break; }
        final old = item.duration;
        item.used++;
        remaining -= cost;
        count++;
        total = schedule().total;
        output.add('step $count: $name $old -> ${item.duration}, cost $cost, project $total');
      }
      output.add('crash done: $count days, cost ${int.parse(a) - remaining}, project ${current.total} -> $total, budget left $remaining, $reason');
    case 'WHATIF':
      final after = schedule({a: int.parse(b)});
      output.add('whatif $a ${tasks[a]!.duration} -> $b: project ${current.total} -> ${after.total}');
      for (final name in names()) {
        final before = current.rows[name]!, next = after.rows[name]!;
        final changes = <String>[];
        if (before.es != next.es) changes.add('ES ${before.es}->${next.es}');
        if (before.ef != next.ef) changes.add('EF ${before.ef}->${next.ef}');
        if (before.tf != next.tf) changes.add('TF ${before.tf}->${next.tf}');
        if (changes.isNotEmpty) output.add('$name ${changes.join(' ')}');
      }
      final beforeCritical = critical(current).join(' '), afterCritical = critical(after).join(' ');
      if (beforeCritical != afterCritical) output.add('critical $beforeCritical -> $afterCritical');
    case 'BASELINE':
      baseline = Baseline(current.total, {for (final entry in current.rows.entries) entry.key: (entry.value.es, entry.value.ef)});
      output.add('baseline saved: ${tasks.length} tasks, duration ${current.total}');
    case 'VARIANCE':
      output.add('variance: duration ${baseline!.total} -> ${current.total} (${signed(current.total - baseline!.total)})');
      final before = output.length, allNames = {...baseline!.rows.keys, ...tasks.keys}.toList()..sort();
      for (final name in allNames) {
        final old = baseline!.rows[name], row = current.rows[name];
        if (row == null) { output.add('$name removed'); }
        else if (old == null) { output.add('$name new'); }
        else if (old.$1 != row.es || old.$2 != row.ef) { output.add('$name start ${signed(row.es - old.$1)} finish ${signed(row.ef - old.$2)}'); }
      }
      if (output.length == before) output.add('no task changes');
  }
}
void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try { execute(stdin.readLineSync()!); }
    on ScheduleError catch (error) { output.add(error.message); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
