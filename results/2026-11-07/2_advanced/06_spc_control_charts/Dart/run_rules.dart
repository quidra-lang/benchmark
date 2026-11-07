import 'variable_charts.dart';

class Zones {
  final Limits limits;
  final double u1, u2, l1, l2;
  Zones(this.limits) : u1 = limits.cl + (limits.ucl - limits.cl) / 3, u2 = limits.cl + 2 * ((limits.ucl - limits.cl) / 3), l1 = limits.cl - (limits.cl - limits.lcl) / 3, l2 = limits.cl - 2 * ((limits.cl - limits.lcl) / 3);
  String name(double value) => value > limits.ucl ? 'OUT+' : value < limits.lcl ? 'OUT-' : value > u2 ? 'A+' : value > u1 ? 'B+' : value > limits.cl ? 'C+' : value < l2 ? 'A-' : value < l1 ? 'B-' : value < limits.cl ? 'C-' : 'C0';
}

class Signal {
  final int chart, rule, start, end;
  final double value;
  final String direction;
  Signal(this.chart, this.rule, this.start, this.end, this.value, this.direction);
  int subgroup(int size) => chart == 4 || chart == 5 ? (end - 1) ~/ size + 1 : end;
}

String ruleText(int rule) => rule == 9 ? 'UPPER' : rule == 10 ? 'LOWER' : '$rule';

String? ruleDirection(int rule, List<double> window, Zones z) {
  final last = window.last;
  if (rule == 1) return z.limits.outside(last) ? last > z.limits.cl ? 'UP' : 'DOWN' : null;
  if (rule == 2 || rule == 3) {
    final upper = rule == 2 ? z.u2 : z.u1, lower = rule == 2 ? z.l2 : z.l1, needed = rule == 2 ? 2 : 4;
    if (last > upper && window.where((v) => v > upper).length >= needed) return 'UP';
    if (last < lower && window.where((v) => v < lower).length >= needed) return 'DOWN';
  } else if (rule == 4) {
    if (window.every((v) => v > z.limits.cl)) return 'UP';
    if (window.every((v) => v < z.limits.cl)) return 'DOWN';
  } else if (rule == 5 || rule == 6) {
    final differences = [for (var i = 1; i < window.length; i++) window[i] - window[i - 1]];
    if (rule == 5) {
      if (differences.every((v) => v > 0)) return 'UP';
      if (differences.every((v) => v < 0)) return 'DOWN';
    } else {
      if (differences.any((v) => v == 0)) return null;
      for (var i = 1; i < differences.length; i++) { if ((differences[i] > 0) == (differences[i - 1] > 0)) return null; }
      return 'NONE';
    }
  } else if (rule == 7) {
    if (window.every((v) => z.l1 < v && v < z.u1)) return 'NONE';
  } else if (rule == 8 && window.every((v) => v > z.u1 || v < z.l1) && window.any((v) => v > z.u1) && window.any((v) => v < z.l1)) {
    return 'NONE';
  }
  return null;
}

List<Signal> checkRules(int chart, List<int> numbers, List<double> values, Limits limits, List<int> rules) {
  const lengths = [1, 3, 5, 8, 6, 14, 15, 8];
  final zones = Zones(limits), signals = <Signal>[];
  for (var k = 1; k <= values.length; k++) {
    for (final rule in rules) {
      final length = lengths[rule - 1]; if (k < length) continue;
      final direction = ruleDirection(rule, values.sublist(k - length, k), zones);
      if (direction != null) signals.add(Signal(chart, rule, numbers[k - length], numbers[k - 1], values[k - 1], direction));
    }
  }
  return signals;
}
