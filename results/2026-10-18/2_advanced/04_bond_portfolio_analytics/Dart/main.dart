import 'dart:io';
import 'dates_calendar.dart';
import 'daycount.dart';
import 'schedule.dart';
import 'pricing.dart';
import 'curve.dart';

const bondTypes = ['FIXED', 'ZERO', 'AMORT', 'FRN'];
const frequencies = {1, 2, 4, 12};
const optionKeys = {'FIXED': {'EOM', 'LONG', 'CALL'}, 'ZERO': {'EOM', 'LONG'}, 'AMORT': {'EOM', 'LONG', 'SINK'}, 'FRN': {'EOM', 'LONG', 'LAG', 'CAP', 'FLOOR'}};
const bucketNames = ['0-1Y', '1-3Y', '3-5Y', '5-10Y', '10Y+'];
typedef Scenario = (String, List<double>);
class InputError implements Exception { final String message; InputError(this.message); }
int rounded(int a, int b) => (2 * a + b) ~/ (2 * b);
String hundredths(int value) { final magnitude = value < 0 ? -value : value; return '${value < 0 ? '-' : ''}${magnitude ~/ 100}.${(magnitude % 100).toString().padLeft(2, '0')}'; }
String decimals(double value, int digits) {
  var scale = 1; for (var index = 0; index < digits; index++) scale *= 10;
  final magnitude = value < 0 ? -value : value, integer = (magnitude * scale + 0.5).toInt();
  return '${value < 0 && integer != 0 ? '-' : ''}${integer ~/ scale}.${(integer % scale).toString().padLeft(digits, '0')}';
}
String percent(double value) => decimals(value * 100, 4);
String amount(double cents) => decimals(cents / 100, 2);
int thousandths(String text) { final parts = text.split('.'); return int.parse(parts[0]) * 1000 + int.parse(parts[1]); }
List<String> readLines(String name) => File('input/$name').readAsStringSync().split('\n')..removeLast();
List<(int, List<String>)> rows(String name) { final lines = readLines(name); return [for (var index = 1; index < lines.length; index++) (index + 1, lines[index].split(','))]; }
void writeLines(String name, List<String> lines) => File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
List<String> sortedKeys<T>(Map<String, T> map) => map.keys.toList()..sort();
void record(List<String> errors, String file, int number, String key, String message) => errors.add('$file:$number: $key: $message');

class Options {
  bool eom = false, long = false;
  int? lag, cap, floor;
  final List<(String, int)> sinks = [], calls = [];
}
Options parseOptions(String kind, String text) {
  final options = Options(), seen = <String>{};
  for (final item in text == '-' ? <String>[] : text.split(';')) {
    final equal = item.indexOf('='), key = equal < 0 ? item : item.substring(0, equal), value = equal < 0 ? '' : item.substring(equal + 1);
    if (!optionKeys[kind]!.contains(key) || (!seen.add(key) && key != 'SINK' && key != 'CALL')) throw InputError('invalid option');
    if (key == 'EOM') options.eom = true;
    else if (key == 'LONG') options.long = true;
    else if (key == 'LAG') options.lag = int.parse(value);
    else if (key == 'CAP') options.cap = int.parse(value);
    else if (key == 'FLOOR') options.floor = int.parse(value);
    else { final parts = value.split(':'); (key == 'SINK' ? options.sinks : options.calls).add((parts[0], key == 'SINK' ? int.parse(parts[1]) : thousandths(parts[1]))); }
  }
  if (kind == 'FRN' && (options.lag == null || options.lag! < 1 || options.lag! > 5 || (options.cap ?? 1200) > 1200 || (options.floor ?? 0) > (options.cap ?? 1200))) throw InputError('invalid option');
  return options;
}
List<(int, int)> scheduleDays(List<(String, int)> items, List<int> dates, String error) {
  final inner = dates.sublist(1, dates.length - 1).toSet(), result = <(int, int)>[];
  var last = -1;
  for (final (text, value) in items) {
    if (!validDate(text)) throw InputError(error);
    final day = parseDate(text);
    if (!inner.contains(day) || day <= last) throw InputError(error);
    result.add((day, value)); last = day;
  }
  return result;
}
int? latestFixing(List<(int, int)> fixings, int day) {
  var low = 0, high = fixings.length;
  while (low < high) { final middle = (low + high) ~/ 2; if (fixings[middle].$1 <= day) low = middle + 1; else high = middle; }
  return low == 0 ? null : fixings[low - 1].$2;
}
class Period {
  final int number, start, end, payment, n, m, rate, opening, coupon, principal;
  int get cash => coupon + principal;
  Period(this.number, this.start, this.end, this.payment, this.n, this.m, this.rate, this.opening, this.coupon, this.principal);
}
class Bond {
  final String code, kind, daycount;
  final int issue, maturity, frequency, face;
  final List<(int, int)> calls;
  final List<Period> periods;
  Bond(this.code, this.kind, this.issue, this.maturity, this.frequency, this.daycount, this.face, this.calls, this.periods);
}
Bond parseBond(List<String> fields, Set<String> seen, Calendar calendar, List<(int, int)> fixings) {
  final code = fields[0], kind = fields[1], coupon = int.parse(fields[4]), frequency = int.parse(fields[5]), daycount = fields[6], bdc = fields[7], face = int.parse(fields[8]);
  if (seen.contains(code)) throw InputError('duplicate id');
  if (!bondTypes.contains(kind)) throw InputError('unknown type');
  if (!validDate(fields[2]) || !validDate(fields[3])) throw InputError('invalid date');
  final issue = parseDate(fields[2]), maturity = parseDate(fields[3]);
  if (maturity <= issue) throw InputError('maturity not after issue');
  if (!frequencies.contains(frequency)) throw InputError('invalid frequency');
  if (!dayCounts.contains(daycount)) throw InputError('unknown day count');
  if (!businessDayRules.contains(bdc)) throw InputError('unknown business day rule');
  if (face % 100000 != 0 || face > 10000000) throw InputError('invalid face');
  if (coupon > 1200 || kind == 'ZERO' && coupon != 0) throw InputError('invalid coupon');
  final options = parseOptions(kind, fields[9]), dates = couponSchedule(issue, maturity, frequency, options.eom, options.long);
  final sinks = <int, int>{}; var total = 0;
  for (final (day, value) in scheduleDays(options.sinks, dates, 'invalid sinking fund')) { if (value == 0) throw InputError('invalid sinking fund'); sinks[day] = value; total += value; }
  if (kind == 'AMORT' && (total == 0 || total >= face)) throw InputError('invalid sinking fund');
  final calls = scheduleDays(options.calls, dates, 'invalid call schedule');
  if (calls.any((call) => call.$2 < 100000 || call.$2 > 110000)) throw InputError('invalid call schedule');
  final periods = <Period>[]; var opening = face;
  for (var number = 1; number < dates.length; number++) {
    final start = dates[number - 1], end = dates[number], fraction = yearFraction(daycount, start, end);
    var rate = kind == 'ZERO' ? 0 : coupon;
    if (kind == 'FRN') {
      final fixing = latestFixing(fixings, calendar.move(calendar.adjust(start, bdc), -options.lag!));
      if (fixing == null) throw InputError('missing fixing');
      rate = fixing + coupon;
      if (options.floor != null && rate < options.floor!) rate = options.floor!;
      if (options.cap != null && rate > options.cap!) rate = options.cap!;
    }
    final principal = number == dates.length - 1 ? opening : (sinks[end] ?? 0), couponAmount = rounded(opening * rate * fraction.$1, 10000 * fraction.$2);
    periods.add(Period(number, start, end, calendar.adjust(end, bdc), fraction.$1, fraction.$2, rate, opening, couponAmount, principal));
    opening -= principal;
  }
  return Bond(code, kind, issue, maturity, frequency, daycount, face, calls, periods);
}
class Valuation {
  final Bond bond;
  final int clean;
  late List<Period> remaining, cashflows;
  late List<(int, double)> flows;
  late int outstanding, cleanAmount, unitValue, workout, nextPayment;
  late double accrued, target, fraction;
  late YieldPricer pricer;
  late Risk risk;
  double ytm = 0, ytw = 0, wal = 0, curveClean = 0, spread = 0;
  Valuation(this.bond, this.clean, int settlement) {
    final index = bond.periods.indexWhere((period) => period.end > settlement), current = bond.periods[index];
    remaining = bond.periods.sublist(index); outstanding = current.opening;
    final (n, m) = yearFraction(bond.daycount, current.start, settlement);
    accrued = current.rate * n / (100 * m);
    final accruedAmount = rounded(outstanding * current.rate * n, 10000 * m);
    cleanAmount = rounded(outstanding * clean, 100000); unitValue = cleanAmount + accruedAmount; target = clean / 1000 + accrued;
    final remainingFraction = yearFraction(bond.daycount, settlement, current.end);
    fraction = bond.frequency * remainingFraction.$1 / remainingFraction.$2;
    cashflows = remaining.where((period) => period.cash >= 1).toList(); flows = cashflows.map((period) => (period.payment - settlement, period.cash.toDouble())).toList();
    pricer = YieldPricer(remaining.map((period) => period.cash).toList(), fraction, bond.frequency, outstanding);
    workout = bond.maturity; nextPayment = cashflows.first.payment;
  }
  void analyze(ZeroCurve curve, int settlement) {
    ytm = pricer.solve(target); risk = pricer.risk(ytm); ytw = ytm;
    for (final (day, price) in bond.calls) {
      if (day <= settlement) continue;
      final values = <int>[];
      for (final period in remaining) { values.add(period.coupon); if (period.end == day) { values[values.length - 1] += rounded(period.opening * price, 100000); break; } }
      final rate = YieldPricer(values, fraction, bond.frequency, outstanding).solve(target);
      if (rate < ytw) { ytw = rate; workout = day; }
    }
    var principalDays = 0;
    for (final period in cashflows) principalDays += period.principal * (period.payment - settlement);
    wal = principalDays / (365 * outstanding); curveClean = curve.presentValue(flows) * 100 / outstanding - accrued; spread = zSpread(curve, flows, unitValue);
  }
}
class Position {
  final Valuation valuation;
  final int units, book;
  Position(this.valuation, this.units, this.book);
  int get value => units * valuation.unitValue;
  int get face => units * valuation.bond.face;
  int get outstanding => units * valuation.outstanding;
  int get gain => units * valuation.cleanAmount - book;
  double get dv01 => valuation.risk.dv01 * units * valuation.outstanding / 10000;
  double pv(ZeroCurve curve) => units * curve.presentValue(valuation.flows, valuation.spread);
}
class GroupStat {
  int count = 0, value = 0;
  double duration = 0, dv01 = 0;
  void add(Position position) { count++; value += position.value; duration += position.value * position.valuation.risk.modified; dv01 += position.dv01; }
}
class ScenarioResult {
  final String name;
  final List<double> values, pnls;
  final double total, pnl;
  ScenarioResult(this.name, this.values, this.pnls, this.total, this.pnl);
}
class Portfolio {
  final String name;
  final List<Position> positions;
  late int total;
  int income = 0;
  double ytm = 0, modified = 0, convexity = 0, spread = 0, dv01 = 0, cashYield = 0, base = 0, effective = 0;
  final List<double> baseValues = [], keyRates = [];
  final Map<String, GroupStat> types = {for (final kind in bondTypes) kind: GroupStat()}, buckets = {for (final bucket in bucketNames) bucket: GroupStat()};
  final Map<int, (int, int)> ladder = {};
  final List<ScenarioResult> results = [];
  Portfolio(this.name, this.positions) { total = positions.fold(0, (sum, position) => sum + position.value); }
  double weight(int value) => value * 100 / total;
  double pv(ZeroCurve curve) { var sum = 0.0; for (final position in positions) sum += position.pv(curve); return sum; }
  double rateDuration(ZeroCurve curve, int? pillar) {
    final down = List<double>.filled(curve.rates.length, 0.0), up = List<double>.filled(curve.rates.length, 0.0);
    for (var index = 0; index < down.length; index++) if (pillar == null || pillar == index) { down[index] = -basisPoint; up[index] = basisPoint; }
    return (pv(curve.shifted(down)) - pv(curve.shifted(up))) / (2 * basisPoint * base);
  }
  void analyze(ZeroCurve curve, List<Scenario> scenarios, int settlement) {
    final flows = <(int, double)>[];
    for (final position in positions) {
      final v = position.valuation, value = position.value;
      ytm += value * v.ytm; modified += value * v.risk.modified; convexity += value * v.risk.convexity; spread += value * v.spread; dv01 += position.dv01;
      types[v.bond.kind]!.add(position);
      final days = v.bond.maturity - settlement, bucket = days < 365 ? 0 : days < 1095 ? 1 : days < 1825 ? 2 : days < 3650 ? 3 : 4;
      buckets[bucketNames[bucket]]!.add(position);
      for (final period in v.cashflows) {
        final days = period.payment - settlement; flows.add((days, (position.units * period.cash).toDouble()));
        if (days <= 365) income += position.units * period.coupon;
        final year = civilDate(period.payment).$1, sums = ladder[civilDate(period.payment).$1] ?? (0, 0);
        ladder[year] = (sums.$1 + position.units * period.coupon, sums.$2 + position.units * period.principal);
      }
      baseValues.add(position.pv(curve));
    }
    ytm /= total; modified /= total; convexity /= total; spread /= total;
    cashYield = bisection((rate) => ZeroCurve([0], [rate]).presentValue(flows), 0.0, 1.0, total.toDouble());
    for (final value in baseValues) base += value;
    effective = rateDuration(curve, null);
    for (var index = 0; index < curve.rates.length; index++) keyRates.add(rateDuration(curve, index));
    for (final (scenarioName, deltas) in <Scenario>[('BASE', List.filled(curve.rates.length, 0.0)), ...scenarios]) {
      final shifted = curve.shifted(deltas), values = <double>[], pnls = <double>[]; var sum = 0.0;
      for (var index = 0; index < positions.length; index++) { final value = positions[index].pv(shifted); values.add(value); pnls.add(value - baseValues[index]); sum += value; }
      results.add(ScenarioResult(scenarioName, values, pnls, sum, sum - base));
    }
  }
  List<String> report() {
    final lines = ['portfolio $name']; var face = 0, outstanding = 0, book = 0, gain = 0;
    for (final position in positions) {
      final v = position.valuation;
      lines.add('position ${v.bond.code} face ${hundredths(position.face)} outstanding ${hundredths(position.outstanding)} clean ${decimals(v.clean / 1000, 6)} value ${hundredths(position.value)} weight ${decimals(weight(position.value), 4)} book ${hundredths(position.book)} gain ${hundredths(position.gain)} ytm ${percent(v.ytm)} modified ${decimals(v.risk.modified, 4)} dv01 ${decimals(position.dv01, 2)}');
      face += position.face; outstanding += position.outstanding; book += position.book; gain += position.gain;
    }
    lines.add('total positions ${positions.length} face ${hundredths(face)} outstanding ${hundredths(outstanding)} value ${hundredths(total)} book ${hundredths(book)} gain ${hundredths(gain)} income ${hundredths(income)}');
    lines.add('risk ytm ${percent(ytm)} yield ${percent(cashYield)} modified ${decimals(modified, 4)} convexity ${decimals(convexity, 4)} zspread ${percent(spread)} dv01 ${decimals(dv01, 2)}');
    lines.add('curve effective ${decimals(effective, 4)} krd ${keyRates.map((value) => decimals(value, 4)).join(' ')}');
    for (final (label, groups) in [('type', types), ('bucket', buckets)]) for (final entry in groups.entries) {
      final group = entry.value;
      lines.add('$label ${entry.key} positions ${group.count} value ${hundredths(group.value)} weight ${decimals(weight(group.value), 4)} duration ${decimals(group.duration / total, 4)} dv01 ${decimals(group.dv01, 2)}');
    }
    var coupons = 0, principals = 0;
    final years = ladder.keys.toList()..sort();
    for (final year in years) { final (coupon, principal) = ladder[year]!; lines.add('ladder $year coupon ${hundredths(coupon)} principal ${hundredths(principal)} total ${hundredths(coupon + principal)}'); coupons += coupon; principals += principal; }
    lines.add('ladder total coupon ${hundredths(coupons)} principal ${hundredths(principals)} total ${hundredths(coupons + principals)}');
    ScenarioResult? worst;
    for (final result in results.skip(1)) if (worst == null || result.pnl < worst.pnl) worst = result;
    if (worst != null) {
      final stress = worst;
      final order = List.generate(positions.length, (index) => index)..sort((a, b) => stress.pnls[a] != stress.pnls[b] ? stress.pnls[a].compareTo(stress.pnls[b]) : positions[a].valuation.bond.code.compareTo(positions[b].valuation.bond.code));
      final parts = ['stress worst', stress.name, 'pnl', amount(stress.pnl), 'losers'];
      for (final index in order.take(3)) { parts.add(positions[index].valuation.bond.code); parts.add(amount(stress.pnls[index])); }
      lines.add(parts.join(' '));
    }
    return lines;
  }
  List<String> scenarioLines() => [for (final result in results) ...[
    for (var index = 0; index < positions.length; index++) '$name,${result.name},${positions[index].valuation.bond.code},${amount(result.values[index])},${amount(result.pnls[index])}',
    '$name,${result.name},*,${amount(result.total)},${amount(result.pnl)}',
  ]];
  List<String> compliance(List<List<String>> limits, int settlement) {
    final lines = <String>[]; var breaches = 0;
    for (final words in limits) {
      final kind = words[0]; String detail; bool breach;
      if (kind == 'position_weight') {
        final limit = int.parse(words[1]); var largest = positions.first;
        for (final position in positions) if (position.value > largest.value) largest = position;
        detail = '${largest.valuation.bond.code} ${decimals(weight(largest.value), 4)} limit ${hundredths(limit)}'; breach = largest.value * 10000 > limit * total;
      } else if (kind == 'type_weight') {
        final limit = int.parse(words[2]), value = types[words[1]]!.value; detail = '${words[1]} ${decimals(weight(value), 4)} limit ${hundredths(limit)}'; breach = value * 10000 > limit * total;
      } else if (kind == 'max_maturity') {
        final years = int.parse(words[1]), count = positions.where((position) => position.valuation.bond.maturity - settlement > 365 * int.parse(words[1])).length;
        detail = '${years}Y positions $count'; breach = count > 0;
      } else if (kind == 'min_yield') { final limit = int.parse(words[1]); detail = '${percent(ytm)} limit ${hundredths(limit)}'; breach = ytm * 10000 < limit; }
      else if (kind == 'duration') { final low = int.parse(words[1]), high = int.parse(words[2]); detail = '${decimals(modified, 4)} range ${hundredths(low)} ${hundredths(high)}'; breach = modified < low / 100 || modified > high / 100; }
      else { final limit = int.parse(words[1]); detail = '${decimals(dv01, 2)} limit ${hundredths(limit)}'; breach = dv01 * 100 > limit; }
      lines.add('$name $kind $detail ${breach ? 'BREACH' : 'PASS'}'); if (breach) breaches++;
    }
    lines.add('$name breaches $breaches'); return lines;
  }
}

void main() {
  var valuationDate = 0, settlementDays = 0;
  final scenarioLines = <(int, String, List<int>)>[], limits = <List<String>>[];
  final params = readLines('params.txt');
  for (var index = 0; index < params.length; index++) {
    final words = params[index].split(' ');
    if (words[0] == 'valuation_date') valuationDate = parseDate(words[1]);
    else if (words[0] == 'settlement_days') settlementDays = int.parse(words[1]);
    else if (words[0] == 'scenario') scenarioLines.add((index + 1, words[1], words.skip(2).map(int.parse).toList()));
    else limits.add(words.sublist(1));
  }
  final calendar = Calendar(readLines('calendar.txt').map(parseDate)), fixings = rows('fixings.csv').map((row) => (parseDate(row.$2[0]), int.parse(row.$2[1]))).toList();
  final settlement = calendar.move(valuationDate, settlementDays), errors = <String>[], seen = <String>{}, pillars = <(int, int, int)>[];
  for (final (number, fields) in rows('curve_quotes.csv')) {
    final text = fields[0], frequency = int.parse(fields[2]);
    final reason = seen.contains(text) ? 'duplicate pillar' : !validDate(text) ? 'invalid date' : parseDate(text) <= settlement ? 'pillar not after settlement' : !frequencies.contains(frequency) ? 'invalid frequency' : null;
    if (reason == null) pillars.add((parseDate(text), int.parse(fields[1]), frequency)); else record(errors, 'curve_quotes.csv', number, text, reason);
    seen.add(text);
  }
  pillars.sort((a, b) => a.$1.compareTo(b.$1)); seen.clear(); final scenarios = <Scenario>[];
  for (final (number, name, shifts) in scenarioLines) {
    if (seen.contains(name)) record(errors, 'params.txt', number, name, 'duplicate scenario');
    else if (shifts.length != pillars.length) record(errors, 'params.txt', number, name, 'wrong number of shifts');
    else scenarios.add((name, shifts.map((shift) => shift * basisPoint).toList()));
    seen.add(name);
  }
  seen.clear(); final bonds = <String, Bond>{};
  for (final (number, fields) in rows('bonds.csv')) {
    try { bonds[fields[0]] = parseBond(fields, seen, calendar, fixings); } on InputError catch (error) { record(errors, 'bonds.csv', number, fields[0], error.message); }
    seen.add(fields[0]);
  }
  seen.clear(); final valuations = <String, Valuation>{};
  for (final (number, fields) in rows('prices.csv')) {
    final code = fields[0];
    try {
      final bond = bonds[code]; if (bond == null) throw InputError('unknown bond');
      if (seen.contains(code)) throw InputError('duplicate price');
      if (bond.issue > settlement || settlement >= bond.maturity) throw InputError('not outstanding');
      final value = Valuation(bond, thousandths(fields[1]), settlement);
      if (!value.pricer.inRange(value.target)) throw InputError('yield out of range');
      valuations[code] = value;
    } on InputError catch (error) { record(errors, 'prices.csv', number, code, error.message); }
    seen.add(code);
  }
  final holdings = <(String, String), (int, int)>{};
  for (final (number, fields) in rows('holdings.csv')) {
    final code = fields[1], face = int.parse(fields[2]);
    try {
      final bond = bonds[code]; if (bond == null) throw InputError('unknown bond');
      final value = valuations[code]; if (value == null) throw InputError('no price');
      if (face % bond.face != 0) throw InputError('invalid face');
      final units = face ~/ bond.face, book = rounded((face ~/ bond.face) * value.outstanding * thousandths(fields[3]), 100000), key = (fields[0], code), old = holdings[(fields[0], code)] ?? (0, 0);
      holdings[key] = (old.$1 + units, old.$2 + book);
    } on InputError catch (error) { record(errors, 'holdings.csv', number, code, error.message); }
  }
  final curve = bootstrap(settlement, pillars);
  for (final value in valuations.values) value.analyze(curve, settlement);
  final grouped = <String, List<Position>>{}, order = holdings.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  for (final key in order) grouped.putIfAbsent(key.$1, () => []).add(Position(valuations[key.$2]!, holdings[key]!.$1, holdings[key]!.$2));
  final report = <String>[], compliance = <String>[], scenarioRows = ['portfolio,scenario,bond,value,pnl'];
  for (final name in sortedKeys(grouped)) { final portfolio = Portfolio(name, grouped[name]!)..analyze(curve, scenarios, settlement); report.addAll(portfolio.report()); scenarioRows.addAll(portfolio.scenarioLines()); compliance.addAll(portfolio.compliance(limits, settlement)); }
  final cashflows = ['bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal'];
  for (final code in sortedKeys(bonds)) for (final period in bonds[code]!.periods) if (period.cash >= 1) cashflows.add([code, period.number, formatDate(period.start), formatDate(period.end), formatDate(period.payment), decimals(period.n / period.m, 6), period.rate, period.opening, period.coupon, period.principal].join(','));
  final analytics = ['bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread'];
  for (final code in sortedKeys(valuations)) { final v = valuations[code]!; analytics.add([code, decimals(v.clean / 1000, 6), decimals(v.accrued, 6), decimals(v.target, 6), percent(v.ytm), percent(v.ytw), formatDate(v.workout), formatDate(v.nextPayment), decimals(v.wal, 4), decimals(v.risk.macaulay, 4), decimals(v.risk.modified, 4), decimals(v.risk.convexity, 4), decimals(v.risk.dv01, 6), decimals(v.curveClean, 6), percent(v.spread)].join(',')); }
  final curveRows = ['valuation ${formatDate(valuationDate)} settlement ${formatDate(settlement)}']; var previous = 0;
  for (var index = 0; index < pillars.length; index++) { final (maturity, coupon, frequency) = pillars[index]; final days = curve.days[index]; curveRows.add('pillar ${formatDate(maturity)} days $days frequency $frequency par ${hundredths(coupon)} zero ${percent(curve.rates[index])} df ${decimals(curve.discount(days), 6)} forward ${percent(curve.forward(previous, days))}'); previous = days; }
  for (var year = 1; year <= curve.days.last ~/ 365; year++) { final days = 365 * year; curveRows.add('grid ${year}Y days $days zero ${percent(curve.zero(days))} df ${decimals(curve.discount(days), 6)} forward ${percent(curve.forward(days - 365, days))}'); }
  Directory('output').createSync(recursive: true);
  for (final entry in {'errors.txt': errors, 'cashflows.csv': cashflows, 'analytics.csv': analytics, 'curve.txt': curveRows, 'portfolio.txt': report, 'scenarios.csv': scenarioRows, 'compliance.txt': compliance}.entries) writeLines(entry.key, entry.value);
}
