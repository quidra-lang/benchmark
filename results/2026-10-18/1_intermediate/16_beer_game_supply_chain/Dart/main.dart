import 'dart:io';

const stages = ['RETAILER', 'WHOLESALER', 'DISTRIBUTOR', 'FACTORY'];
const parameterCounts = {
  'FIXED': 1, 'PASS': 0, 'BASESTOCK': 1, 'MINMAX': 2,
  'MOVAVG': 2, 'SMOOTH': 2, 'STERMAN': 4,
};
const modes = {'ORDERS': 'order', 'INV': 'inventory', 'BACK': 'backlog'};

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
  @override
  String toString() => message;
}

int total(Iterable<int> values) => values.fold(0, (a, b) => a + b);
int floorDiv(int a, int b) => a < 0 ? -((-a + b - 1) ~/ b) : a ~/ b;

String money(int value) =>
    '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';

String decimal(int numerator, int denominator, int places) {
  final scale = [1, 10, 100, 1000, 10000][places];
  final fixed = floorDiv(numerator * scale, denominator);
  return '${fixed ~/ scale}.${(fixed % scale).toString().padLeft(places, '0')}';
}

int variation(List<int> values) {
  final n = values.length;
  return n * total(values.map((v) => v * v)) -
      total(values) * total(values);
}

class Policy {
  final String name;
  final List<int> args;
  final String display;
  Policy(this.name, this.args, this.display);
}

Policy parsePolicy(List<String> tokens) {
  final name = tokens.first;
  final count = parameterCounts[name];
  if (count == null) throw CommandError('unknown policy $name');
  if (tokens.length - 1 != count) {
    throw CommandError('$name needs $count parameters');
  }
  final args = <int>[];
  for (var i = 1; i < tokens.length; ++i) {
    args.add(int.parse(name == 'STERMAN' && i <= 3
        ? tokens[i].replaceAll('.', '') : tokens[i]));
  }
  final valid = switch (name) {
    'FIXED' => args[0] >= 0 && args[0] <= 1000,
    'PASS' => true,
    'BASESTOCK' => args[0] >= 0 && args[0] <= 10000,
    'MINMAX' => args[0] >= 0 && args[0] < args[1] && args[1] <= 10000,
    'MOVAVG' => args[0] >= 1 && args[0] <= 52 &&
        args[1] >= 0 && args[1] <= 10000,
    'SMOOTH' => args[0] >= 1 && args[0] <= 10 &&
        args[1] >= 0 && args[1] <= 10000,
    _ => args.take(3).every((v) => v >= 0 && v <= 100) &&
        args[3] >= 0 && args[3] <= 10000,
  };
  if (!valid) throw CommandError('invalid parameter for $name');
  return Policy(name, args, tokens.join(' '));
}

class Initial {
  final int inventory;
  final int quantity;
  final int shippingDelay;
  final int orderDelay;
  final int holding;
  final int backlog;
  final Policy policy;
  Initial(this.inventory, this.quantity, this.shippingDelay, this.orderDelay,
      this.holding, this.backlog, this.policy);

  factory Initial.parse(List<String> words) => Initial(
      int.parse(words[1]), int.parse(words[2]), int.parse(words[3]),
      int.parse(words[4]), int.parse(words[5]), int.parse(words[6]),
      parsePolicy(words.sublist(7)));
}

class Stage {
  int inventory;
  int backlog = 0;
  List<int> shipping;
  List<int> orders;
  Policy policy;
  int expected;
  int holding;
  int backlogRate;
  int lot = 1;
  int? capacity;
  final records = <Map<String, int>>[];

  Stage(Initial initial)
      : inventory = initial.inventory,
        shipping = List.filled(initial.shippingDelay, initial.quantity),
        orders = List.filled(initial.orderDelay, initial.quantity),
        policy = initial.policy,
        expected = 100 * initial.quantity,
        holding = initial.holding,
        backlogRate = initial.backlog;

  Stage clone() {
    final copy = Stage.__copy(
        inventory, backlog, List.of(shipping), List.of(orders),
        policy, expected, holding, backlogRate, lot, capacity);
    copy.records.addAll(records.map((r) => Map<String, int>.of(r)));
    return copy;
  }

  Stage.__copy(this.inventory, this.backlog, this.shipping, this.orders,
      this.policy, this.expected, this.holding, this.backlogRate,
      this.lot, this.capacity);
}

class Simulation {
  final List<Initial> initials;
  int week = 0;
  final List<int> demands;
  List<Stage> stages;
  int plantBacklog = 0;
  int? plantCapacity;
  List<Map<String, int>> plantRecords = [];
  String visibility = 'OFF';

  Simulation(this.initials, List<int> demands)
      : demands = List.of(demands),
        stages = initials.map(Stage.new).toList();

  Simulation clone() {
    final result = Simulation(initials, demands);
    result.week = week;
    result.stages = stages.map((stage) => stage.clone()).toList();
    result.plantBacklog = plantBacklog;
    result.plantCapacity = plantCapacity;
    result.plantRecords = plantRecords.map((r) => Map<String, int>.of(r)).toList();
    result.visibility = visibility;
    return result;
  }

  int signal(int index, int targetWeek, [List<int>? current]) {
    if (visibility == 'ON') return demands[targetWeek - 1];
    if (current != null && targetWeek == week + 1) return current[index];
    return stages[index].records[targetWeek - 1]['incoming']!;
  }

  void setPolicy(int index, Policy policy) {
    final stage = stages[index];
    stage.policy = policy;
    if (policy.name == 'STERMAN') {
      stage.expected = 100 * (week == 0
          ? initials[index].quantity : signal(index, week));
    }
  }

  (List<int>, List<int>) positions() {
    final supply = <int>[], positions = <int>[];
    for (var i = 0; i < stages.length; ++i) {
      final stage = stages[i];
      final upstream = i < 3 ? stages[i + 1].backlog : plantBacklog;
      final line = total(stage.orders) + upstream + total(stage.shipping);
      supply.add(line);
      positions.add(stage.inventory + line - stage.backlog);
    }
    return (supply, positions);
  }

  int policyOrder(int index, List<int> incoming, int line, int position) {
    final stage = stages[index];
    final policy = stage.policy;
    final args = policy.args;
    final nextWeek = week + 1;
    final demandSignal = signal(index, nextWeek, incoming);

    if (policy.name == 'FIXED') return args[0];
    if (policy.name == 'PASS') return incoming[index];
    if (policy.name == 'BASESTOCK') {
      return args[0] > position ? args[0] - position : 0;
    }
    if (policy.name == 'MINMAX') {
      return position <= args[0] ? args[1] - position : 0;
    }
    if (policy.name == 'MOVAVG') {
      final count = args[0] < nextWeek ? args[0] : nextWeek;
      var sum = 0;
      for (var w = nextWeek - count + 1; w <= nextWeek; ++w) {
        sum += signal(index, w, incoming);
      }
      final forecast = sum ~/ count;
      final initial = initials[index];
      final order = args[1] +
          forecast * (initial.shippingDelay + initial.orderDelay) - position;
      return order > 0 ? order : 0;
    }
    if (policy.name == 'SMOOTH') {
      final order = demandSignal + floorDiv(args[1] - position, args[0]);
      return order > 0 ? order : 0;
    }
    final theta = args[0], alpha = args[1], beta = args[2], target = args[3];
    stage.expected = floorDiv(
        100 * theta * demandSignal + (100 - theta) * stage.expected, 100);
    final net = stage.inventory - stage.backlog;
    final order = floorDiv(
        100 * stage.expected +
            alpha * (100 * (target - net) - beta * line), 10000);
    return order > 0 ? order : 0;
  }

  List<Map<String, int>> step() {
    final received = <int>[];
    for (final stage in stages) {
      final quantity = stage.shipping.removeAt(0);
      stage.inventory += quantity;
      received.add(quantity);
    }
    final incoming = <int>[demands[week]];
    for (var i = 0; i < 3; i++) {
      incoming.add(stages[i].orders.removeAt(0));
    }
    final plantIncoming = stages[3].orders.removeAt(0);
    final records = <Map<String, int>>[];
    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final before = stage.backlog;
      final requested = before + incoming[i];
      var shipped = stage.inventory < requested ? stage.inventory : requested;
      if (stage.capacity != null && shipped > stage.capacity!) {
        shipped = stage.capacity!;
      }
      stage.inventory -= shipped;
      stage.backlog = requested - shipped;
      if (i > 0) stages[i - 1].shipping.add(shipped);
      final ontime = (shipped - before) > 0 ? shipped - before : 0;
      records.add({
        'received': received[i], 'incoming': incoming[i],
        'shipped': shipped, 'before': before,
        'ontime': ontime < incoming[i] ? ontime : incoming[i],
        'inventory': stage.inventory, 'backlog': stage.backlog,
      });
    }
    final requested = plantBacklog + plantIncoming;
    final produced = plantCapacity == null || requested < plantCapacity!
        ? requested : plantCapacity!;
    plantBacklog = requested - produced;
    stages[3].shipping.add(produced);
    final (supply, positions) = this.positions();
    for (var i = 0; i < stages.length; ++i) {
      final stage = stages[i];
      final order = policyOrder(i, incoming, supply[i], positions[i]);
      final quantity = ((order + stage.lot - 1) ~/ stage.lot) * stage.lot;
      stage.orders.add(quantity);
      final record = records[i];
      record['order'] = quantity;
      record['holding'] = stage.holding * stage.inventory;
      record['backlog_cost'] = stage.backlogRate * stage.backlog;
      record['cost'] = record['holding']! + record['backlog_cost']!;
      stage.records.add(record);
    }
    plantRecords.add({
      'incoming': plantIncoming, 'produced': produced, 'backlog': plantBacklog,
    });
    week++;
    return records;
  }

  List<int> costs() => stages.map((s) =>
      total(s.records.map((r) => r['cost']!))).toList();
}

class Game {
  final List<Initial> initials;
  late List<int> base = [];
  late Simulation simulation = Simulation(initials, []);
  final snapshots = <String, Simulation>{};
  final output = <String>[];

  Game(List<List<String>> settings)
      : initials = settings.map(Initial.parse).toList();

  void emit(List<Object> parts) => output.add(parts.join(' '));

  int stageIndex(String name) {
    final index = stages.indexOf(name);
    if (index < 0) throw CommandError('unknown stage $name');
    return index;
  }

  List<int> target(String text) =>
      text == 'ALL' ? [0, 1, 2, 3] : [stageIndex(text)];

  void requireWeeks() {
    if (simulation.week == 0) throw CommandError('no weeks simulated');
  }

  (int, int) range(List<String> args, int limit) {
    if (args.isEmpty) return (1, limit);
    final first = int.parse(args[0]), last = int.parse(args[1]);
    if (first < 1 || last < first || last > limit) {
      throw CommandError('bad range ${args[0]} ${args[1]}');
    }
    return (first, last);
  }

  void checkMode(String mode) {
    if (!{'ORDERS', 'INV', 'BACK', 'NET'}.contains(mode)) {
      throw CommandError('unknown mode $mode');
    }
  }

  List<int> values(int index, String mode) {
    return simulation.stages[index].records.map((record) {
      if (mode == 'NET') return record['inventory']! - record['backlog']!;
      return record[modes[mode]]!;
    }).toList();
  }

  void initialize([List<int>? demands]) {
    if (demands != null) base = List.of(demands);
    simulation = Simulation(initials, base);
  }

  Simulation trial(List<Policy> policies) {
    final current = simulation;
    final simulation = Simulation(initials, current.demands);
    simulation.visibility = current.visibility;
    simulation.plantCapacity = current.plantCapacity;
    for (var i = 0; i < stages.length; i++) {
      final next = simulation.stages[i], before = current.stages[i];
      next.lot = before.lot;
      next.capacity = before.capacity;
      next.holding = before.holding;
      next.backlogRate = before.backlogRate;
      simulation.setPolicy(i, policies[i]);
    }
    while (simulation.week < simulation.demands.length) {
      simulation.step();
    }
    return simulation;
  }

  void demand(List<int> amounts) {
    initialize(amounts);
    emit(['DEMAND', 'weeks', amounts.length, 'total', total(amounts),
      'min', amounts.reduce((a, b) => a < b ? a : b),
      'max', amounts.reduce((a, b) => a > b ? a : b)]);
  }

  void generate(List<String> args) {
    final weeks = int.parse(args[0]), base = int.parse(args[1]),
        spread = int.parse(args[2]);
    var seed = int.parse(args[3]);
    final changes = <(String, int, int)>[];
    for (var i = 4; i < args.length; i += 3) {
      changes.add((args[i], int.parse(args[i+1]), int.parse(args[i+2])));
    }
    for (final (kind, week, amount) in changes) {
      if (week < 1 || week > weeks) {
        throw CommandError('week $week outside horizon');
      }
    }
    final levels = <int>[];
    for (var week = 1; week <= weeks; ++week) {
      var level = base;
      for (final (kind, start, amount) in changes) {
        if (kind == 'STEP' && week >= start) {
          level += amount;
        } else if (kind == 'PULSE' && week == start) {
          level += amount;
        } else if (kind == 'RAMP' && week >= start) {
          level += amount * (week - start + 1);
        }
      }
      if (level < 0) throw CommandError('negative level at week $week');
      levels.add(level);
    }
    final result = <int>[];
    for (final level in levels) {
      seed = 48271 * seed % 2147483647;
      result.add(level + seed % spread);
    }
    demand(result);
  }

  void status() {
    final s = simulation;
    emit(['STATUS', 'week', s.week, 'of', s.demands.length]);
    final (supply, position) = s.positions();
    for (var i = 0; i < stages.length; ++i) {
      final stage = s.stages[i];
      final parts = <Object>[
        stages[i], 'inv', stage.inventory, 'back', stage.backlog,
        'transit', stage.shipping.join(','), 'pending', stage.orders.join(','),
        'supply', supply[i], 'position', position[i], 'policy', stage.policy.display
      ];
      if (stage.policy.name == 'STERMAN') {
        parts.addAll(['expect', money(stage.expected)]);
      }
      emit(parts);
    }
    emit(['PLANT', 'back', s.plantBacklog]);
  }

  void showWeek(int week) {
    final s = simulation;
    emit(['WEEK', week, 'demand', s.demands[week - 1]]);
    for (var i = 0; i < stages.length; ++i) {
      final r = s.stages[i].records[week - 1];
      emit([stages[i], 'recv', r['received']!, 'in', r['incoming']!,
        'ship', r['shipped']!, 'inv', r['inventory']!, 'back', r['backlog']!,
        'order', r['order']!, 'cost', money(r['cost']!)]);
    }
    final r = s.plantRecords[week - 1];
    emit(['PLANT', 'in', r['incoming']!, 'made', r['produced']!, 'back', r['backlog']!]);
  }

  void table(int index, int first, int last) {
    emit(['TABLE', stages[index], '$first-$last']);
    final labels = ['week', 'in', 'ship', 'recv', 'inv', 'back', 'order', 'cost'];
    final widths = [4, 6, 6, 6, 6, 6, 6, 9];
    emit([List.generate(labels.length, (i) => labels[i].padLeft(widths[i])).join(' ')]);
    for (var week = first; week <= last; week++) {
      final r = simulation.stages[index].records[week - 1];
      final row = <Object>[week, r['incoming']!, r['shipped']!, r['received']!,
        r['inventory']!, r['backlog']!, r['order']!, money(r['cost']!)];
      emit([List.generate(row.length, (i) => row[i].toString().padLeft(widths[i])).join(' ')]);
    }
  }

  void costs() {
    emit(['COSTS', 'week', simulation.week]);
    var allHolding = 0, allBacklog = 0;
    for (var i = 0; i < stages.length; ++i) {
      final records = simulation.stages[i].records;
      final holding = total(records.map((r) => r['holding']!));
      final backlog = total(records.map((r) => r['backlog_cost']!));
      allHolding += holding;
      allBacklog += backlog;
      emit([stages[i], 'holding', money(holding), 'backlog', money(backlog),
        'total', money(holding + backlog)]);
    }
    emit(['TOTAL', 'holding', money(allHolding), 'backlog', money(allBacklog),
      'total', money(allHolding + allBacklog)]);
  }

  (int, int, String) fillText(List<Map<String, int>> records) {
    final ordered = total(records.map((r) => r['incoming']!));
    final ontime = total(records.map((r) => r['ontime']!));
    return (ordered, ontime, ordered == 0 ? 'n/a' :
        '${decimal(ontime * 100, ordered, 2)}%');
  }

  void bullwhip() {
    final s = simulation, n = simulation.week;
    final demands = s.demands.sublist(0, n);
    final demandVariation = variation(demands);
    emit(['BULLWHIP', 'weeks', '1-$n', 'demand',
      'mean', decimal(total(demands), n, 4),
      'var', decimal(demandVariation, n*n, 4)]);
    var previous = demandVariation;
    for (var i = 0; i < stages.length; ++i) {
      final orders = s.stages[i].records.map((r) => r['order']!).toList();
      final variance = variation(orders);
      emit([stages[i], 'mean', decimal(total(orders), n, 4),
        'var', decimal(variance, n*n, 4),
        'ratio', demandVariation == 0 ? 'n/a' : decimal(variance, demandVariation, 4),
        'step', previous == 0 ? 'n/a' : decimal(variance, previous, 4)]);
      previous = variance;
    }
  }

  void peaks() {
    final s = simulation;
    emit(['PEAKS', 'weeks', '1-${s.week}']);
    for (var i = 0; i < stages.length; ++i) {
      final records = s.stages[i].records;
      final inventories = records.map((r) => r['inventory']!).toList();
      final backlogs = records.map((r) => r['backlog']!).toList();
      final maxInv = inventories.reduce((a, b) => a > b ? a : b);
      final maxBack = backlogs.reduce((a, b) => a > b ? a : b);
      var longest = 0, run = 0, start = 0, bestStart = 0, bestEnd = 0;
      for (var week = 1; week <= backlogs.length; week++) {
        if (backlogs[week - 1] > 0) {
          if (run == 0) start = week;
          run++;
          if (run > longest) {
            longest = run;
            bestStart = start;
            bestEnd = week;
          }
        } else {
          run = 0;
        }
      }
      emit([stages[i], 'max_inv', maxInv, 'week',
        maxInv != 0 ? inventories.indexOf(maxInv) + 1 : '-',
        'max_back', maxBack, 'week',
        maxBack != 0 ? backlogs.indexOf(maxBack) + 1 : '-',
        'longest_stockout', longest == 0 ? 0 : '$longest weeks $bestStart-$bestEnd']);
    }
  }

  void leadtime(int index) {
    final s = simulation, stage = s.stages[index], initial = initials[index];
    final nominal = initial.shippingDelay + initial.orderDelay;
    final cumulative = <int>[];
    var received = 0;
    for (final record in stage.records) {
      received += record['received']!;
      cumulative.add(received - nominal * initial.quantity);
    }
    var ordered = 0, count = 0;
    final leads = <int>[];
    for (var t = 0; t < stage.records.length; t++) {
      final record = stage.records[t];
      ordered += record['order']!;
      if (record['order'] == 0) continue;
      count++;
      for (var u = t + 1; u < stage.records.length; ++u) {
        if (cumulative[u] >= ordered) {
          leads.add(u - t);
          break;
        }
      }
    }
    emit(['LEADTIME', stages[index], 'nominal', nominal,
      'orders', count, 'completed', leads.length, 'open', count - leads.length,
      'min', leads.isEmpty ? '-' : leads.reduce((a, b) => a < b ? a : b),
      'avg', leads.isEmpty ? '-' : decimal(total(leads), leads.length, 2),
      'max', leads.isEmpty ? '-' : leads.reduce((a, b) => a > b ? a : b)]);
  }

  void plot(int index, String mode, int first, int last) {
    final selected = values(index, mode).sublist(first - 1, last);
    final maxValue = selected.reduce((a, b) => a > b ? a : b);
    if (mode == 'NET') {
      final minValue = selected.reduce((a, b) => a < b ? a : b);
      emit(['PLOT', stages[index], mode, '$first-$last',
        'min', minValue, 'max', maxValue]);
      final scale = selected.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
      for (var i = 0; i < selected.length; i++) {
        final value = selected[i];
        final length = scale == 0 ? 0 : value.abs() * 25 ~/ scale;
        final left = value < 0
            ? '${''.padLeft(25 - length)}${List.filled(length, '-').join()}'
            : ''.padLeft(25);
        final right = value > 0 ? List.filled(length, '+').join() : '';
        emit(['${(first+i).toString().padLeft(3)} $left|$right $value']);
      }
    } else {
      emit(['PLOT', stages[index], mode, '$first-$last', 'max', maxValue]);
      for (var i = 0; i < selected.length; i++) {
        final value = selected[i];
        final length = maxValue == 0 ? 0 : value * 50 ~/ maxValue;
        emit(['${(first+i).toString().padLeft(3)} |${List.filled(length, '#').join()} $value']);
      }
    }
  }

  void command(String cmd, List<String> a) {
    final s = simulation;
    switch (cmd) {
      case 'DEMAND':
        demand(a.map(int.parse).toList());
        break;
      case 'GENERATE':
        generate(a);
        break;
      case 'RUN':
        if (s.week == s.demands.length) {
          throw CommandError('horizon reached at week ${s.demands.length}');
        }
        final first = s.week + 1;
        final count = int.parse(a[0]) < s.demands.length - s.week
            ? int.parse(a[0]) : s.demands.length - s.week;
        var cost = 0;
        for (var i = 0; i < count; ++i) {
          final records = s.step();
          for (var stage = 0; stage < stages.length; stage++) {
            final record = records[stage];
            cost += record['cost']!;
            if (record['before'] == 0 && record['backlog']! > 0) {
              emit(['STOCKOUT', stages[stage], 'week', s.week,
                'backlog', record['backlog']!]);
            } else if (record['before']! > 0 && record['backlog'] == 0) {
              emit(['RECOVER', stages[stage], 'week', s.week]);
            }
          }
        }
        emit(['RUN', '$first-${s.week}', 'demand',
          total(s.demands.sublist(first-1, s.week)), 'cost', money(cost)]);
        if (s.week == s.demands.length) emit(['HORIZON', s.week]);
        break;
      case 'RESET':
        initialize();
        emit(['RESET', 'week', 0]);
        break;
      case 'SAVE':
        snapshots[a[0]] = s.clone();
        emit(['SAVE', a[0], 'week', s.week]);
        break;
      case 'LOAD':
        if (!snapshots.containsKey(a[0])) throw CommandError('no snapshot ${a[0]}');
        simulation = snapshots[a[0]]!.clone();
        emit(['LOAD', a[0], 'week', simulation.week]);
        break;
      case 'SET':
        final indices = target(a[0]);
        final policy = parsePolicy(a.sublist(1));
        for (final index in indices) {
          s.setPolicy(index, policy);
        }
        emit(['SET', a[0], policy.display]);
        break;
      case 'BATCH':
        final index = stageIndex(a[0]);
        final lot = int.parse(a[1]);
        if (lot < 1 || lot > 100) throw CommandError('invalid batch size ${a[1]}');
        s.stages[index].lot = lot;
        emit(['BATCH', a[0], lot]);
        break;
      case 'CAPACITY':
        final index = a[0] == 'PLANT' ? null : stageIndex(a[0]);
        final capacity = a[1] == 'OFF' ? null : int.parse(a[1]);
        if (capacity != null && capacity > 10000) {
          throw CommandError('invalid capacity ${a[1]}');
        }
        if (index == null) {
          s.plantCapacity = capacity;
        } else {
          s.stages[index].capacity = capacity;
        }
        emit(['CAPACITY', a[0], a[1]]);
        break;
      case 'COST':
        final index = stageIndex(a[0]);
        final holding = int.parse(a[1]), backlog = int.parse(a[2]);
        if (holding > 1000 || backlog > 1000) throw CommandError('invalid cost');
        s.stages[index].holding = holding;
        s.stages[index].backlogRate = backlog;
        emit(['COST', a[0], 'holding', holding, 'backlog', backlog]);
        break;
      case 'VISIBILITY':
        if (a[0] != 'ON' && a[0] != 'OFF') {
          throw CommandError('unknown visibility ${a[0]}');
        }
        s.visibility = a[0];
        emit(['VISIBILITY', a[0]]);
        break;
      case 'SHOCK':
        final week = int.parse(a[0]), value = int.parse(a[1]);
        if (week < 1 || week > s.demands.length) {
          throw CommandError('week ${a[0]} outside horizon');
        }
        if (week <= s.week) throw CommandError('week ${a[0]} already simulated');
        final old = s.demands[week - 1];
        s.demands[week - 1] = value;
        emit(['SHOCK', 'week', week, old, '->', value]);
        break;
      case 'STATUS':
        status();
        break;
      case 'SETTINGS':
        emit(['SETTINGS']);
        for (var i = 0; i < stages.length; ++i) {
          final stage = s.stages[i], initial = initials[i];
          emit([stages[i], 'holding', stage.holding, 'backlog', stage.backlogRate,
            'batch', stage.lot, 'capacity', stage.capacity ?? 'OFF',
            'delays', initial.shippingDelay, initial.orderDelay]);
        }
        emit(['PLANT', 'capacity', s.plantCapacity ?? 'OFF']);
        emit(['VISIBILITY', s.visibility]);
        break;
      case 'WEEK':
        requireWeeks();
        final week = int.parse(a[0]);
        if (week < 1 || week > s.week) throw CommandError('bad week ${a[0]}');
        showWeek(week);
        break;
      case 'TABLE':
        final index = stageIndex(a[0]);
        requireWeeks();
        final (first, last) = range(a.sublist(1), s.week);
        table(index, first, last);
        break;
      case 'CHAIN':
        requireWeeks();
        final (first, last) = range(a, s.week);
        emit(['CHAIN', '$first-$last']);
        emit(['${'week'.padLeft(4)} ${'demand'.padLeft(6)} '
          '${stages.map((s) => s.padLeft(11)).join(' ')}']);
        for (var week = first; week <= last; week++) {
          final orders = s.stages.map((stage) =>
              stage.records[week - 1]['order']!.toString().padLeft(11)).join(' ');
          emit(['${week.toString().padLeft(4)} '
            '${s.demands[week-1].toString().padLeft(6)} $orders']);
        }
        break;
      case 'DEMANDS':
        final (first, last) = range(a, s.demands.length);
        final values = s.demands.sublist(first-1, last);
        emit(['DEMANDS', '$first-$last', 'total', total(values),
          'min', values.reduce((a,b) => a < b ? a : b),
          'max', values.reduce((a,b) => a > b ? a : b)]);
        emit(values.cast<Object>());
        break;
      case 'COSTS':
        costs();
        break;
      case 'SUMMARY':
        requireWeeks();
        emit(['SUMMARY', 'weeks', '1-${s.week}']);
        for (var i = 0; i < stages.length; ++i) {
          final records = s.stages[i].records;
          final orders = records.map((r) => r['order']!).toList();
          emit([stages[i], 'avg_inv',
            decimal(total(records.map((r) => r['inventory']!)), s.week, 2),
            'avg_back', decimal(total(records.map((r) => r['backlog']!)), s.week, 2),
            'orders', total(orders),
            'min', orders.reduce((a,b) => a < b ? a : b),
            'max', orders.reduce((a,b) => a > b ? a : b),
            'zero_weeks', orders.where((o) => o == 0).length]);
        }
        break;
      case 'BALANCE':
        emit(['BALANCE', 'week', s.week]);
        for (var i = 0; i < stages.length; ++i) {
          final record = s.stages[i].records;
          emit([stages[i], 'start', initials[i].inventory,
            'received', total(record.map((r) => r['received']!)),
            'shipped', total(record.map((r) => r['shipped']!)),
            'end', s.stages[i].inventory, 'owed', s.stages[i].backlog]);
        }
        final initialGoods = total(initials.map((i) =>
            i.inventory + i.quantity * i.shippingDelay));
        emit(['SYSTEM', 'initial', initialGoods,
          'produced', total(s.plantRecords.map((r) => r['produced']!)),
          'delivered', total(s.stages[0].records.map((r) => r['shipped']!)),
          'stock', total(s.stages.map((stage) => stage.inventory)),
          'transit', total(s.stages.map((stage) => total(stage.shipping)))]);
        break;
      case 'FILLRATE':
        requireWeeks();
        emit(['FILLRATE', 'weeks', '1-${s.week}']);
        for (var i = 0; i < stages.length; ++i) {
          final stage = s.stages[i];
          final (ordered, ontime, fill) = fillText(stage.records);
          final stockouts = stage.records.where((r) => r['backlog']! > 0).length;
          emit([stages[i], 'fill', fill, 'ontime', ontime, 'ordered', ordered,
            'stockout_weeks', stockouts,
            'service', '${decimal((s.week-stockouts)*100, s.week, 2)}%']);
        }
        break;
      case 'BULLWHIP':
        requireWeeks();
        bullwhip();
        break;
      case 'PEAKS':
        requireWeeks();
        peaks();
        break;
      case 'LEADTIME':
        final index = stageIndex(a[0]);
        requireWeeks();
        leadtime(index);
        break;
      case 'PLOT':
      case 'HISTOGRAM':
        final index = stageIndex(a[0]);
        checkMode(a[1]);
        int? width;
        if (cmd == 'HISTOGRAM') {
          width = int.parse(a[2]);
          if (width < 1 || width > 100) {
            throw CommandError('invalid width ${a[2]}');
          }
        }
        requireWeeks();
        if (cmd == 'PLOT') {
          final (first, last) = range(a.sublist(2), s.week);
          plot(index, a[1], first, last);
        } else {
          final values = this.values(index, a[1]);
          final bins = <int, int>{};
          for (final value in values) {
            final bucket = floorDiv(value, width!);
            bins[bucket] = (bins[bucket] ?? 0) + 1;
          }
          emit(['HISTOGRAM', a[0], a[1], 'width', width!,
            'weeks', '1-${s.week}']);
          final keys = bins.keys.toList()..sort();
          for (var bucket = keys.first; bucket <= keys.last; bucket++) {
            final count = bins[bucket] ?? 0;
            final parts = <Object>['${bucket * width}-${bucket * width + width - 1}', count];
            // A histogram interval is written using two dots, unlike a date range.
            parts[0] = '${bucket * width}..${bucket * width + width - 1}';
            if (count != 0) parts.add(List.filled(count, '*').join());
            emit(parts);
          }
        }
        break;
      case 'COMPARE':
        final policies = <Policy>[];
        var start = 0;
        for (var end = 0; end <= a.length; end++) {
          if (end == a.length || a[end] == '/') {
            policies.add(parsePolicy(a.sublist(start, end)));
            start = end + 1;
          }
        }
        final rows = <(int, int, String, String, String)>[];
        for (var index = 0; index < policies.length; index++) {
          final trial = this.trial(List.filled(4, policies[index]));
          final cost = total(trial.costs());
          final (_, __, fill) = fillText(trial.stages[0].records);
          final demandVariance = variation(trial.demands);
          final factoryVariance = variation(trial.stages[3].records
              .map((r) => r['order']!).toList());
          final ratio = demandVariance == 0 ? 'n/a' :
              decimal(factoryVariance, demandVariance, 4);
          rows.add((cost, index, policies[index].display, fill, ratio));
        }
        rows.sort((a,b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
        emit(['COMPARE', policies.length, 'weeks', s.demands.length]);
        for (var i = 0; i < rows.length; i++) {
          final item = rows[i];
          emit([i+1, item.$3, 'total', money(item.$1),
            'fill', item.$4, 'bullwhip', item.$5]);
        }
        break;
      case 'OPTIMIZE':
        final indices = target(a[0]);
        final low = int.parse(a[1]), high = int.parse(a[2]);
        if (low > high) throw CommandError('bad range ${a[1]} ${a[2]}');
        if (high - low > 200) throw CommandError('range too large');
        (int, int, int)? best;
        for (var target = low; target <= high; ++target) {
          final policies = s.stages.map((stage) => stage.policy).toList();
          for (final index in indices) {
            policies[index] = Policy('BASESTOCK', [target], 'BASESTOCK $target');
          }
          final trial = this.trial(policies);
          final costs = trial.costs();
          final objective = total(indices.map((i) => costs[i]));
          final candidate = (objective, target, total(costs));
          if (best == null || candidate.$1 < best.$1 ||
              (candidate.$1 == best.$1 && candidate.$2 < best.$2)) {
            best = candidate;
          }
        }
        emit(['OPTIMIZE', a[0], 'BASESTOCK', best!.$2,
          'cost', money(best.$1), 'total', money(best.$3)]);
        break;
      default:
        throw CommandError('unknown command $cmd');
    }
  }

  void execute(String line) {
    final tokens = line.trim().split(' ');
    final command = tokens.first;
    try {
      this.command(command, tokens.sublist(1));
    } on CommandError catch (error) {
      emit(['ERROR', error.message]);
    }
  }
}

void main() {
  final initial = <List<String>>[];
  for (var i = 0; i < 4; ++i) {
    initial.add(stdin.readLineSync()!.split(' '));
  }
  final game = Game(initial);
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line == 'END') break;
    game.execute(line);
  }
  if (game.output.isNotEmpty) stdout.write('${game.output.join('\n')}\n');
}
