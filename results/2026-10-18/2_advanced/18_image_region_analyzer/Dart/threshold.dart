import 'dart:math' as math;
import 'pgm_reader.dart';

class Histogram {
  final int maxval;
  final int pixels;
  late final List<int> counts;
  final belowCounts = <int>[];
  final belowSums = <int>[];
  var total = 0;
  late int minimum;
  var maximum = 0, median = -1, mode = 0, levels = 0;
  late final int binWidth;
  final bins = <int>[];

  Histogram(Image image) : maxval = image.maxval, pixels = image.width * image.height {
    counts = List.filled(maxval + 1, 0);
    minimum = maxval;
    for (final row in image.pixels) {
      for (final value in row) {
        counts[value]++;
      }
    }
    var count = 0;
    for (var value = 0; value <= maxval; value++) {
      final frequency = counts[value];
      count += frequency;
      total += value * frequency;
      belowCounts.add(count);
      belowSums.add(total);
      if (frequency > 0) {
        minimum = math.min(minimum, value);
        maximum = value;
        levels++;
      }
      if (median < 0 && 2 * count >= pixels) {
        median = value;
      }
      if (frequency > counts[mode]) {
        mode = value;
      }
    }
    binWidth = (maxval + 8) ~/ 8;
    for (var start = 0; start <= maxval; start += binWidth) {
      bins.add(counts.sublist(start, math.min(start + binWidth, counts.length)).fold(0, (sum, value) => sum + value));
    }
  }

  (int, int, int, int) split(int cutoff) => (belowCounts[cutoff], belowSums[cutoff], pixels - belowCounts[cutoff], total - belowSums[cutoff]);
}

class Candidate {
  final int cutoff;
  final int below;
  final int sumBelow;
  final int above;
  final int sumAbove;
  late final int numerator = sumBelow * sumBelow * above + sumAbove * sumAbove * below;
  late final int denominator = below * above;
  Candidate(this.cutoff, this.below, this.sumBelow, this.above, this.sumAbove);
}

int compareScores(Candidate first, Candidate second) {
  final q1 = first.numerator ~/ first.denominator;
  final q2 = second.numerator ~/ second.denominator;
  if (q1 != q2) {
    return q1.compareTo(q2);
  }
  return ((first.numerator % first.denominator) * second.denominator).compareTo((second.numerator % second.denominator) * first.denominator);
}

class OtsuResult {
  final int cutoff;
  final int upper;
  final List<Candidate> candidates;
  OtsuResult(this.cutoff, this.upper, this.candidates);
}

OtsuResult otsu(Histogram data) {
  final candidates = <Candidate>[];
  for (var cutoff = 0; cutoff < data.maxval; cutoff++) {
    final (below, sumBelow, above, sumAbove) = data.split(cutoff);
    if (data.counts[cutoff] > 0 && above > 0) {
      candidates.add(Candidate(cutoff, below, sumBelow, above, sumAbove));
    }
  }
  candidates.sort((first, second) {
    final order = compareScores(second, first);
    return order == 0 ? first.cutoff.compareTo(second.cutoff) : order;
  });
  if (candidates.isEmpty) {
    return OtsuResult(data.minimum, data.minimum, candidates);
  }
  final cutoff = candidates.first.cutoff;
  var following = cutoff + 1;
  while (data.counts[following] == 0) {
    following++;
  }
  return OtsuResult(cutoff, following - 1, candidates);
}

(int, int) isodata(Histogram data) {
  var cutoff = data.total ~/ data.pixels;
  var iterations = 0;
  while (true) {
    final (below, sumBelow, above, sumAbove) = data.split(cutoff);
    if (below == 0 || above == 0) {
      break;
    }
    final following = (sumBelow * above + sumAbove * below) ~/ (2 * below * above);
    iterations++;
    if (following == cutoff) {
      break;
    }
    cutoff = following;
    if (iterations == 100) {
      break;
    }
  }
  return (cutoff, iterations);
}
