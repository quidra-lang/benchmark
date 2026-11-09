import 'dart:math';
import 'dataset.dart';
import 'variable_charts.dart';

class HistogramBin {
  final int lower, upper, frequency, length;
  final List<String> marks;
  HistogramBin(this.lower, this.upper, this.frequency, this.length, this.marks);
}

List<double> indices(double mean, double sigma, Settings s) {
  final potential = (s.usl - s.lsl) / (6 * sigma), upper = (s.usl - mean) / (3 * sigma), lower = (mean - s.lsl) / (3 * sigma);
  return [potential, upper, lower, min(upper, lower)];
}

List<double> confidenceInterval(double index, int count, double z) {
  final delta = z * sqrt(1 / (9 * count) + index * index / (2 * (count - 1)));
  return [index - delta, index + delta];
}

class Capability {
  final int count, below, above;
  final Map<String, double> metrics;
  final List<List<double>> intervals;
  final double ppm;
  final String verdict;
  final List<HistogramBin> bins;
  Capability._(this.count, this.below, this.above, this.metrics, this.intervals, this.ppm, this.verdict, this.bins);
  factory Capability(List<Subgroup> groups, Settings s) {
    final values = groups.expand((g) => g.values).toList(), count = values.length;
    final mean = integerSum(values) / count, rbar = integerSum(groups.map((g) => g.range)) / groups.length, sbar = realSum(groups.map((g) => g.sd)) / groups.length, constants = controlConstants[s.size - 2];
    final within = rbar / constants[6], sigmaSbar = sbar / constants[7];
    final squares = realSum(values.map((value) => (value - mean) * (value - mean))), overall = sqrt(squares / (count - 1));
    final [cp, cpu, cpl, cpk] = indices(mean, within, s);
    final [pp, ppu, ppl, ppk] = indices(mean, overall, s);
    final offset = mean - s.target, cpm = (s.usl - s.lsl) / (6 * sqrt(overall * overall + offset * offset));
    final below = values.where((v) => v < s.lsl).length, above = values.where((v) => v > s.usl).length;
    final metrics = {'mean': mean, 'sigma_within': within, 'sigma_sbar': sigmaSbar, 'sigma_overall': overall, 'cp': cp, 'cpu': cpu, 'cpl': cpl, 'cpk': cpk, 'pp': pp, 'ppu': ppu, 'ppl': ppl, 'ppk': ppk, 'cpm': cpm};
    return Capability._(count, below, above, metrics, [confidenceInterval(cpk, count, s.ciZ), confidenceInterval(ppk, count, s.ciZ)], 1000000 * (below + above) / count, cpk >= 1.33 ? 'capable' : cpk >= 1 ? 'marginal' : 'incapable', histogram(values, s));
  }
}

List<HistogramBin> histogram(List<int> values, Settings s) {
  final width = s.bin, low = min(values.reduce(min), s.lsl) ~/ width * width, high = max(values.reduce(max), s.usl) ~/ width * width + width;
  final frequencies = List.filled((high - low) ~/ width, 0);
  for (final value in values) { frequencies[(value - low) ~/ width]++; }
  final top = frequencies.reduce(max), bins = <HistogramBin>[];
  for (final (index, frequency) in frequencies.indexed) {
    final lower = low + index * width, upper = lower + width - 1;
    final marks = [for (final entry in {'lsl': s.lsl, 'target': s.target, 'usl': s.usl}.entries) if (lower <= entry.value && entry.value <= upper) entry.key];
    bins.add(HistogramBin(lower, upper, frequency, (50 * frequency + top - 1) ~/ top, marks));
  }
  return bins;
}
