part of 'main.dart';

int sum(Iterable<int> values) =>
    values.fold(0, (total, value) => total + value);
int sumSquares(Iterable<int> values) =>
    values.fold(0, (total, value) => total + value * value);
int? mean(List<int> values) =>
    values.isEmpty ? null : rdiv(100 * sum(values), values.length);

class RRStatistics {
  int count = 0;
  int? meanRR, meanHR;
  Beat? shortest, longest;
  RRStatistics(List<Beat> beats) {
    final values = <int>[];
    for (final b in beats) {
      if (b.rr == 0) continue;
      count++;
      values.add(b.rr);
      if (shortest == null || b.rr < shortest!.rr) shortest = b;
      if (longest == null || b.rr > longest!.rr) longest = b;
    }
    meanRR = mean(values);
    if (values.isNotEmpty) meanHR = rdiv(6000000 * values.length, sum(values));
  }
}

class NNStatistics {
  final intervals = <int>[], pairs = <(int, int)>[], histogram = <int, int>{};
  int e = 0, k = 0, nn50 = 0, histogramMax = 0;
  int? meanNN, sdnn, rmssd, sdsd, pnn50, sd1, sd2, triangular;
  NNStatistics(List<Beat> beats) {
    final nn = <int, int>{};
    for (var i = 2; i < beats.length; i++) {
      final previous = beats[i - 1], current = beats[i];
      if (previous.label == 'N' &&
          current.label == 'N' &&
          5 * (current.rr - previous.rr).abs() <= previous.rr) {
        nn[current.number] = current.rr;
        intervals.add(current.rr);
        final value = nn[current.number - 1];
        if (value != null) pairs.add((value, current.rr));
      }
    }
    e = intervals.length;
    k = pairs.length;
    meanNN = mean(intervals);
    if (e >= 2)
      sdnn = root(
        e * sumSquares(intervals) - sum(intervals) * sum(intervals),
        e * (e - 1),
      );
    final differences = pairs.map((p) => p.$2 - p.$1).toList(),
        sums = pairs.map((p) => p.$1 + p.$2).toList();
    nn50 = differences.where((d) => d.abs() > 50).length;
    if (k > 0) {
      rmssd = root(sumSquares(differences), k);
      pnn50 = rdiv(10000 * nn50, k);
    }
    if (k >= 2) {
      final dn =
              k * sumSquares(differences) - sum(differences) * sum(differences),
          sn = k * sumSquares(sums) - sum(sums) * sum(sums);
      sdsd = root(dn, k * (k - 1));
      sd1 = root(dn, 2 * k * (k - 1));
      sd2 = root(sn, 2 * k * (k - 1));
    }
    for (final u in intervals) {
      final bin = 16 * u ~/ 125;
      histogram[bin] = (histogram[bin] ?? 0) + 1;
    }
    for (final count in histogram.values) {
      histogramMax = math.max(histogramMax, count);
    }
    if (histogramMax > 0) triangular = rdiv(100 * e, histogramMax);
  }
}

List<(int, int)> consecutiveRanges(List<int> indices) {
  final ranges = <(int, int)>[];
  if (indices.isEmpty) return ranges;
  var start = indices.first, end = indices.first;
  for (final index in indices.skip(1)) {
    if (index == end + 1) {
      end = index;
    } else {
      ranges.add((start, end));
      start = index;
      end = index;
    }
  }
  ranges.add((start, end));
  return ranges;
}

List<List<int>> linkedSequences(
  List<int> indices,
  int interval,
  Map<int, String> labels,
) {
  final chains = <List<int>>[];
  var current = <int>[];
  for (final index in indices) {
    var linked = current.isNotEmpty && index == current.last + interval;
    if (linked) {
      for (var j = current.last + 1; j < index; j++) {
        if (labels[j] != 'N') {
          linked = false;
          break;
        }
      }
    }
    if (linked) {
      current.add(index);
    } else {
      if (current.isNotEmpty) chains.add(current);
      current = [index];
    }
  }
  if (current.isNotEmpty) chains.add(current);
  return chains;
}
