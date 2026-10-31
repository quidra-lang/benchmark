import 'dart:io';
import 'dart:math';
import 'dataset.dart';
import 'variable_charts.dart';
import 'attribute_charts.dart';
import 'run_rules.dart';
import 'capability.dart';
import 'plot.dart';

const chartNames = ['XBAR_R', 'R', 'XBAR_S', 'S', 'I', 'MR', 'CUSUM', 'EWMA', 'MA'];
const familyNames = ['XBAR_R', 'XBAR_S', 'I_MR'];
const labels = [['XBAR', 'R'], ['XBAR', 'S'], ['I', 'MR']];
const familyCharts = [[0, 1], [2, 3], [4, 5]];
const eventTypes = ['SHIFT_UP', 'SHIFT_DOWN', 'SPREAD_UP', 'SPREAD_DOWN', 'PATTERN'];

String real(double value) { final text = value.toStringAsFixed(4); return text == '-0.0000' ? '0.0000' : text; }
String numberList(List<int> numbers) => numbers.isEmpty ? 'none' : numbers.join(' ');
String status(bool converged) => converged ? 'converged' : 'stopped';
String limitsText(String label, Limits limits) => '$label lcl ${real(limits.lcl)} cl ${real(limits.cl)} ucl ${real(limits.ucl)}';
String pairText(int family, List<Limits> limits) => '${limitsText(labels[family][0], limits[0])} ${limitsText(labels[family][1], limits[1])}';

typedef Series = ({List<int> numbers, List<double> values});
typedef EstimationPass = ({int points, List<Limits> limits, List<int> outliers});
typedef Check = ({int points, List<Signal> signals});
typedef Proposal = ({int points, List<Limits> limits});
typedef AttributePass = ({int lots, double center, List<int> outliers});
typedef CapabilityGroup = ({String name, List<int> numbers, Capability result});
typedef RollingWindow = ({int first, int last, Capability result});

class Estimate {
  final List<EstimationPass> passes;
  final bool converged;
  final List<Limits> limits;
  final List<int> retained, removed;
  Estimate(this.passes, this.converged, this.limits, this.retained, this.removed);
}

class AttributeResult {
  final List<AttributePass> passes;
  final bool converged;
  final int retained;
  final List<int> removed;
  final List<LotPoint> points;
  final List<Signal> signals;
  AttributeResult(this.passes, this.converged, this.retained, this.removed, this.points, this.signals);
}

class Event {
  final int start;
  int end;
  List<Signal> signals = [];
  final counts = List.filled(5, 0), detection = List<int?>.filled(9, null);
  int kind = 0, onset = 0, out = 0;
  double shift = 0, spread = 0;
  Event(this.start, this.end);
  bool contains(int subgroup) => start <= subgroup && subgroup <= end;
}

List<Series> sequences(int family, List<int> numbers, List<Subgroup> groups, List<int> values) {
  if (family == 2) {
    final selected = numbers.map((i) => values[i - 1]).toList();
    return [(numbers: [...numbers], values: selected.map((v) => v.toDouble()).toList()), (numbers: numbers.sublist(1), values: movingRanges(selected).map((v) => v.toDouble()).toList())];
  }
  return [(numbers: [...numbers], values: numbers.map((i) => groups[i - 1].mean).toList()), (numbers: [...numbers], values: numbers.map((i) => family == 0 ? groups[i - 1].range.toDouble() : groups[i - 1].sd).toList())];
}

Estimate estimateFamily(int family, List<Subgroup> groups, List<int> values, Settings s) {
  final initial = List.generate(s.phase1 * (family == 2 ? s.size : 1), (i) => i + 1), passes = <EstimationPass>[];
  var retained = [...initial], converged = false, limits = <Limits>[];
  for (var pass = 1; pass <= s.passes; pass++) {
    limits = variableLimits(family, retained, groups, values, s.size);
    final series = sequences(family, retained, groups, values), out = <int>{};
    for (final (index, sequence) in series.indexed) {
      for (final (i, number) in sequence.numbers.indexed) { if (limits[index].outside(sequence.values[i])) out.add(number); }
    }
    final outliers = out.toList()..sort(); passes.add((points: retained.length, limits: limits, outliers: outliers));
    if (outliers.isEmpty) { converged = true; break; }
    if (pass == s.passes) break;
    retained = retained.where((i) => !out.contains(i)).toList();
  }
  return Estimate(passes, converged, limits, retained, initial.where((i) => !retained.contains(i)).toList());
}

List<AttributeResult> estimateAttributes(List<Lot> lots, Settings s) {
  final results = <AttributeResult>[];
  for (var chart = 0; chart < 4; chart++) {
    var retained = [...lots], converged = false, center = CenterLine(chart, lots);
    final passes = <AttributePass>[];
    for (var pass = 1; pass <= s.passes; pass++) {
      center = CenterLine(chart, retained);
      final out = [for (final lot in retained) if (LotPoint(chart, lot, center).status != 'ok') lot.number];
      passes.add((lots: retained.length, center: center.value, outliers: out));
      if (out.isEmpty) { converged = true; break; }
      if (pass == s.passes) break;
      retained = retained.where((lot) => !out.contains(lot.number)).toList();
    }
    final points = lots.map((lot) => LotPoint(chart, lot, center)).toList(), removed = [for (final lot in lots) if (!retained.any((other) => other.number == lot.number)) lot.number];
    final signals = checkRules(chart, lots.map((l) => l.number).toList(), points.map((p) => p.z).toList(), const Limits(-3, 0, 3), s.rules['STD']!);
    results.add(AttributeResult(passes, converged, retained.length, removed, points, signals));
  }
  return results;
}

class Analysis {
  final Settings settings;
  final List<int> values;
  final List<Lot> lots;
  late final List<Subgroup> groups;
  late final List<Estimate> estimates;
  final List<Check> checks = [];
  final List<Proposal> proposed = [];
  double mu = 0, sigma = 0, reference = 0, interval = 0, ewmaWidth = 0, maWidth = 0;
  late final List<List<double>> cusum, ewma, ma;
  final List<Signal> signals = [];
  final List<Event> events = [];
  late final List<AttributeResult> attributes;
  final List<CapabilityGroup> capabilities = [];
  final List<RollingWindow> rolling = [];
  Analysis(this.settings, this.values, this.lots) {
    final s = settings;
    groups = subgroupStatistics(values, s.size);
    estimates = [for (var family = 0; family < 3; family++) estimateFamily(family, groups, values, s)];
    for (var family = 0; family < 3; family++) {
      for (final (index, series) in sequences(family, estimates[family].retained, groups, values).indexed) {
        final chart = familyCharts[family][index]; checks.add((points: series.numbers.length, signals: checkRules(chart, series.numbers, series.values, estimates[family].limits[index], s.rules[chartNames[chart]]!)));
      }
    }
    cusum = List.generate(groups.length, (_) => [0.0, 0.0]); ewma = List.generate(groups.length, (_) => [0.0, 0.0]); ma = List.generate(groups.length, (_) => [0.0, 0.0]);
    monitor(); groupEvents();
    for (var family = 0; family < 3; family++) {
      final numbers = [...estimates[family].retained];
      for (var i = s.phase1 + 1; i <= groups.length; i++) {
        if (eventNumber(i) == null) {
          if (family == 2) { numbers.addAll(List.generate(s.size, (j) => (i - 1) * s.size + j + 1)); } else { numbers.add(i); }
        }
      }
      proposed.add((points: numbers.length, limits: variableLimits(family, numbers, groups, values, s.size)));
    }
    attributes = estimateAttributes(lots, s);
    for (final entry in {'phase1': estimates[0].retained, 'phase2': List.generate(groups.length - s.phase1, (j) => s.phase1 + j + 1)}.entries) {
      capabilities.add((name: entry.key, numbers: entry.value, result: Capability(entry.value.map((i) => groups[i - 1]).toList(), s)));
    }
    for (var first = s.phase1 + 1; first + s.window - 1 <= groups.length; first += s.step) {
      final last = first + s.window - 1; rolling.add((first: first, last: last, result: Capability(groups.sublist(first - 1, last), s)));
    }
  }

  int? eventNumber(int subgroup) {
    final index = events.indexWhere((event) => event.contains(subgroup)); return index < 0 ? null : index + 1;
  }
  bool hasSignal(int chart, int end, [int? rule]) => signals.any((s) => s.chart == chart && s.end == end && (rule == null || rule == s.rule));

  void monitor() {
    final s = settings;
    for (var family = 0; family < 3; family++) {
      final factor = family == 2 ? s.size : 1, last = family == 2 ? values.length : groups.length;
      final numbers = [for (var i = s.phase1 * factor + 1; i <= last; i++) i], series = sequences(family, numbers, groups, values);
      if (family == 2) series[1] = (numbers: numbers, values: numbers.map((i) => (values[i - 1] - values[i - 2]).abs().toDouble()).toList());
      for (final (index, sequence) in series.indexed) {
        final chart = familyCharts[family][index]; signals.addAll(checkRules(chart, sequence.numbers, sequence.values, estimates[family].limits[index], s.rules[chartNames[chart]]!));
      }
    }
    mu = estimates[0].limits[0].cl; sigma = estimates[0].limits[1].cl / controlConstants[s.size - 2][6] / sqrt(s.size);
    reference = s.cusumK * sigma; interval = s.cusumH * sigma;
    final rho = s.lambda / (2 - s.lambda), q = (1 - s.lambda) * (1 - s.lambda);
    ewmaWidth = s.ewmaL * sigma * sqrt(rho); maWidth = 3 * sigma / sqrt(s.span);
    var upper = 0.0, lower = 0.0, etaUpper = 0, etaLower = 0, z = mu, factor = 1.0;
    for (var i = s.phase1 + 1; i <= groups.length; i++) {
      final mean = groups[i - 1].mean;
      upper = max(0.0, upper + (mean - mu - reference)); lower = max(0.0, lower + (mu - mean - reference));
      etaUpper = upper > 0 ? etaUpper + 1 : 0; etaLower = lower > 0 ? etaLower + 1 : 0; cusum[i - 1] = [upper, lower];
      if (upper > interval) { signals.add(Signal(6, 9, i - etaUpper + 1, i, upper, 'UP')); upper = 0; etaUpper = 0; }
      if (lower > interval) { signals.add(Signal(6, 10, i - etaLower + 1, i, lower, 'DOWN')); lower = 0; etaLower = 0; }
      z = s.lambda * mean + (1 - s.lambda) * z; factor *= q;
      final width = s.ewmaL * sigma * sqrt(rho * (1 - factor)); ewma[i - 1] = [z, width];
      if (z > mu + width) { signals.add(Signal(7, 9, i, i, z, 'UP')); } else if (z < mu - width) { signals.add(Signal(7, 10, i, i, z, 'DOWN')); }
      final start = max(s.phase1 + 1, i - s.span + 1), count = i - start + 1;
      final average = integerSum(groups.sublist(start - 1, i).map((g) => g.total)) / (s.size * count), maWidth = 3 * sigma / sqrt(count);
      ma[i - 1] = [average, maWidth];
      if (average > mu + maWidth) { signals.add(Signal(8, 9, start, i, average, 'UP')); } else if (average < mu - maWidth) { signals.add(Signal(8, 10, start, i, average, 'DOWN')); }
    }
    signals.sort((a, b) {
      for (final comparison in [a.chart.compareTo(b.chart), a.end.compareTo(b.end), a.rule.compareTo(b.rule)]) { if (comparison != 0) return comparison; }
      return 0;
    });
  }

  void groupEvents() {
    final numbers = signals.map((s) => s.subgroup(settings.size)).toSet().toList()..sort();
    for (final number in numbers) {
      if (events.isEmpty || number - events.last.end - 1 > settings.gap) { events.add(Event(number, number)); } else { events.last.end = number; }
    }
    for (final event in events) {
      event.signals = signals.where((signal) => event.contains(signal.subgroup(settings.size))).toList();
      final onsets = <int>[];
      for (final signal in event.signals) {
        final index = signal.direction == 'NONE' ? 4 : ([1, 3, 5].contains(signal.chart) ? 2 : 0) + (signal.direction == 'DOWN' ? 1 : 0);
        event.counts[index]++;
        if (signal.chart == 6) onsets.add(signal.start);
        final g = signal.subgroup(settings.size), old = event.detection[signal.chart]; event.detection[signal.chart] = old == null ? g : min(g, old);
      }
      event.kind = event.counts.indexOf(event.counts.reduce(max)); event.onset = onsets.isEmpty ? event.start : onsets.reduce(min);
      final selected = groups.sublist(event.start - 1, event.end), mean = integerSum(selected.map((g) => g.total)) / (settings.size * selected.length);
      event.shift = (mean - mu) / sigma; event.spread = (realSum(selected.map((g) => g.sd)) / selected.length) / estimates[1].limits[1].cl;
      event.out = selected.expand((g) => g.values).where((value) => value < settings.lsl || value > settings.usl).length;
    }
  }

  List<String> limitsLines() {
    final s = settings;
    final lines = ['characteristic ${s.characteristic}', 'subgroup_size ${s.size}', 'subgroups ${groups.length}', 'samples ${values.length}', 'phase1_subgroups ${s.phase1}'];
    for (final (family, estimate) in estimates.indexed) {
      lines.add('family ${familyNames[family]}');
      for (final (index, pass) in estimate.passes.indexed) { lines.add('pass ${index + 1} points ${pass.points} ${pairText(family, pass.limits)} out ${numberList(pass.outliers)}'); }
      lines.add('result ${status(estimate.converged)} passes ${estimate.passes.length} retained ${estimate.retained.length} removed ${numberList(estimate.removed)}');
    }
    for (final (chart, check) in checks.indexed) {
      for (final signal in check.signals) { lines.add('phase1_signal ${chartNames[chart]} ${ruleText(signal.rule)} ${signal.start} ${signal.end} ${real(signal.value)}'); }
      lines.add('phase1_check ${chartNames[chart]} points ${check.points} signals ${check.signals.length}');
    }
    for (final (family, proposal) in proposed.indexed) { lines.add('proposed ${familyNames[family]} points ${proposal.points} ${pairText(family, proposal.limits)}'); }
    lines.add('cusum target ${real(mu)} sigma ${real(sigma)} k ${real(reference)} h ${real(interval)}');
    lines.add('ewma target ${real(mu)} sigma ${real(sigma)} lcl ${real(mu - ewmaWidth)} ucl ${real(mu + ewmaWidth)}');
    lines.add('ma target ${real(mu)} sigma ${real(sigma)} span ${s.span} lcl ${real(mu - maWidth)} ucl ${real(mu + maWidth)}');
    for (final (chart, name) in chartNames.indexed) {
      final selected = signals.where((signal) => signal.chart == chart).toList(), ends = selected.map((signal) => signal.end).toSet();
      final first = ends.isEmpty ? 'none' : '${ends.reduce(min)}', rules = chart < 6 ? s.rules[name]! : [9, 10];
      final counts = rules.map((rule) => '${ruleText(rule)}:${selected.where((signal) => signal.rule == rule).length}').join(' ');
      final points = (groups.length - s.phase1) * (chart == 4 || chart == 5 ? s.size : 1);
      lines.add('phase2 $name points $points signals ${selected.length} signalled ${ends.length} first $first by_rule $counts');
    }
    return lines;
  }

  List<String> signalLines() => ['chart,rule,start,end,value,direction', for (final s in signals) '${chartNames[s.chart]},${ruleText(s.rule)},${s.start},${s.end},${real(s.value)},${s.direction}'];

  List<String> eventLines() {
    final lines = ['events ${events.length}'];
    for (final (index, event) in events.indexed) {
      final number = index + 1, charts = [for (final (chart, name) in chartNames.indexed) if (event.detection[chart] != null) name].join(',');
      final counts = [for (final (i, name) in ['location_up', 'location_down', 'spread_up', 'spread_down', 'pattern'].indexed) '$name ${event.counts[i]}'].join(' ');
      lines.add('event $number start ${event.start} end ${event.end} length ${event.end - event.start + 1} signals ${event.signals.length} charts $charts $counts onset ${event.onset} shift ${real(event.shift)} spread ${real(event.spread)} out_of_spec ${event.out} type ${eventTypes[event.kind]}');
      final detection = [for (final (chart, name) in chartNames.indexed) '$name:${event.detection[chart] ?? '-'}'].join(' ');
      lines.add('detection $number $detection');
    }
    return lines;
  }

  List<String> subgroupLines() {
    final lines = ['subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event'], zones = Zones(estimates[0].limits[0]);
    for (final (index, group) in groups.indexed) {
      final i = index + 1, phase = i > settings.phase1 ? 'phase2' : estimates[0].removed.contains(i) ? 'excluded' : 'phase1';
      final trace = i > settings.phase1 ? [cusum[index][0], cusum[index][1], ewma[index][0], ma[index][0]].map(real).toList() : ['-', '-', '-', '-'];
      final count = signals.where((signal) => signal.subgroup(settings.size) == i).length;
      lines.add('$i,$phase,${real(group.mean)},${zones.name(group.mean)},${group.range},${real(group.sd)},${trace.join(',')},$count,${eventNumber(i) ?? '-'}');
    }
    return lines;
  }

  List<String> attributeLines() {
    final lines = <String>[];
    for (final (chart, result) in attributes.indexed) {
      lines.add('chart ${attributeCharts[chart]}');
      for (final (index, pass) in result.passes.indexed) { lines.add('pass ${index + 1} lots ${pass.lots} center ${real(pass.center)} out ${numberList(pass.outliers)}'); }
      lines.add('result ${status(result.converged)} passes ${result.passes.length} retained ${result.retained} removed ${numberList(result.removed)}');
      for (final (index, point) in result.points.indexed) {
        final lot = lots[index], value = chart == 1 || chart == 2 ? '${point.value.toInt()}' : real(point.value);
        lines.add('lot ${lot.number} size ${lot.inspected} value $value lcl ${real(point.lcl)} ucl ${real(point.ucl)} z ${real(point.z)} status ${point.status}');
      }
      for (final signal in result.signals) { lines.add('signal ${ruleText(signal.rule)} ${signal.start} ${signal.end} ${real(signal.value)}'); }
      lines.add('signals ${result.signals.length}');
    }
    return lines;
  }

  List<String> capabilityLines() {
    final lines = <String>[];
    for (final group in capabilities) {
      final result = group.result;
      lines.add('group ${group.name} subgroups ${group.numbers.length} values ${result.count}');
      for (final entry in result.metrics.entries) { lines.add('${entry.key} ${real(entry.value)}'); }
      for (final (i, label) in ['cpk_ci', 'ppk_ci'].indexed) { lines.add('$label ${real(result.intervals[i][0])} ${real(result.intervals[i][1])}'); }
      lines.add('below_lsl ${result.below}'); lines.add('above_usl ${result.above}'); lines.add('ppm ${real(result.ppm)}');
      for (final i in group.numbers) {
        for (final (index, value) in groups[i - 1].values.indexed) {
          if (value < settings.lsl || value > settings.usl) lines.add('out_of_spec sample ${(i - 1) * settings.size + index + 1} subgroup $i value $value side ${value < settings.lsl ? 'low' : 'high'}');
        }
      }
      lines.add('verdict ${result.verdict}');
      for (final bin in result.bins) {
        lines.add('bin ${bin.lower} ${bin.upper} ${bin.frequency}${bin.length > 0 ? ' ${'#' * bin.length}' : ''}${bin.marks.isNotEmpty ? ' ${bin.marks.join(' ')}' : ''}');
      }
    }
    for (final window in rolling) {
      final parts = [for (final label in ['mean', 'sigma_within', 'sigma_overall', 'cpk', 'ppk']) '$label ${real(window.result.metrics[label]!)}'].join(' ');
      lines.add('rolling ${window.first} ${window.last} $parts verdict ${window.result.verdict}');
    }
    return lines;
  }

  List<String> chartLines() {
    final lines = <String>[];
    for (final (picture, family, limitIndex, chart) in [('XBAR', 0, 0, 0), ('R', 0, 1, 1), ('S', 1, 1, 3)]) {
      final limits = estimates[family].limits[limitIndex]; lines.add(limitsText('chart $picture', limits));
      for (final (index, group) in groups.indexed) {
        final i = index + 1, mark = i > settings.phase1 ? '2' : estimates[family].removed.contains(i) ? 'x' : '1';
        final value = chart == 0 ? group.mean : chart == 1 ? group.range.toDouble() : group.sd;
        lines.add('${'$i'.padLeft(3)} $mark ${limitsBand(limits, value, mark == '2' && hasSignal(chart, i))} ${real(value)}');
      }
    }
    lines.add('chart CUSUM h ${real(interval)}');
    for (var i = settings.phase1 + 1; i <= groups.length; i++) {
      final [upper, lower] = cusum[i - 1];
      lines.add('${'$i'.padLeft(3)} ${cusumBand(upper, lower, interval, hasSignal(6, i, 9), hasSignal(6, i, 10))} ${real(upper)} ${real(lower)}');
    }
    for (final (chart, points, scale) in [(7, ewma, ewmaWidth), (8, ma, maWidth)]) {
      lines.add(limitsText('chart ${chartNames[chart]}', Limits(mu - scale, mu, mu + scale)));
      for (var i = settings.phase1 + 1; i <= groups.length; i++) {
        final [value, width] = points[i - 1];
        lines.add('${'$i'.padLeft(3)} ${widthBand(scale, width, value, mu, hasSignal(chart, i))} ${real(value)} ${real(mu - width)} ${real(mu + width)}');
      }
    }
    for (final (chart, result) in attributes.indexed) {
      lines.add('chart ${attributeCharts[chart].toUpperCase()}_STD lcl -3.0000 cl 0.0000 ucl 3.0000');
      for (final (index, point) in result.points.indexed) { lines.add('${lots[index].number.toString().padLeft(3)} ${standardBand(point.z, point.status == 'ok')} ${real(point.z)}'); }
    }
    return lines;
  }
}

void main() {
  final a = Analysis(Settings.read(), readMeasurements(), readAttributes());
  Directory('output').createSync(recursive: true);
  for (final entry in {'limits.txt': a.limitsLines(), 'signals.csv': a.signalLines(), 'events.txt': a.eventLines(), 'subgroups.csv': a.subgroupLines(), 'attribute_charts.txt': a.attributeLines(), 'capability.txt': a.capabilityLines(), 'charts.txt': a.chartLines()}.entries) {
    File('output/${entry.key}').writeAsStringSync(entry.value.isEmpty ? '' : '${entry.value.join('\n')}\n');
  }
}
