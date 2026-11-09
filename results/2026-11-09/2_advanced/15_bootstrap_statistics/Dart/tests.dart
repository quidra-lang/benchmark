import 'resampling.dart';

Iterable<List<int>> positionChoices(int total, int size) sync* {
  final choice = List.generate(size, (index) => index);
  while (true) {
    yield choice.toList();
    var index = size - 1;
    while (index >= 0 && choice[index] == total - size + index) {
      index--;
    }
    if (index < 0) return;
    choice[index]++;
    for (var next = index + 1; next < size; next++) {
      choice[next] = choice[next - 1] + 1;
    }
  }
}

(int, int) reducedFraction(int numerator, int denominator) {
  final divisor = numerator.gcd(denominator);
  return (numerator ~/ divisor, denominator ~/ divisor);
}

int contrast(int firstTotal, int firstSize, int secondTotal, int secondSize) => secondSize * firstTotal - firstSize * secondTotal;

List<(int, int)> valueCounts(List<int> values) {
  final counts = <int, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  return [for (final value in keys) (value, counts[value]!)];
}

List<int> doubledRanks(List<int> values) {
  final ranks = <int, int>{};
  var smaller = 0;
  for (final (value, count) in valueCounts(values)) {
    ranks[value] = 2 * smaller + count + 1;
    smaller += count;
  }
  return [for (final value in values) ranks[value]!];
}

List<List<T>> splitList<T>(List<T> items, List<int> sizes) {
  final groups = <List<T>>[];
  var start = 0;
  for (final size in sizes) {
    groups.add(items.sublist(start, start + size));
    start += size;
  }
  return groups;
}

(double, double) sumsOfSquares(List<List<int>> samples) {
  final count = sumIntegers(samples.map((sample) => sample.length));
  final grandMean = sumIntegers(samples.map(sumIntegers)) / (100 * count);
  var between = 0.0, within = 0.0;
  for (final sample in samples) {
    final center = mean(sample), difference = center - grandMean;
    between += sample.length * (difference * difference);
    var squares = 0.0;
    for (final value in sample) {
      final e = value / 100 - center;
      squares += e * e;
    }
    within += squares;
  }
  return (between, within);
}

double fStatistic(double between, double within, int groups, int total) => between / (groups - 1) / (within / (total - groups));

double hStatistic(List<int> rankSums, List<int> sizes, double correction) {
  var count = 0, total = 0.0;
  for (var index = 0; index < rankSums.length; index++) {
    final rank = rankSums[index];
    total += (rank * rank) / (4 * sizes[index]);
    count += sizes[index];
  }
  return (12 * total / (count * (count + 1)) - 3 * (count + 1)) / correction;
}
