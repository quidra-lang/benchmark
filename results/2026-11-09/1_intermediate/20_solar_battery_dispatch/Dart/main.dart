import 'dart:io';
import 'dart:math' as math;

const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const flowNames = ['PV>LOAD', 'PV>BATTERY', 'PV>GRID', 'PV>CURTAIL',
  'BATTERY>LOAD', 'BATTERY>GRID', 'GRID>LOAD', 'GRID>BATTERY'];
const reportArities = {
  'HOURLY': 1, 'DAILY': 0, 'BILL': 0, 'SAVINGS': 0, 'BYPERIOD': 0,
  'DAYTYPE': 0, 'PEAKS': 1, 'PROFILE': 0, 'FLOWS': 0, 'SELFSUFF': 0,
  'CYCLES': 0, 'USAGE': 0, 'HISTOGRAM': 0, 'CHART': 1,
};

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

Never fail(String message) => throw CommandError(message);
int ceilDiv(int value, int divisor) => (value + divisor - 1) ~/ divisor;
int min3(int a, int b, int c) => math.min(a, math.min(b, c));
String field(Object value, int width) => value.toString().padLeft(width);
String bar(int width) => '|${'#' * width}${'.' * (20 - width)}|';

String money(int value) => '${value < 0 ? '-' : ''}${value.abs() ~/ 100}.'
    '${(value.abs() % 100).toString().padLeft(2, '0')}';

String percentage(int numerator, int denominator) =>
    money(denominator == 0 ? 0 : 10000 * numerator ~/ denominator);

enum Setting {
  capacity('CAPACITY', 1, 100000), initial('INITIAL', 0, 100),
  charge('CHARGE', 1, 20000), discharge('DISCHARGE', 1, 20000),
  ceff('CEFF', 1, 100), deff('DEFF', 1, 100), reserve('RESERVE', 0, 100),
  cost('COST', 0, 100000), exportLimit('EXPORT', 0, 100000),
  feedin('FEEDIN', 0, 10000), fixed('FIXED', 0, 100000),
  demand('DEMAND', 0, 100000), pvscale('PVSCALE', 0, 300);

  final String label;
  final int minimum;
  final int maximum;
  const Setting(this.label, this.minimum, this.maximum);
}

class Settings {
  final List<int> _values;
  Settings(Iterable<int> values) : _values = List.unmodifiable(values);

  int operator [](Setting item) => _values[item.index];

  Settings withValue(Setting item, int value) {
    final changed = _values.toList();
    changed[item.index] = value;
    return Settings(changed);
  }
}

enum Kind { self, tou, peakshave, backup, exportpeak }

class Strategy {
  final Kind kind;
  final int parameter;
  const Strategy(this.kind, [this.parameter = 0]);

  bool get hasParameter => const {Kind.tou, Kind.peakshave, Kind.backup}.contains(kind);
  String get text => '${kind.name.toUpperCase()}${hasParameter ? ' $parameter' : ''}';
}

List<Strategy> strategies(List<String> words) {
  final parsed = <Strategy>[];
  for (var i = 0; i < words.length; i++) {
    final name = words[i];
    Kind? kind;
    for (final candidate in Kind.values) {
      if (candidate.name.toUpperCase() == name) kind = candidate;
    }
    if (kind == null) fail('unknown strategy $name');
    var strategy = Strategy(kind);
    if (strategy.hasParameter) {
      if (++i == words.length) fail('missing parameter for $name');
      final parameter = int.parse(words[i]);
      final low = kind == Kind.tou ? 1 : 0;
      final high = kind == Kind.peakshave ? 100000 : 100;
      if (parameter < low || parameter > high) fail('invalid parameter for $name');
      strategy = Strategy(kind, parameter);
    }
    parsed.add(strategy);
  }
  return parsed;
}

Strategy oneStrategy(List<String> words) {
  final parsed = strategies(words);
  if (parsed.length != 1) fail('wrong number of arguments');
  return parsed.single;
}

typedef HourInput = ({int load, int pv, int period});
typedef Outage = ({int first, int last});
typedef Extremes = ({int low, int high});

Extremes extremes(List<int> prices) {
  var low = 0;
  var high = 0;
  for (var p = 1; p < prices.length; p++) {
    if (prices[p] < prices[low]) low = p;
    if (prices[p] > prices[high]) high = p;
  }
  return (low: low, high: high);
}

class Data {
  final List<String> periods;
  final List<HourInput> hours;
  final Set<int> holidays;
  Data(this.periods, this.hours, this.holidays);

  int get days => hours.length ~/ 24;
  bool weekend(int day) => day % 7 >= 5 || holidays.contains(day);
  String dayName(int day) => holidays.contains(day) ? 'HOL' : weekdays[day % 7];
}

class Metrics {
  int load, pv, charge, discharge, drawn, soc, imported, exported;
  int curtailed, shortfall, loss, importCost, exportIncome;

  Metrics({this.load = 0, this.pv = 0, this.charge = 0, this.discharge = 0,
    this.drawn = 0, this.soc = 0, this.imported = 0, this.exported = 0,
    this.curtailed = 0, this.shortfall = 0, this.loss = 0,
    this.importCost = 0, this.exportIncome = 0});

  int get net => importCost - exportIncome;

  void add(Metrics other) {
    load += other.load;
    pv += other.pv;
    charge += other.charge;
    discharge += other.discharge;
    drawn += other.drawn;
    soc += other.soc;
    imported += other.imported;
    exported += other.exported;
    curtailed += other.curtailed;
    shortfall += other.shortfall;
    loss += other.loss;
    importCost += other.importCost;
    exportIncome += other.exportIncome;
  }
}

class HourRecord {
  final int period;
  final Metrics values;
  final List<int> flows;
  HourRecord(this.period, this.values, this.flows);
}

class Result {
  final Settings settings;
  final List<int> prices;
  final Strategy strategy;
  final List<HourRecord> records;
  final int starting;
  final int reserve;
  final total = Metrics();
  final List<Metrics> periods;
  final List<int> periodHours;
  final flows = List<int>.filled(8, 0);
  int peak = 0;
  late final int demandCharge;
  late final int bill;

  Result(this.settings, List<int> prices, this.strategy, this.records,
      this.starting, this.reserve)
      : prices = List.unmodifiable(prices),
        periods = List.generate(prices.length, (_) => Metrics()),
        periodHours = List.filled(prices.length, 0) {
    for (final record in records) {
      total.add(record.values);
      periods[record.period].add(record.values);
      periodHours[record.period]++;
      peak = math.max(peak, record.values.imported);
      for (var i = 0; i < flows.length; i++) {
        flows[i] += record.flows[i];
      }
    }
    demandCharge = peak * settings[Setting.demand] ~/ 1000;
    bill = total.net + settings[Setting.fixed] + demandCharge;
  }

  int get endSoc => records.last.values.soc;
  String get sufficiency => percentage(math.max(0, total.load - total.imported), total.load);

  Metrics sum(Iterable<int> indices) {
    final sum = Metrics();
    for (final index in indices) {
      sum.add(records[index].values);
    }
    return sum;
  }

  Metrics day(int day) => sum(List.generate(24, (hour) => day * 24 + hour));
}

Result simulate(Data data, Settings settings, List<int> prices, Strategy strategy,
    [Outage? outage]) {
  final capacity = settings[Setting.capacity];
  final ceff = settings[Setting.ceff];
  final deff = settings[Setting.deff];
  final chargeMax = settings[Setting.charge];
  final dischargeMax = settings[Setting.discharge];
  final exportMax = settings[Setting.exportLimit];
  final reservePercent = strategy.kind == Kind.backup
      ? math.max(settings[Setting.reserve], strategy.parameter)
      : settings[Setting.reserve];
  final reserve = capacity * reservePercent ~/ 100;
  final starting = capacity * settings[Setting.initial] ~/ 100;
  final periods = extremes(prices);
  final arbitrage = strategy.kind == Kind.exportpeak &&
      settings[Setting.feedin] > prices[periods.low];
  var soc = starting;
  final records = <HourRecord>[];
  for (var i = 0; i < data.hours.length; i++) {
    final input = data.hours[i];
    final p = input.period;
    final pv = input.pv * settings[Setting.pvscale] ~/ 100;
    final direct = math.min(input.load, pv);
    var surplus = pv - direct;
    var deficit = input.load - direct;
    final x1 = min3(surplus, chargeMax, ceilDiv(100 * (capacity - soc), ceff));
    final stored1 = x1 * ceff ~/ 100;
    soc += stored1;
    surplus -= x1;
    final off = outage != null && i >= outage.first && i <= outage.last;
    final target = off ? deficit : switch (strategy.kind) {
      Kind.self || Kind.backup => deficit,
      Kind.tou => p == periods.high ? deficit : 0,
      Kind.peakshave => math.max(0, deficit - strategy.parameter),
      Kind.exportpeak => arbitrage && p == periods.low && p != periods.high ? 0 : deficit,
    };
    final lower = off ? 0 : reserve;
    final y1 = min3(ceilDiv(100 * target, deff), dischargeMax, math.max(0, soc - lower));
    final d1 = y1 * deff ~/ 100;
    soc -= y1;
    deficit -= d1;
    final gridLoad = off ? 0 : deficit;
    final e1 = off ? 0 : math.min(surplus, exportMax);
    var x2 = 0;
    var y2 = 0;
    var d2 = 0;
    if (!off) {
      var headroom = chargeMax - x1;
      int? targetSoc;
      switch (strategy.kind) {
        case Kind.tou:
          if (p == periods.low && p != periods.high) {
            targetSoc = capacity * strategy.parameter ~/ 100;
          }
          break;
        case Kind.peakshave:
          if (p == periods.low) {
            targetSoc = capacity;
            headroom = math.min(headroom, math.max(0, strategy.parameter - gridLoad));
          }
          break;
        case Kind.backup:
          if (p == periods.low) targetSoc = reserve;
          break;
        case Kind.exportpeak:
          if (arbitrage && p == periods.low && p != periods.high) targetSoc = capacity;
          break;
        case Kind.self: break;
      }
      if (targetSoc != null) {
        x2 = math.min(headroom, ceilDiv(100 * math.max(0, targetSoc - soc), ceff));
        soc += x2 * ceff ~/ 100;
      }
      if (strategy.kind == Kind.exportpeak && arbitrage && p == periods.high && x1 == 0) {
        y2 = min3(ceilDiv(100 * (exportMax - e1), deff), dischargeMax - y1,
            math.max(0, soc - reserve));
        d2 = y2 * deff ~/ 100;
        soc -= y2;
      }
    }
    final imported = gridLoad + x2;
    final exported = e1 + d2;
    final curtailed = surplus - e1;
    final values = Metrics(load: input.load, pv: pv, charge: x1 + x2,
        discharge: d1 + d2, drawn: y1 + y2, soc: soc, imported: imported,
        exported: exported, curtailed: curtailed, shortfall: off ? deficit : 0,
        loss: x1 - stored1 + x2 - x2 * ceff ~/ 100 + y1 - d1 + y2 - d2,
        importCost: imported * prices[p] ~/ 100000,
        exportIncome: exported * settings[Setting.feedin] ~/ 100000);
    records.add(HourRecord(p, values,
        [direct, x1, e1, curtailed, d1, d2, gridLoad, x2]));
  }
  return Result(settings, prices, strategy, records, starting, reserve);
}

Result baseline(Data data, Settings settings, List<int> prices) =>
    simulate(data, settings.withValue(Setting.capacity, 0), prices, const Strategy(Kind.self));

class Dispatch {
  final Data data;
  final Settings initialSettings;
  final List<int> initialPrices;
  Settings settings;
  List<int> prices;
  Result? current;
  final output = StringBuffer();

  Dispatch(this.data, this.initialSettings, List<int> prices)
      : settings = initialSettings, initialPrices = List.unmodifiable(prices),
        prices = prices.toList();

  void emit(String line) => output.writeln(line);
  Result get result => current ?? (fail('no run'));

  void arity(List<String> args, int count) {
    if (args.length != count) fail('wrong number of arguments');
  }

  int dayArgument(String text) {
    final day = int.parse(text);
    if (day < 1 || day > data.days) fail('invalid day');
    return day - 1;
  }

  Setting itemArgument(String text) {
    for (final item in Setting.values) {
      if (item.label == text) return item;
    }
    fail('unknown parameter $text');
  }

  void validateRange(int low, int high, int step, Setting item) {
    if (low < item.minimum || high > item.maximum || high < low ||
        step < 1 || (high - low) ~/ step + 1 > 20) fail('invalid range');
  }

  void table(Iterable<Object> values, [int firstWidth = 4, int width = 7]) {
    final row = values.toList();
    emit(field(row.first, firstWidth) + row.skip(1).map((value) => field(value, width)).join());
  }

  void config() {
    final s = settings;
    final bounds = extremes(prices);
    emit('BATTERY capacity ${s[Setting.capacity]} initial ${s[Setting.initial]} '
        'charge ${s[Setting.charge]} discharge ${s[Setting.discharge]} '
        'ceff ${s[Setting.ceff]} deff ${s[Setting.deff]} reserve ${s[Setting.reserve]} cost ${s[Setting.cost]}');
    emit('GRID export ${s[Setting.exportLimit]} feedin ${s[Setting.feedin]} '
        'fixed ${s[Setting.fixed]} demand ${s[Setting.demand]}');
    emit('SOLAR pvscale ${s[Setting.pvscale]}');
    emit('TARIFF ${List.generate(prices.length, (p) => '${data.periods[p]} ${prices[p]}').join(' ')} '
        'cheapest ${data.periods[bounds.low]} peak ${data.periods[bounds.high]}');
  }

  void compare(List<String> args) {
    final parsed = strategies(args);
    if (parsed.isEmpty) fail('wrong number of arguments');
    final base = baseline(data, settings, prices);
    final rows = [for (var i = 0; i < parsed.length; i++)
      (order: i, result: simulate(data, settings, prices, parsed[i]))];
    rows.sort((a, b) => a.result.bill != b.result.bill
        ? a.result.bill.compareTo(b.result.bill) : a.order.compareTo(b.order));
    emit('COMPARE baseline ${money(base.bill)}');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i].result;
      emit('${i + 1}. ${r.strategy.text} bill ${money(r.bill)} '
          'saving ${money(base.bill - r.bill)} sufficiency ${r.sufficiency}%');
    }
  }

  void size(List<String> args) {
    arity(args, 3);
    final low = int.parse(args[0]);
    final high = int.parse(args[1]);
    final step = int.parse(args[2]);
    validateRange(low, high, step, Setting.capacity);
    final base = baseline(data, settings, prices);
    ({int capacity, int cost, int saving})? best;
    for (var capacity = low; capacity <= high; capacity += step) {
      final changed = settings.withValue(Setting.capacity, capacity);
      final trial = simulate(data, changed, prices, const Strategy(Kind.self));
      final saving = base.bill - trial.bill;
      final cost = capacity * settings[Setting.cost] ~/ 1000;
      var payback = 'never';
      if (saving > 0) {
        final value = 10 * cost ~/ saving;
        payback = '${value ~/ 10}.${value % 10}';
        if (best == null || cost * best.saving < best.cost * saving) {
          best = (capacity: capacity, cost: cost, saving: saving);
        }
      }
      emit('SIZE $capacity bill ${money(trial.bill)} saving ${money(saving)} '
          'cost ${money(cost)} payback $payback');
    }
    emit('BEST ${best?.capacity ?? 'none'}');
  }

  void sweep(List<String> args) {
    if (args.length < 5) fail('wrong number of arguments');
    final item = itemArgument(args[0]);
    final low = int.parse(args[1]);
    final high = int.parse(args[2]);
    final step = int.parse(args[3]);
    validateRange(low, high, step, item);
    final strategy = oneStrategy(args.sublist(4));
    ({int value, int bill})? best;
    for (var value = low; value <= high; value += step) {
      final changed = settings.withValue(item, value);
      final trial = simulate(data, changed, prices, strategy);
      final base = baseline(data, changed, prices);
      emit('SWEEP ${item.label} $value bill ${money(trial.bill)} '
          'saving ${money(base.bill - trial.bill)} sufficiency ${trial.sufficiency}%');
      if (best == null || trial.bill < best.bill) best = (value: value, bill: trial.bill);
    }
    emit('BEST ${best!.value}');
  }

  void outage(List<String> args) {
    arity(args, 3);
    final day = dayArgument(args[0]);
    final start = int.parse(args[1]);
    final end = int.parse(args[2]);
    if (start < 0 || end > 23 || start > end) fail('invalid hours');
    final saved = result;
    final first = day * 24 + start;
    final last = day * 24 + end;
    final trial = simulate(data, saved.settings, saved.prices, saved.strategy,
        (first: first, last: last));
    final before = first == 0 ? trial.starting : trial.records[first - 1].values.soc;
    emit('OUTAGE day ${day + 1} hours $start-$end strategy ${saved.strategy.text} soc $before');
    emit('hour   load     pv  disch    soc  short   curt');
    final total = Metrics();
    for (var i = first; i <= last; i++) {
      final v = trial.records[i].values;
      total.add(v);
      table([i % 24, v.load, v.pv, v.discharge, v.soc, v.shortfall, v.curtailed]);
    }
    final served = total.load == 0 ? '100.00' : percentage(total.load - total.shortfall, total.load);
    emit('TOTAL load ${total.load} unserved ${total.shortfall} served $served% bill ${money(trial.bill)}');
  }

  void difference(List<String> args) {
    if (args.length < 2) fail('wrong number of arguments');
    final day = dayArgument(args[0]);
    final strategy = oneStrategy(args.sublist(1));
    final saved = result;
    final trial = simulate(data, saved.settings, saved.prices, strategy);
    emit('DIFF day ${day + 1} ${data.dayName(day)} ${saved.strategy.text} vs ${strategy.text}');
    emit('hour   imp1   imp2   exp1   exp2   soc1   soc2');
    for (var hour = 0; hour < 24; hour++) {
      final a = saved.records[day * 24 + hour].values;
      final b = trial.records[day * 24 + hour].values;
      table([hour, a.imported, b.imported, a.exported, b.exported, a.soc, b.soc]);
    }
    final cost1 = saved.day(day).net;
    final cost2 = trial.day(day).net;
    emit('TOTAL cost1 ${money(cost1)} cost2 ${money(cost2)} difference ${money(cost2 - cost1)}');
  }

  void hourly(Result r, int day) {
    emit('HOURLY day ${day + 1} ${data.dayName(day)} strategy ${r.strategy.text}');
    emit('hour   load     pv charge  disch    soc import export   curt');
    for (var hour = 0; hour < 24; hour++) {
      final v = r.records[day * 24 + hour].values;
      table([hour, v.load, v.pv, v.charge, v.discharge, v.soc, v.imported, v.exported, v.curtailed]);
    }
    final v = r.day(day);
    table(['sum', v.load, v.pv, v.charge, v.discharge, '', v.imported, v.exported, v.curtailed]);
  }

  void daily(Result r) {
    emit('DAILY strategy ${r.strategy.text}');
    emit('day name    load      pv  import  export    curt     soc      cost');
    for (var day = 0; day < data.days; day++) {
      final v = r.day(day);
      final values = [v.load, v.pv, v.imported, v.exported, v.curtailed, r.records[day * 24 + 23].values.soc];
      emit(field(day + 1, 3) + field(data.dayName(day), 5) +
          values.map((value) => field(value, 8)).join() + field(money(v.net), 10));
    }
    final v = r.total;
    emit('TOTAL load ${v.load} pv ${v.pv} import ${v.imported} export ${v.exported} '
        'curtailed ${v.curtailed} cost ${money(v.net)}');
  }

  void bill(Result r) {
    emit('BILL strategy ${r.strategy.text} days ${data.days}');
    for (var p = 0; p < data.periods.length; p++) {
      emit('IMPORT ${data.periods[p]} ${r.periods[p].imported} Wh ${money(r.periods[p].importCost)}');
    }
    emit('EXPORT ${r.total.exported} Wh ${money(-r.total.exportIncome)}');
    emit('FIXED ${money(r.settings[Setting.fixed])}');
    emit('DEMAND ${r.peak} Wh ${money(r.demandCharge)}');
    emit('TOTAL ${money(r.bill)}');
  }

  void savings(Result r) {
    final base = baseline(data, r.settings, r.prices);
    emit('SAVINGS strategy ${r.strategy.text}');
    void row(String name, int before, int after) =>
        emit('$name ${money(before)} -> ${money(after)} saving ${money(before - after)}');
    for (var p = 0; p < data.periods.length; p++) {
      row(data.periods[p], base.periods[p].importCost, r.periods[p].importCost);
    }
    row('EXPORT', -base.total.exportIncome, -r.total.exportIncome);
    row('DEMAND', base.demandCharge, r.demandCharge);
    row('TOTAL', base.bill, r.bill);
  }

  void dayType(Result r) {
    emit('DAYTYPE strategy ${r.strategy.text}');
    for (final weekend in [false, true]) {
      var count = 0;
      final total = Metrics();
      for (var day = 0; day < data.days; day++) {
        if (data.weekend(day) != weekend) continue;
        count++;
        total.add(r.day(day));
      }
      emit('${weekend ? 'WEEKEND' : 'WEEKDAY'} days $count load ${total.load ~/ count} '
          'pv ${total.pv ~/ count} import ${total.imported ~/ count} '
          'export ${total.exported ~/ count} cost ${money(total.net ~/ count)}');
    }
  }

  void peaks(Result r, int count) {
    emit('PEAKS strategy ${r.strategy.text}');
    final indices = [for (var i = 0; i < r.records.length; i++)
      if (r.records[i].values.imported > 0) i];
    indices.sort((a, b) {
      final order = r.records[b].values.imported.compareTo(r.records[a].values.imported);
      return order == 0 ? a.compareTo(b) : order;
    });
    if (indices.isEmpty) emit('none');
    for (var rank = 0; rank < math.min(count, indices.length); rank++) {
      final index = indices[rank];
      final record = r.records[index];
      final v = record.values;
      emit('${rank + 1}. day ${index ~/ 24 + 1} hour ${index % 24} '
          '${data.periods[record.period]} import ${v.imported} load ${v.load} soc ${v.soc}');
    }
  }

  void usage(Result r) {
    var charging = 0;
    var discharging = 0;
    var idle = 0;
    var full = 0;
    var low = 0;
    var streak = 0;
    var longest = 0;
    var first = 0;
    for (var i = 0; i < r.records.length; i++) {
      final v = r.records[i].values;
      if (v.charge > 0) charging++;
      if (v.drawn > 0) discharging++;
      if (v.charge == 0 && v.drawn == 0) idle++;
      if (v.soc == r.settings[Setting.capacity]) full++;
      if (v.soc <= r.reserve) {
        low++;
        streak++;
        if (streak > longest) {
          longest = streak;
          first = i - streak + 1;
        }
      } else {
        streak = 0;
      }
    }
    emit('USAGE charging $charging discharging $discharging idle $idle full $full '
        'low $low longest $longest${longest == 0 ? '' : ' from day ${first ~/ 24 + 1} hour ${first % 24}'}');
  }

  void report(String command, Result r, int argument) {
    switch (command) {
      case 'HOURLY': hourly(r, argument); break;
      case 'DAILY': daily(r); break;
      case 'BILL': bill(r); break;
      case 'SAVINGS': savings(r); break;
      case 'DAYTYPE': dayType(r); break;
      case 'PEAKS': peaks(r, argument); break;
      case 'USAGE': usage(r); break;
      case 'BYPERIOD':
        emit('BYPERIOD strategy ${r.strategy.text}');
        for (var p = 0; p < data.periods.length; p++) {
          final v = r.periods[p];
          emit('${data.periods[p]} hours ${r.periodHours[p]} load ${v.load} pv ${v.pv} '
              'charge ${v.charge} discharge ${v.discharge} import ${v.imported} export ${v.exported}');
        }
        break;
      case 'PROFILE':
        emit('PROFILE strategy ${r.strategy.text} days ${data.days}');
        emit('hour   load     pv import export    soc');
        for (var hour = 0; hour < 24; hour++) {
          final v = r.sum(List.generate(data.days, (day) => day * 24 + hour));
          table([hour, v.load ~/ data.days, v.pv ~/ data.days, v.imported ~/ data.days,
            v.exported ~/ data.days, v.soc ~/ data.days]);
        }
        break;
      case 'FLOWS':
        emit('FLOWS strategy ${r.strategy.text}');
        for (var i = 0; i < flowNames.length; i++) {
          emit('${flowNames[i]} ${r.flows[i]}');
        }
        emit('LOSSES ${r.total.loss}');
        emit('STORED ${r.endSoc - r.starting}');
        break;
      case 'SELFSUFF':
        emit('SELFSUFF sufficiency ${r.sufficiency}% '
            'consumption ${percentage(r.flows[0] + r.flows[1], r.total.pv)}%');
        break;
      case 'CYCLES': {
        final drawn = r.total.drawn;
        final capacity = r.settings[Setting.capacity];
        final divisor = drawn.gcd(capacity);
        final value = 1000 * drawn ~/ capacity;
        emit('CYCLES ${drawn ~/ divisor}/${capacity ~/ divisor} '
            '${value ~/ 1000}.${(value % 1000).toString().padLeft(3, '0')} '
            'drawn $drawn losses ${r.total.loss}');
        break;
      }
      case 'HISTOGRAM': {
        emit('HISTOGRAM strategy ${r.strategy.text}');
        final counts = List<int>.filled(10, 0);
        for (final record in r.records) {
          counts[math.min(9, 10 * record.values.soc ~/ r.settings[Setting.capacity])]++;
        }
        for (var i = 0; i < counts.length; i++) {
          emit('${field(i * 10, 3)}% ${bar(20 * counts[i] ~/ r.records.length)} ${counts[i]}');
        }
        break;
      }
      case 'CHART':
        emit('CHART day ${argument + 1} ${data.dayName(argument)} strategy ${r.strategy.text}');
        for (var hour = 0; hour < 24; hour++) {
          final soc = r.records[argument * 24 + hour].values.soc;
          final capacity = r.settings[Setting.capacity];
          emit('${field(hour, 2)} ${bar(20 * soc ~/ capacity)} ${percentage(soc, capacity)}%');
        }
        break;
    }
  }

  bool execute(String line) {
    final words = line.split(' ');
    final command = words[0];
    final args = words.sublist(1);
    try {
      final count = reportArities[command];
      if (count != null) {
        arity(args, count);
        var argument = 0;
        if (command == 'HOURLY' || command == 'CHART') argument = dayArgument(args[0]);
        if (command == 'PEAKS') {
          argument = int.parse(args[0]);
          if (argument < 1) fail('invalid count');
        }
        report(command, result, argument);
        return false;
      }
      switch (command) {
        case 'END': arity(args, 0); return true;
        case 'RUN': {
          final strategy = oneStrategy(args);
          final trial = simulate(data, settings, prices, strategy);
          current = trial;
          emit('RUN ${strategy.text} bill ${money(trial.bill)} import ${trial.total.imported} '
              'export ${trial.total.exported} soc ${trial.endSoc}');
          break;
        }
        case 'SET': {
          arity(args, 2);
          final item = itemArgument(args[0]);
          final value = int.parse(args[1]);
          if (value < item.minimum || value > item.maximum) fail('invalid value for ${item.label}');
          final previous = settings[item];
          settings = settings.withValue(item, value);
          emit('SET ${item.label} $previous -> $value');
          break;
        }
        case 'PRICE': {
          arity(args, 2);
          final p = data.periods.indexOf(args[0]);
          if (p < 0) fail('unknown period ${args[0]}');
          final value = int.parse(args[1]);
          if (value < 0 || value > 10000) fail('invalid value for ${args[0]}');
          final previous = prices[p];
          prices[p] = value;
          final bounds = extremes(prices);
          emit('PRICE ${args[0]} $previous -> $value cheapest ${data.periods[bounds.low]} '
              'peak ${data.periods[bounds.high]}');
          break;
        }
        case 'RESET':
          arity(args, 0);
          settings = initialSettings;
          prices = initialPrices.toList();
          emit('RESET');
          break;
        case 'CONFIG': arity(args, 0); config(); break;
        case 'NOBATTERY': {
          arity(args, 0);
          final base = baseline(data, settings, prices);
          emit('NOBATTERY bill ${money(base.bill)} import ${base.total.imported} '
              'export ${base.total.exported} curtailed ${base.total.curtailed} peak ${base.peak}');
          break;
        }
        case 'COMPARE': compare(args); break;
        case 'SIZE': size(args); break;
        case 'SWEEP': sweep(args); break;
        case 'OUTAGE': outage(args); break;
        case 'DIFF': difference(args); break;
        default: fail('unknown command $command');
      }
    } on CommandError catch (error) {
      emit('ERROR ${error.message}');
    }
    return false;
  }
}

Dispatch readInput() {
  List<String> words() => stdin.readLineSync()!.split(' ');
  final battery = words().skip(1).map(int.parse).toList();
  final grid = words().skip(1).map(int.parse).toList();
  final settings = Settings([...battery, ...grid, 100]);
  final periodCount = int.parse(words()[1]);
  final names = <String>[];
  final prices = <int>[];
  for (var i = 0; i < periodCount; i++) {
    final line = words();
    names.add(line[0]);
    prices.add(int.parse(line[1]));
  }
  final divisions = <List<int>>[];
  for (var type = 0; type < 2; type++) {
    final line = words();
    final hours = List<int>.filled(24, 0);
    for (var i = 1; i < line.length; i += 2) {
      final start = int.parse(line[i]);
      final end = i + 2 < line.length ? int.parse(line[i + 2]) : 24;
      final period = names.indexOf(line[i + 1]);
      hours.fillRange(start, end, period);
    }
    divisions.add(hours);
  }
  final profileCount = int.parse(words()[1]);
  final profiles = <(String, String), List<int>>{};
  for (var i = 0; i < profileCount; i++) {
    final line = words();
    profiles[(line[0], line[1])] = line.skip(2).map(int.parse).toList();
  }
  final days = int.parse(words()[1]);
  final hours = <HourInput>[];
  for (var day = 0; day < days; day++) {
    final line = words();
    final load = profiles[('LOAD', line[0])]!;
    final pv = profiles[('PV', line[2])]!;
    final loadPercent = int.parse(line[1]);
    final pvPercent = int.parse(line[3]);
    for (var hour = 0; hour < 24; hour++) {
      hours.add((load: load[hour] * loadPercent ~/ 100,
          pv: pv[hour] * pvPercent ~/ 100, period: 0));
    }
  }
  final holidays = words().skip(2).map((word) => int.parse(word) - 1).toSet();
  final data = Data(names, hours, holidays);
  for (var i = 0; i < hours.length; i++) {
    final input = hours[i];
    hours[i] = (load: input.load, pv: input.pv,
        period: divisions[data.weekend(i ~/ 24) ? 1 : 0][i % 24]);
  }
  final overrides = int.parse(words()[1]);
  for (var i = 0; i < overrides; i++) {
    final line = words().map(int.parse).toList();
    final index = (line[0] - 1) * 24 + line[1];
    hours[index] = (load: line[2], pv: line[3], period: hours[index].period);
  }
  return Dispatch(data, settings, prices);
}

void main() {
  final dispatch = readInput();
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || dispatch.execute(line)) break;
  }
  stdout.write(dispatch.output);
}
