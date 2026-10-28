part of 'main.dart';

class FlatRun {
  final int first, last;
  final double value;
  FlatRun(this.first, this.last, this.value);
}

class Spike {
  final int time;
  final double residual, median, mad, limit;
  Spike(this.time, this.residual, this.median, this.mad, this.limit);
}

class Gap {
  final int first, last;
  final String cause;
  Gap(this.first, this.last, this.cause);
}

double median(List<double> a) {
  a = List.of(a)..sort();
  final n = a.length;
  return n.isOdd ? a[n ~/ 2] : (a[n ~/ 2 - 1] + a[n ~/ 2]) / 2;
}

List<FlatRun> flatRuns(
  Map<int, double> values,
  int first,
  int last,
  int length,
  Map<int, String> reasons,
) {
  final runs = <FlatRun>[];
  for (var t = first; t <= last;) {
    final value = values[t];
    if (value == null) {
      t++;
      continue;
    }
    var end = t;
    while (end < last && values[end + 1] == value) {
      end++;
    }
    if (end - t + 1 >= length) {
      runs.add(FlatRun(t, end, value));
      for (var u = t + 1; u <= end; u++) {
        reasons[u] = 'flat';
      }
    }
    t = end + 1;
  }
  return runs;
}

(List<Spike>, int) spikeTest(
  List<int> times,
  Map<int, double> residual,
  Settings p,
  Map<int, String> reasons,
) {
  final spikes = <Spike>[];
  var tested = 0;
  for (final t in times) {
    final a = [
      for (final u in times)
        if (u >= t - p.w && u <= t + p.w) residual[u]!,
    ];
    if (a.length < p.c) continue;
    tested++;
    final me = median(a), mad = median(a.map((v) => (v - me).abs()).toList());
    final limit = max(p.ks * 1.4826 * mad, p.d);
    if ((residual[t]! - me).abs() > limit) {
      reasons[t] = 'spike';
      spikes.add(Spike(t, residual[t]!, me, mad, limit));
    }
  }
  return (spikes, tested);
}

List<Gap> listGaps(int first, int last, Map<int, String> reasons) {
  final gaps = <Gap>[];
  for (var t = first; t <= last;) {
    var cause = reasons[t];
    if (cause == null) {
      t++;
      continue;
    }
    var end = t;
    while (end < last && reasons[end + 1] != null) {
      end++;
      if (reasons[end] != cause) cause = 'mixed';
    }
    gaps.add(Gap(t, end, cause!));
    t = end + 1;
  }
  return gaps;
}
