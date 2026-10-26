import 'dart:io';
import 'dart:math' as math;
import 'dataset.dart';
import 'minstd.dart';
import 'resampling.dart';
import 'tests.dart';
import 'report.dart';

const groupNames = ['mean', 'median', 'trimmed_mean', 'sd'];
final groupFunctions = <double Function(List<int>)>[mean, median, trimmedMean, sd];
const pairNames = ['mean_diff', 'median_ratio', 'hodges_lehmann', 'cohen_d'];
final pairFunctions = <double Function(List<int>, List<int>)>[meanDifference, medianRatio, hodgesLehmann, cohenD];
const testNames = ['mean', 'median', 'ranksum', 'absdev'];

int ceilDiv(int numerator, int denominator) => (numerator + denominator - 1) ~/ denominator;

class Summary {
  final double estimate;
  final List<double> values, ordered;
  final double average, se, bias, low, high, basicLow, basicHigh;
  Summary._(this.estimate, this.values, this.ordered, this.average, this.se,
      this.bias, this.low, this.high, this.basicLow, this.basicHigh);
  factory Summary(double estimate, List<double> values, (int, int) ranks) {
    final (average, se) = meanAndSE(values);
    final ordered = orderedReals(values);
    final low = ordered[ranks.$1 - 1], high = ordered[ranks.$2 - 1];
    return Summary._(estimate, values, ordered, average, se, average - estimate,
        low, high, 2 * estimate - high, 2 * estimate - low);
  }
  String csvLine(String name, String statistic) => [name, statistic,
    ...[estimate, se, bias, low, high, basicLow, basicHigh].map(realText)].join(',');
  String intervalText() => 'se ${realText(se)} bias ${realText(bias)} percentile ${realText(low)} ${realText(high)} basic ${realText(basicLow)} ${realText(basicHigh)}';
}

class GroupBootstrap {
  final Group group;
  final List<List<int>> indices, samples;
  final List<Summary> summaries;
  GroupBootstrap._(this.group, this.indices, this.samples, this.summaries);
  factory GroupBootstrap(Group group, List<List<int>> indices, (int, int) ranks) {
    final samples = [for (final replicate in indices) [for (final index in replicate) group.values[index]]];
    final summaries = [for (final function in groupFunctions)
      Summary(function(group.values), [for (final sample in samples) function(sample)], ranks)];
    return GroupBootstrap._(group, indices, samples, summaries);
  }
}

class PairBootstrap {
  final GroupBootstrap first, second;
  final String name;
  final List<Summary> summaries;
  PairBootstrap._(this.first, this.second, this.name, this.summaries);
  factory PairBootstrap(GroupBootstrap first, GroupBootstrap second, (int, int) ranks) {
    final summaries = [for (final function in pairFunctions)
      Summary(function(first.group.values, second.group.values),
          [for (var index = 0; index < first.samples.length; index++)
            function(first.samples[index], second.samples[index])], ranks)];
    return PairBootstrap._(first, second, '${first.group.name}-${second.group.name}', summaries);
  }
}

(double, double) jackknifeSpread(List<double> values) {
  final count = values.length, average = sequentialSum(values) / values.length;
  var squares = 0.0;
  for (final value in values) {
    final difference = value - average;
    squares += difference * difference;
  }
  return (average, (count - 1) * squares / count);
}

class Jackknife {
  final List<double> values;
  final double average, variance, bias, se;
  Jackknife._(this.values, this.average, this.variance, this.bias, this.se);
  factory Jackknife(double estimate, List<double> values) {
    final (average, variance) = jackknifeSpread(values);
    return Jackknife._(values, average, variance,
        (values.length - 1) * (average - estimate), math.sqrt(variance));
  }
}

class Tally {
  final int observed;
  var extreme = 0, greater = 0;
  Tally(this.observed);
  void count(int value) {
    if (value.abs() >= observed.abs()) extreme++;
    if (value >= observed) greater++;
  }
  String text(int offset, int denominator) => 'extreme $extreme greater $greater p_two ${pValue(extreme + offset, denominator)} p_greater ${pValue(greater + offset, denominator)}';
}

class DisplayRange {
  final int low, delta;
  DisplayRange._(this.low, this.delta);
  factory DisplayRange(List<int> values) {
    final ordered = orderedIntegers(values);
    return DisplayRange._(ordered.first, 100 * (ordered.last - ordered.first));
  }
  int position(int value) => (120 * (value - 100 * low) + delta) ~/ (2 * delta);
}

List<int> outlierIndices(List<int> values) {
  final first = quantileNumerator(values, 25), third = quantileNumerator(values, 75);
  return [for (var index = 0; index < values.length; index++)
    if (200 * values[index] < 5 * first - 3 * third || 200 * values[index] > 5 * third - 3 * first) index];
}

List<String> seriesLines(String kind, String name, List<int> values, DisplayRange display, bool stems) {
  final count = values.length, average = mean(values), deviation = sd(values);
  final (second, third, fourth) = centralMoments(values);
  final clipped = winsorized(values);
  final firstQuartile = quantileNumerator(values, 25), thirdQuartile = quantileNumerator(values, 75);
  final outliers = outlierIndices(values);
  final outside = outliers.toSet();
  final inside = orderedIntegers([for (var index = 0; index < count; index++) if (!outside.contains(index)) values[index]]);
  final lowWhisker = inside.first, highWhisker = inside.last;
  final band = List.filled(61, '.');
  for (var position = display.position(100 * lowWhisker); position <= display.position(100 * highWhisker); position++) {
    band[position] = '-';
  }
  for (var position = display.position(firstQuartile); position <= display.position(thirdQuartile); position++) {
    band[position] = '=';
  }
  band[display.position(quantileNumerator(values, 50))] = '|';
  for (final index in outliers) {
    band[display.position(100 * values[index])] = 'o';
  }
  final ordered = orderedIntegers(values);
  final lines = ['$kind $name', 'n $count', 'mean ${realText(average)}',
    'median ${realText(median(values))}', 'trimmed_mean ${realText(trimmedMean(values))} trim ${count ~/ 10}',
    'winsorized_mean ${realText(mean(clipped))} winsorized_sd ${realText(sd(clipped))}',
    'sd ${realText(deviation)}', 'se_mean ${realText(deviation / math.sqrt(count))}',
    'cv ${realText(deviation / average)}', 'skewness ${realText(third / (second * math.sqrt(second)))}',
    'kurtosis ${realText(fourth / (second * second) - 3)}', 'mad ${realText(mad(values))}',
    'min ${realText(ordered.first / 100)}', 'q1 ${realText(firstQuartile / 10000)}',
    'q3 ${realText(thirdQuartile / 10000)}', 'iqr ${realText((thirdQuartile - firstQuartile) / 10000)}',
    'max ${realText(ordered.last / 100)}'];
  final percentiles = <String>['percentiles'];
  const percentages = [5, 10, 90, 95], labels = ['p05', 'p10', 'p90', 'p95'];
  for (var index = 0; index < percentages.length; index++) {
    percentiles.addAll([labels[index], realText(quantileNumerator(values, percentages[index]) / 10000)]);
  }
  lines.addAll([percentiles.join(' '), 'whiskers ${realText(lowWhisker / 100)} ${realText(highWhisker / 100)}',
    'outliers ${numberList([for (final index in outliers) index + 1])}', 'box ${band.join()}']);
  if (stems) {
    for (var stem = ordered.first ~/ 100; stem <= ordered.last ~/ 100; stem++) {
      final leaves = [for (final value in ordered) if (value ~/ 100 == stem) value % 100 ~/ 10].join();
      lines.add('stem $stem${leaves.isEmpty ? '' : ' $leaves'}');
    }
  }
  return lines;
}

List<String> bootstrapLines(List<GroupBootstrap> ordinary, List<GroupBootstrap> balanced, List<PairBootstrap> pairs) {
  final lines = ['group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi'];
  for (var index = 0; index < ordinary.length; index++) {
    final bootstrap = ordinary[index];
    for (var column = 0; column < 4; column++) {
      lines.add(bootstrap.summaries[column].csvLine(bootstrap.group.name, groupNames[column]));
    }
    for (var column = 0; column < 4; column++) {
      lines.add(balanced[index].summaries[column].csvLine(bootstrap.group.name, 'balanced_${groupNames[column]}'));
    }
  }
  for (final pair in pairs) {
    for (var column = 0; column < 4; column++) {
      lines.add(pair.summaries[column].csvLine(pair.name, pairNames[column]));
    }
  }
  return lines;
}

List<String> pairJackknifeLines(PairBootstrap pair) {
  final x = pair.first.group.values, y = pair.second.group.values, lines = <String>[];
  for (var statistic = 0; statistic < 4; statistic++) {
    final function = pairFunctions[statistic], estimate = pair.summaries[statistic].estimate;
    final first = Jackknife(estimate, [for (var index = 0; index < x.length; index++) function(without(x, index), y)]);
    final second = Jackknife(estimate, [for (var index = 0; index < y.length; index++) function(x, without(y, index))]);
    var bias = 0.0, variance = 0.0;
    bias += first.bias;
    bias += second.bias;
    variance += first.variance;
    variance += second.variance;
    lines.add('pair ${pair.name} ${pairNames[statistic]} estimate ${realText(estimate)} bias ${realText(bias)} se ${realText(math.sqrt(variance))}');
  }
  return lines;
}

int deviationTotal(List<int> sample, int center) => sumIntegers([for (final value in sample) (2 * value - center).abs()]);
List<int> splitStatistics(List<int> values, List<int> ranks, List<int> order, int size) {
  final first = <int>[], second = <int>[];
  var rankTotal = 0;
  for (var position = 0; position < order.length; position++) {
    final index = order[position];
    if (position < size) {
      first.add(values[index]);
      rankTotal += ranks[index];
    } else {
      second.add(values[index]);
    }
  }
  final firstCenter = doubledMedian(first), secondCenter = doubledMedian(second);
  return [contrast(sumIntegers(first), first.length, sumIntegers(second), second.length),
    firstCenter - secondCenter, rankTotal - first.length * (first.length + second.length + 1),
    contrast(deviationTotal(first, firstCenter), first.length, deviationTotal(second, secondCenter), second.length)];
}

List<int> signedRanks(List<int> differences) {
  final ranks = doubledRanks([for (final value in differences) if (value != 0) value.abs()]);
  final result = List.filled(differences.length, 0);
  var cursor = 0;
  for (var index = 0; index < differences.length; index++) {
    final value = differences[index];
    if (value != 0) result[index] = value < 0 ? -ranks[cursor++] : ranks[cursor++];
  }
  return result;
}

String welchLine(List<List<int>> samples) {
  final count = samples.length, means = <double>[], weights = <double>[];
  for (final sample in samples) {
    means.add(mean(sample));
    final deviation = sd(sample);
    weights.add(sample.length / (deviation * deviation));
  }
  final totalWeight = sequentialSum(weights);
  var weighted = 0.0;
  for (var index = 0; index < count; index++) {
    weighted += weights[index] * means[index];
  }
  final center = weighted / totalWeight;
  var spread = 0.0, lambda = 0.0;
  for (var index = 0; index < count; index++) {
    final difference = means[index] - center, share = 1 - weights[index] / totalWeight;
    spread += weights[index] * (difference * difference);
    lambda += share * share / (samples[index].length - 1);
  }
  spread /= count - 1;
  final f = spread / (1 + 2 * (count - 2) * lambda / (count * count - 1));
  final degrees = (count * count - 1) / (3 * lambda);
  return 'welch f ${realText(f)} df ${count - 1} ${realText(degrees)}';
}

typedef Delta = (int, int);
List<Delta> groupDeltas(List<List<int>> samples, List<(int, int)> pairs) => [for (final (first, second) in pairs)
  (contrast(sumIntegers(samples[first]), samples[first].length,
      sumIntegers(samples[second]), samples[second].length).abs(), samples[first].length * samples[second].length)];
bool deltaAtLeast(Delta value, Delta bound) => value.$1 * bound.$2 >= bound.$1 * value.$2;
Delta largestDelta(List<Delta> values) {
  var largest = values.first;
  for (final value in values.skip(1)) {
    if (!deltaAtLeast(largest, value)) largest = value;
  }
  return largest;
}

class Study {
  final Dataset data;
  final Minstd generator;
  final (int, int) ranks;
  final double zLow;
  Study._(this.data, this.generator, this.ranks, this.zLow);
  factory Study(Dataset data) {
    final low = (data.settings.bootstrap + 1) * (100 - data.settings.confidence) ~/ 200;
    return Study._(data, Minstd(data.settings.seed), (low, data.settings.bootstrap + 1 - low),
        phiInverse((100 - data.settings.confidence) / 200));
  }

  List<String> descriptiveLines() {
    final all = <int>[for (final group in data.groups) ...group.values];
    final lines = ['groups ${data.groups.length} observations ${all.length}'];
    final display = DisplayRange(all);
    for (final group in data.groups) {
      lines.addAll(seriesLines('group', group.name, group.values, display, true));
    }
    final paired = data.paired, together = DisplayRange([...data.paired.before, ...data.paired.after]);
    lines.add('paired subjects ${paired.differences.length}');
    lines.addAll(seriesLines('series', 'before', paired.before, together, false));
    lines.addAll(seriesLines('series', 'after', paired.after, together, false));
    lines.addAll(seriesLines('series', 'diff', paired.differences, DisplayRange(paired.differences), false));
    return lines;
  }

  (Summary, Summary) pairedBootstrap() {
    final paired = data.paired, means = <double>[], correlations = <double>[];
    for (final indices in ordinaryIndices(generator, paired.differences.length, data.settings.bootstrap)) {
      final before = <int>[], after = <int>[], differences = <int>[];
      for (final index in indices) {
        before.add(paired.before[index]);
        after.add(paired.after[index]);
        differences.add(paired.differences[index]);
      }
      means.add(mean(differences));
      correlations.add(correlation(before, after));
    }
    return (Summary(mean(paired.differences), means, ranks),
        Summary(correlation(paired.before, paired.after), correlations, ranks));
  }

  List<String> histogramLines(String name, String statistic, Summary summary) {
    final bins = data.settings.bins, values = summary.values;
    final low = summary.ordered.first, high = summary.ordered.last;
    final counts = List.filled(bins, 0), marks = List.generate(bins, (_) => <String>[]);
    var top = 0;
    for (final value in values) {
      final index = binNumber(value, low, high, bins) - 1;
      counts[index]++;
      top = math.max(top, counts[index]);
    }
    marks[binNumber(summary.low, low, high, bins) - 1].add('L');
    var estimateBin = 'none';
    if (low <= summary.estimate && summary.estimate <= high) {
      final index = binNumber(summary.estimate, low, high, bins) - 1;
      estimateBin = '${index + 1}';
      marks[index].add('E');
    }
    marks[binNumber(summary.high, low, high, bins) - 1].add('H');
    final convergence = <String>[];
    for (var quarter = 1; quarter <= 4; quarter++) {
      final size = quarter * data.settings.bootstrap ~/ 4;
      final (_, se) = meanAndSE(values.sublist(0, size));
      convergence.add('$size:${realText(se)}');
    }
    final lines = ['histogram $name $statistic min ${realText(low)} max ${realText(high)} width ${realText((high - low) / bins)} top $top estimate_bin $estimateBin',
      'convergence ${convergence.join(' ')}'];
    for (var index = 0; index < bins; index++) {
      final count = counts[index];
      lines.add(['bin', '${index + 1}', realText(low + (high - low) * index / bins), '$count',
        if (count > 0) bar(count, top), ...marks[index]].join(' '));
    }
    return lines;
  }

  List<String> histogramFile(List<GroupBootstrap> ordinary, List<PairBootstrap> pairs) {
    final lines = <String>[];
    for (final bootstrap in ordinary) {
      for (var column = 0; column < 4; column++) {
        lines.addAll(histogramLines(bootstrap.group.name, groupNames[column], bootstrap.summaries[column]));
      }
    }
    for (final pair in pairs) {
      for (var column = 0; column < 4; column++) {
        lines.addAll(histogramLines(pair.name, pairNames[column], pair.summaries[column]));
      }
    }
    return lines;
  }

  String bcaLine(String statistic, Summary summary, Jackknife jackknife) {
    final replicates = data.settings.bootstrap;
    final below = summary.values.where((value) => value < summary.estimate).length;
    final z0 = phiInverse(below / replicates);
    var squares = 0.0, cubes = 0.0;
    for (final value in jackknife.values) {
      final u = jackknife.average - value;
      squares += u * u;
      cubes += u * u * u;
    }
    final acceleration = cubes / (6 * squares * math.sqrt(squares));
    double alpha(double z) => phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)));
    final lower = ((replicates + 1) * alpha(zLow)).floor().clamp(1, replicates).toInt();
    final upper = (replicates + 1 - ((replicates + 1) * (1 - alpha(-zLow))).floor()).clamp(1, replicates).toInt();
    return 'bca $statistic below $below z0 ${realText(z0)} acceleration ${realText(acceleration)} ranks $lower $upper interval ${realText(summary.ordered[lower - 1])} ${realText(summary.ordered[upper - 1])}';
  }

  List<String> afterBootstrapLines(GroupBootstrap bootstrap, Jackknife meanJackknife) {
    final values = bootstrap.group.values, count = bootstrap.group.values.length;
    final omitted = List.generate(count, (_) => <int>[]);
    for (var number = 0; number < bootstrap.indices.length; number++) {
      final chosen = bootstrap.indices[number].toSet();
      for (var index = 0; index < count; index++) {
        if (!chosen.contains(index)) omitted[index].add(number);
      }
    }
    final errors = <List<double>>[], lines = <String>[];
    for (var statistic = 0; statistic < 4; statistic++) {
      final summary = bootstrap.summaries[statistic], deviations = <double>[];
      for (final replicates in omitted) {
        final (_, se) = meanAndSE([for (final number in replicates) summary.values[number]]);
        deviations.add(se);
      }
      errors.add(deviations);
      final (average, variance) = jackknifeSpread(deviations);
      lines.add('after_bootstrap ${groupNames[statistic]} se ${realText(summary.se)} average ${realText(average)} se_of_se ${realText(math.sqrt(variance))}');
    }
    final sizes = [for (final numbers in omitted) numbers.length]..sort();
    lines.add('without min ${sizes.first} max ${sizes.last}');
    final total = sumIntegers(values);
    final ranking = List.generate(count, (index) => index)..sort((first, second) {
      final compared = (count * values[second] - total).abs().compareTo((count * values[first] - total).abs());
      return compared != 0 ? compared : first.compareTo(second);
    });
    final summary = bootstrap.summaries[0];
    for (var rank = 0; rank < math.min(5, count); rank++) {
      final index = ranking[rank], numbers = omitted[ranking[rank]];
      final influence = (count - 1) * (meanJackknife.average - meanJackknife.values[index]);
      final shifted = orderedReals([for (final number in numbers) summary.values[number] - summary.estimate]);
      final quantiles = [for (final percent in [5, 50, 95]) realText(shifted[ceilDiv(percent * numbers.length, 100) - 1])];
      lines.add('influence ${rank + 1} obs ${index + 1} value ${realText(values[index] / 100)} l ${realText(influence)} without ${numbers.length} se ${realText(errors[0][index])} q05 ${quantiles[0]} q50 ${quantiles[1]} q95 ${quantiles[2]}');
    }
    return lines;
  }

  List<String> groupJackknifeLines(GroupBootstrap bootstrap) {
    final values = bootstrap.group.values, jackknives = <Jackknife>[];
    final lines = ['group ${bootstrap.group.name} n ${values.length}'];
    for (var index = 0; index < 4; index++) {
      final function = groupFunctions[index], summary = bootstrap.summaries[index];
      final jackknife = Jackknife(summary.estimate, [for (var position = 0; position < values.length; position++) function(without(values, position))]);
      jackknives.add(jackknife);
      lines.add('jackknife ${groupNames[index]} estimate ${realText(summary.estimate)} average ${realText(jackknife.average)} bias ${realText(jackknife.bias)} se ${realText(jackknife.se)}');
    }
    for (var index = 0; index < 4; index++) {
      lines.add(bcaLine(groupNames[index], bootstrap.summaries[index], jackknives[index]));
    }
    lines.addAll(afterBootstrapLines(bootstrap, jackknives[0]));
    return lines;
  }

  List<String> jackknifeFile(List<GroupBootstrap> ordinary, List<PairBootstrap> pairs) => [
    for (final bootstrap in ordinary) ...groupJackknifeLines(bootstrap),
    for (final pair in pairs) ...pairJackknifeLines(pair)];

  (List<String>, List<int>) permutationLines(List<int> x, List<int> y) {
    final permutations = data.settings.permutations, combined = [...x, ...y];
    final ranks = doubledRanks(combined), positions = List.generate(combined.length, (index) => index);
    final observed = splitStatistics(combined, ranks, positions, x.length);
    final tallies = [for (final value in observed) Tally(value)];
    for (var replicate = 0; replicate < permutations; replicate++) {
      final order = positions.toList();
      generator.shuffle(order);
      final values = splitStatistics(combined, ranks, order, x.length);
      for (var index = 0; index < 4; index++) {
        tallies[index].count(values[index]);
      }
    }
    final k = x.length, m = y.length, rankTotal = sumIntegers(ranks.sublist(0, x.length));
    final results = [for (final tally in tallies) tally.text(1, permutations + 1)];
    return (['permutation n $k $m perms $permutations',
      'mean diff ${realText(meanDifference(x, y))} ${results[0]}',
      'median diff ${realText(observed[1] / 200)} ${results[1]}',
      'ranksum w ${realText(rankTotal / 2)} u ${realText((rankTotal - k * (k + 1)) / 2)} ${results[2]}',
      'absdev diff ${realText(observed[3] / (200 * k * m))} ${results[3]}'],
      [for (final tally in tallies) tally.extreme]);
  }

  bool simulationRejects(List<int> first, List<int> second) {
    final settings = data.settings, k = first.length, m = second.length;
    final combined = [...first, ...second];
    final total = sumIntegers(combined);
    final observed = contrast(sumIntegers(first), k, sumIntegers(second), m).abs();
    var count = 0;
    for (var replicate = 0; replicate < settings.powerPerms; replicate++) {
      final shuffled = combined.toList();
      generator.shuffle(shuffled);
      final head = sumIntegers(shuffled.sublist(0, k));
      if (contrast(head, k, total - head, m).abs() >= observed) count++;
    }
    return 100 * (count + 1) <= (100 - settings.confidence) * (settings.powerPerms + 1);
  }

  String powerLine(List<int> x, List<int> y) {
    final settings = data.settings;
    var rejections = 0;
    for (var simulation = 0; simulation < settings.powerSims; simulation++) {
      final first = [for (final index in resampleIndices(generator, x.length)) x[index]];
      final second = [for (final index in resampleIndices(generator, y.length)) y[index]];
      if (simulationRejects(first, second)) rejections++;
    }
    final power = rejections / settings.powerSims;
    final se = math.sqrt(power * (1 - power) / settings.powerSims);
    return 'power sims ${settings.powerSims} perms ${settings.powerPerms} rejections $rejections power ${realText(power)} se ${realText(se)}';
  }

  List<String> exactLines(List<int> x, List<int> y) {
    final size = data.settings.pilot, combined = [...x.take(data.settings.pilot), ...y.take(data.settings.pilot)];
    final ranks = doubledRanks(combined), total = sumIntegers(combined);
    final meanValues = <int>[], rankValues = <int>[];
    for (final choice in positionChoices(2 * size, size)) {
      var chosen = 0, rankTotal = 0;
      for (final index in choice) {
        chosen += combined[index];
        rankTotal += ranks[index];
      }
      meanValues.add(contrast(chosen, size, total - chosen, size));
      rankValues.add(rankTotal - size * (2 * size + 1));
    }
    final splits = meanValues.length, meanTally = Tally(meanValues.first), rankTally = Tally(rankValues.first);
    final absolute = <int>[];
    for (var index = 0; index < splits; index++) {
      meanTally.count(meanValues[index]);
      rankTally.count(rankValues[index]);
      absolute.add(meanValues[index].abs());
    }
    var critical = 'critical diff none attained none', cumulative = 0;
    for (final (value, count) in valueCounts(absolute).reversed) {
      cumulative += count;
      if (100 * cumulative > (100 - data.settings.confidence) * splits) break;
      critical = 'critical diff ${realText(value / (100 * size * size))} attained ${pValue(cumulative, splits)}';
    }
    final rankTotal = sumIntegers(ranks.sublist(0, size));
    return ['exact size $size splits $splits',
      'mean diff ${realText(meanDifference(x.sublist(0, size), y.sublist(0, size)))} ${meanTally.text(0, splits)}',
      'ranksum w ${realText(rankTotal / 2)} u ${realText((rankTotal - size * (size + 1)) / 2)} ${rankTally.text(0, splits)}', critical];
  }

  List<String> studentizedLines(PairBootstrap pair) {
    final x = pair.first.group.values, y = pair.second.group.values;
    final k = x.length, m = y.length, estimate = meanDifference(x, y);
    final firstSD = sd(x), secondSD = sd(y);
    final firstVariance = firstSD * firstSD / k, secondVariance = secondSD * secondSD / m;
    final se0 = math.sqrt(firstVariance + secondVariance), statistics = <double>[];
    final t = estimate / se0;
    var extreme = 0;
    for (var index = 0; index < pair.summaries[0].values.length; index++) {
      final first = pair.first.summaries[3].values[index], second = pair.second.summaries[3].values[index];
      final spread = math.sqrt(first * first / k + second * second / m);
      final value = (pair.summaries[0].values[index] - estimate) / spread;
      statistics.add(value);
      if (value.abs() >= t.abs()) extreme++;
    }
    final ordered = orderedReals(statistics);
    final lower = estimate - ordered[ranks.$2 - 1] * se0, upper = estimate - ordered[ranks.$1 - 1] * se0;
    final degrees = (firstVariance + secondVariance) * (firstVariance + secondVariance) /
        (firstVariance * firstVariance / (k - 1) + secondVariance * secondVariance / (m - 1));
    var greater = 0, equal = 0;
    for (final first in x) {
      for (final second in y) {
        if (first > second) greater++;
        if (first == second) equal++;
      }
    }
    final d = cohenD(x, y);
    final hedges = d * (1 - 3 / (4 * (k + m - 2) - 1));
    final cles = (2 * greater + equal) / (2 * k * m);
    return ['bootstrap_t t ${realText(t)} df ${realText(degrees)} extreme $extreme p ${pValue(extreme + 1, data.settings.bootstrap + 1)} interval ${realText(lower)} ${realText(upper)}',
      'effect pooled_sd ${realText(pooledSD(x, y))} cohen_d ${realText(d)} hedges_g ${realText(hedges)} cles ${realText(cles)}'];
  }

  (List<String>, List<int>) pairTestLines(PairBootstrap pair) {
    final first = pair.first.group, second = pair.second.group;
    final (records, extremes) = permutationLines(first.values, second.values);
    return (['compare ${first.name} ${second.name}', ...records,
      powerLine(first.values, second.values), ...exactLines(first.values, second.values),
      ...studentizedLines(pair)], extremes);
  }

  List<String> holmLines(List<List<int>> extremes) {
    final settings = data.settings, count = data.pairs.length, lines = <String>[];
    for (var column = 0; column < 4; column++) {
      final order = List.generate(count, (index) => index)..sort((first, second) {
        final compared = extremes[first][column].compareTo(extremes[second][column]);
        return compared != 0 ? compared : first.compareTo(second);
      });
      var adjusted = 0;
      for (var rank = 0; rank < count; rank++) {
        final index = order[rank], extreme = extremes[order[rank]][column];
        adjusted = math.max(adjusted, math.min(settings.permutations + 1, (count - rank) * (extreme + 1)));
        final decision = 100 * adjusted <= (100 - settings.confidence) * (settings.permutations + 1) ? 'reject' : 'retain';
        final (first, second) = data.pairs[index];
        lines.add('holm ${testNames[column]} rank ${rank + 1} ${first.name} ${second.name} p ${pValue(extreme + 1, settings.permutations + 1)} adjusted ${pValue(adjusted, settings.permutations + 1)} $decision');
      }
    }
    return lines;
  }

  List<String> pairedLines(Summary meanSummary, Summary correlationSummary) {
    final paired = data.paired, count = data.paired.differences.length;
    final positive = paired.differences.where((value) => value > 0).length;
    final negative = paired.differences.where((value) => value < 0).length;
    final average = mean(paired.differences), deviation = sd(paired.differences);
    final r = correlation(paired.before, paired.after);
    final z = 0.5 * math.log((1 + r) / (1 - r));
    final halfWidth = -zLow / math.sqrt(count - 3);
    return ['paired subjects $count positive $positive negative $negative zero ${count - positive - negative}',
      'paired before ${realText(mean(paired.before))} after ${realText(mean(paired.after))} diff ${realText(average)} sd_diff ${realText(deviation)} t ${realText(average / (deviation / math.sqrt(count)))} dz ${realText(average / deviation)}',
      'paired_bootstrap ${meanSummary.intervalText()}',
      'correlation r ${realText(r)} ${correlationSummary.intervalText()} fisher ${realText(hyperbolicTangent(z - halfWidth))} ${realText(hyperbolicTangent(z + halfWidth))}'];
  }

  List<String> signFlipLines() {
    final permutations = data.settings.permutations, differences = data.paired.differences;
    final signed = signedRanks(differences);
    final meanTally = Tally(sumIntegers(differences)), rankTally = Tally(sumIntegers(signed));
    for (var replicate = 0; replicate < permutations; replicate++) {
      var meanTotal = 0, rankTotal = 0;
      for (var index = 0; index < differences.length; index++) {
        final sign = generator.draw().isOdd ? -1 : 1;
        meanTotal += sign * differences[index];
        rankTotal += sign * signed[index];
      }
      meanTally.count(meanTotal);
      rankTally.count(rankTotal);
    }
    final positive = sumIntegers(signed.where((rank) => rank > 0));
    return ['signflip flips $permutations',
      'mean diff ${realText(mean(differences))} ${meanTally.text(1, permutations + 1)}',
      'signedrank w_plus ${realText(positive / 2)} ${rankTally.text(1, permutations + 1)}'];
  }

  List<String> anovaPermutationLines(List<int> combined, List<int> ranks, List<int> sizes, double f, double h, double correction) {
    final permutations = data.settings.permutations, groupCount = sizes.length;
    final pairs = <(int, int)>[for (var first = 0; first < groupCount; first++)
      for (var second = first + 1; second < groupCount; second++) (first, second)];
    final observed = groupDeltas(splitList(combined, sizes), pairs);
    final extremes = List.filled(pairs.length, 0), maxima = List.filled(pairs.length, 0);
    final positions = List.generate(combined.length, (index) => index);
    var fExtreme = 0, hExtreme = 0;
    for (var replicate = 0; replicate < permutations; replicate++) {
      final order = positions.toList();
      generator.shuffle(order);
      final parts = splitList(order, sizes);
      final samples = <List<int>>[], rankSums = <int>[];
      for (final part in parts) {
        samples.add([for (final index in part) combined[index]]);
        rankSums.add(sumIntegers([for (final index in part) ranks[index]]));
      }
      final (between, within) = sumsOfSquares(samples);
      if (fStatistic(between, within, groupCount, combined.length) >= f - 0.000000001 * f) fExtreme++;
      if (hStatistic(rankSums, sizes, correction) >= h - 0.000000001 * h) hExtreme++;
      final deltas = groupDeltas(samples, pairs);
      final largest = largestDelta(deltas);
      for (var index = 0; index < observed.length; index++) {
        if (deltaAtLeast(deltas[index], observed[index])) extremes[index]++;
        if (deltaAtLeast(largest, observed[index])) maxima[index]++;
      }
    }
    final lines = ['anova_permutation perms $permutations f_extreme $fExtreme f_p ${pValue(fExtreme + 1, permutations + 1)} h_extreme $hExtreme h_p ${pValue(hExtreme + 1, permutations + 1)}'];
    for (var index = 0; index < pairs.length; index++) {
      final (firstIndex, secondIndex) = pairs[index];
      final first = data.groups[firstIndex], second = data.groups[secondIndex];
      lines.add('pairwise ${first.name} ${second.name} diff ${realText(meanDifference(first.values, second.values))} extreme ${extremes[index]} p ${pValue(extremes[index] + 1, permutations + 1)} maxt ${maxima[index]} adjusted ${pValue(maxima[index] + 1, permutations + 1)}');
    }
    return lines;
  }

  List<String> anovaLines(List<GroupBootstrap> ordinary) {
    final samples = [for (final group in data.groups) group.values];
    final sizes = [for (final sample in samples) sample.length], combined = <int>[for (final sample in samples) ...sample];
    final groupCount = samples.length, totalCount = combined.length;
    final (between, within) = sumsOfSquares(samples);
    final f = fStatistic(between, within, groupCount, totalCount), eta = between / (between + within);
    final msw = within / (totalCount - groupCount);
    final omega = (between - (groupCount - 1) * msw) / (between + within + msw);
    final etaValues = <double>[];
    for (var number = 0; number < data.settings.bootstrap; number++) {
      final (first, second) = sumsOfSquares([for (final bootstrap in ordinary) bootstrap.samples[number]]);
      etaValues.add(first / (first + second));
    }
    final etaSummary = Summary(eta, etaValues, ranks), allRanks = doubledRanks(combined);
    final rankSums = [for (final part in splitList(allRanks, sizes)) sumIntegers(part)];
    var ties = 0, tieTotal = 0;
    for (final (_, count) in valueCounts(combined)) {
      if (count >= 2) {
        ties++;
        tieTotal += count * count * count - count;
      }
    }
    final correction = 1 - tieTotal / (totalCount * totalCount * totalCount - totalCount);
    final h = hStatistic(rankSums, sizes, correction);
    return ['anova groups $groupCount observations $totalCount ssb ${realText(between)} ssw ${realText(within)} df ${groupCount - 1} ${totalCount - groupCount} f ${realText(f)} eta_squared ${realText(eta)} omega_squared ${realText(omega)}',
      'eta_bootstrap ${etaSummary.intervalText()}', welchLine(samples), 'kruskal h ${realText(h)} tie_groups $ties',
      ...anovaPermutationLines(combined, allRanks, sizes, f, h, correction)];
  }

  Map<String, List<String>> run() {
    final ordinary = <GroupBootstrap>[], balanced = <GroupBootstrap>[];
    final count = data.settings.bootstrap;
    for (final group in data.groups) {
      ordinary.add(GroupBootstrap(group, ordinaryIndices(generator, group.values.length, count), ranks));
    }
    for (final group in data.groups) {
      balanced.add(GroupBootstrap(group, balancedIndices(generator, group.values.length, count), ranks));
    }
    final (meanSummary, correlationSummary) = pairedBootstrap();
    final pairs = [for (final (first, second) in data.pairs)
      PairBootstrap(ordinary[first.number - 1], ordinary[second.number - 1], ranks)];
    final lines = <String>[], extremes = <List<int>>[];
    for (final pair in pairs) {
      final (records, counts) = pairTestLines(pair);
      lines.addAll(records);
      extremes.add(counts);
    }
    lines.addAll(holmLines(extremes));
    lines.addAll(pairedLines(meanSummary, correlationSummary));
    lines.addAll(signFlipLines());
    lines.addAll(anovaLines(ordinary));
    return {'descriptives.txt': descriptiveLines(), 'bootstrap.csv': bootstrapLines(ordinary, balanced, pairs),
      'jackknife.txt': jackknifeFile(ordinary, pairs), 'tests.txt': lines, 'histograms.txt': histogramFile(ordinary, pairs)};
  }
}

double hyperbolicTangent(double value) {
  final growth = math.exp(2 * value);
  return (growth - 1) / (growth + 1);
}

void main() {
  final files = Study(loadDataset()).run();
  Directory('output').createSync(recursive: true);
  for (final entry in files.entries) {
    writeLines(entry.key, entry.value);
  }
}
