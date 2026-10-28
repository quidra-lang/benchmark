part of 'main.dart';

double sum(Iterable<double> values) {
  var total = 0.0;
  for (final v in values) {
    total += v;
  }
  return total;
}

double median(List<double> values) {
  final ordered = List<double>.of(values)..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2;
}

double log10(double value) => log(value) / 2.302585092994046;

class PickMagnitude {
  final Pick pick;
  final double r, ml, md;
  final bool hasML;
  PickMagnitude(this.pick, this.r, this.ml, this.md, this.hasML);
}

PickMagnitude perPickMagnitude(Pick pick, double r, Params p) {
  final md =
      p.real('duration_magnitude') +
      p.real('duration_magnitude', 1) * log10(pick.duration / 100) +
      p.real('duration_magnitude', 2) * r;
  final ml = pick.clipped
      ? 0.0
      : log10(pick.amplitude.toDouble()) +
            p.real('local_magnitude') * log10(r / 100) +
            p.real('local_magnitude', 1) * (r - 100) +
            p.real('local_magnitude', 2);
  return PickMagnitude(pick, r, ml, md, !pick.clipped);
}

String magnitudeClass(int value) =>
    '${value < 0 ? '-' : ''}${value.abs() ~/ 10}.${value.abs() % 10}';
int classNumber(double magnitude) =>
    floorDiv(scaledDecimal(magnitude, 2) + 5, 10);

class FrequencyStats {
  final classes = <int, int>{};
  int minimum = 0, maximum = 0, completeness = 0, nb = 0, n = 0;
  double bvalue = 0,
      sigma = 0,
      avalue = 0,
      slope = 0,
      intercept = 0,
      r = 0,
      meanDiff = 0;
}

FrequencyStats frequencyStatistics(List<Event> events) {
  final result = FrequencyStats(),
      classes = <int>[],
      x = <double>[],
      y = <double>[];
  for (final event in events) {
    if (event.hasML) {
      final c = classNumber(event.ml);
      classes.add(c);
      result.classes[c] = (result.classes[c] ?? 0) + 1;
      x.add(event.md);
      y.add(event.ml);
    }
  }
  result.minimum = classes.reduce(min);
  result.maximum = classes.reduce(max);
  result.completeness = result.minimum;
  for (var c = result.minimum + 1; c <= result.maximum; c++) {
    if ((result.classes[c] ?? 0) > result.classes[result.completeness]!) {
      result.completeness = c;
    }
  }
  var total = 0;
  for (final c in classes) {
    if (c >= result.completeness) {
      result.nb++;
      total += c;
    }
  }
  final mc = result.completeness / 10, mean = total / (10 * result.nb);
  result.bvalue = 0.4342944819032518 / (mean - (mc - 0.05));
  result.sigma = result.bvalue / sqrt(result.nb);
  result.avalue = log10(result.nb.toDouble()) + result.bvalue * mc;
  result.n = x.length;
  final xm = sum(x) / result.n, ym = sum(y) / result.n;
  var xx = 0.0, xy = 0.0, yy = 0.0;
  for (var i = 0; i < x.length; i++) {
    final dx = x[i] - xm, dy = y[i] - ym;
    xx += dx * dx;
    xy += dx * dy;
    yy += dy * dy;
  }
  result.slope = xy / xx;
  result.intercept = ym - result.slope * xm;
  result.r = xy / sqrt(xx * yy);
  result.meanDiff = ym - xm;
  return result;
}
