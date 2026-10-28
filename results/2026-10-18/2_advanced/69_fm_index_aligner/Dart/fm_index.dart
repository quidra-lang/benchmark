part of 'main.dart';

class Interval {
  final int lo, hi;
  const Interval(this.lo, this.hi);
  bool get empty => lo >= hi;
}

class FMIndex {
  final String text, bwt;
  final SuffixArray suffix;
  final List<int> c;
  final List<List<int>> checkpoints;
  final int occInterval;
  final Map<int, int> sample;
  FMIndex(
    this.text,
    this.bwt,
    this.suffix,
    this.c,
    this.checkpoints,
    this.occInterval,
    this.sample,
  );
  int occ(int ch, int i) {
    final q = i ~/ occInterval;
    var value = checkpoints[q][ch];
    for (var j = q * occInterval; j < i; j++) {
      if (symbol(bwt[j]) == ch) value++;
    }
    return value;
  }

  int lf(int row) {
    final ch = symbol(bwt[row]);
    return c[ch] + occ(ch, row);
  }

  Interval extend(Interval iv, String base) {
    if (base == 'N') return const Interval(0, 0);
    final ch = symbol(base);
    return Interval(c[ch] + occ(ch, iv.lo), c[ch] + occ(ch, iv.hi));
  }

  (int, int) locate(int row) {
    var steps = 0;
    while (true) {
      final p = sample[row];
      if (p != null) return (p + steps, steps);
      row = lf(row);
      steps++;
    }
  }

  String inverse() {
    final n = text.length, b = List.filled(text.length, r'$');
    var row = 0;
    for (var p = n - 2; p >= 0; p--) {
      b[p] = bwt[row];
      row = lf(row);
    }
    return b.join();
  }

  Interval exact(String q) {
    var iv = Interval(0, text.length);
    for (var i = q.length - 1; i >= 0; i--) {
      iv = extend(iv, q[i]);
      if (iv.empty) return const Interval(0, 0);
    }
    return iv;
  }
}

FMIndex buildIndex(String text, int occ, int sampleInterval) {
  final suffix = suffixArray(text),
      n = text.length,
      bwt = <String>[],
      counts = List.filled(6, 0);
  for (final p in suffix.sa) {
    bwt.add(text[(p + n - 1) % n]);
    counts[symbol(text[p])]++;
  }
  final c = List.filled(6, 0);
  var total = 0;
  for (var ch = 0; ch < 6; ch++) {
    c[ch] = total;
    total += counts[ch];
  }
  counts.fillRange(0, 6, 0);
  final checkpoints = <List<int>>[], sample = <int, int>{};
  for (var i = 0; i <= n; i++) {
    if (i % occ == 0) checkpoints.add(List.of(counts));
    if (i < n) {
      counts[symbol(bwt[i])]++;
      if (sampleInterval > 0 && suffix.sa[i] % sampleInterval == 0)
        sample[i] = suffix.sa[i];
    }
  }
  return FMIndex(text, bwt.join(), suffix, c, checkpoints, occ, sample);
}
