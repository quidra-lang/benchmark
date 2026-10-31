part of 'main.dart';

double distance(Point a, Point b) {
  final x = a.$1 - b.$1, y = a.$2 - b.$2;
  return sqrt(x * x + y * y);
}

String fixed(double v) {
  final s = v.toStringAsFixed(4);
  return s == '-0.0000' ? '0.0000' : s;
}

double ospa(List<Point> first, List<Point> second, double cutoff) {
  if (first.isEmpty && second.isEmpty) return 0;
  if (first.isEmpty || second.isEmpty) return cutoff;
  var x = first, y = second;
  if (x.length > y.length) {
    final temp = x;
    x = y;
    y = temp;
  }
  final cost = zeros(x.length, y.length),
      usable = List.generate(x.length, (_) => List.filled(y.length, true));
  for (var i = 0; i < x.length; i++) {
    for (var j = 0; j < y.length; j++) {
      final d = min(cutoff, distance(x[i], y[j]));
      cost[i][j] = d * d;
    }
  }
  final chosen = assignment(cost, usable, y.length);
  var sum = 0.0;
  for (var i = 0; i < chosen.length; i++) {
    sum += cost[i][chosen[i]];
  }
  return sqrt((sum + cutoff * cutoff * (y.length - x.length)) / y.length);
}

class Continuity {
  int covered = 0, breaks = 0, swaps = 0, delay = -1;
}

Continuity continuity(List<int> labels) {
  final out = Continuity();
  var groups = 0, previous = -1, active = false;
  for (var scan = 0; scan < labels.length; scan++) {
    final label = labels[scan];
    if (label < 0) {
      active = false;
      continue;
    }
    out.covered++;
    if (out.delay < 0) out.delay = scan;
    if (!active) groups++;
    if (previous >= 0 && previous != label) out.swaps++;
    previous = label;
    active = true;
  }
  out.breaks = max(0, groups - 1);
  return out;
}

String bestFilter(List<double> values) {
  var best = 0;
  for (var i = 1; i < 5; i++) {
    if (double.parse(fixed(values[i])) < double.parse(fixed(values[best])))
      best = i;
  }
  return filterNames[best];
}

String filterValues(List<double> values) => [
  for (var i = 0; i < 5; i++) '${filterNames[i]} ${fixed(values[i])}',
].join(' ');
