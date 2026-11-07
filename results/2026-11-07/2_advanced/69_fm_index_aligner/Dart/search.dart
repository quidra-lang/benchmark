part of 'main.dart';

class SearchLeaf {
  final Interval interval;
  final int mismatches;
  SearchLeaf(this.interval, this.mismatches);
}

class SearchResult {
  final List<SearchLeaf> leaves = [];
  int nodes = 0, hits = 0;
}

List<int> lowerBound(FMIndex reverse, String w) {
  final d = List.filled(w.length, 0);
  var z = 0, iv = Interval(0, reverse.text.length);
  for (var i = 0; i < w.length; i++) {
    iv = reverse.extend(iv, w[i]);
    if (iv.empty) {
      z++;
      iv = Interval(0, reverse.text.length);
    }
    d[i] = z;
  }
  return d;
}

SearchResult backtrack(FMIndex forward, FMIndex reverse, String w, int zmax) {
  final d = lowerBound(reverse, w),
      stack = [(w.length - 1, zmax, 0, forward.text.length)],
      result = SearchResult();
  while (stack.isNotEmpty) {
    final (i, z, lo, hi) = stack.removeLast();
    result.nodes++;
    final bound = i >= 0 ? d[i] : 0;
    if (z < bound) continue;
    if (i < 0) {
      result.leaves.add(SearchLeaf(Interval(lo, hi), zmax - z));
      result.hits += hi - lo;
      continue;
    }
    for (final b in ['T', 'G', 'C', 'A']) {
      final iv = forward.extend(Interval(lo, hi), b);
      if (iv.empty) continue;
      var remaining = z;
      if (b != w[i]) {
        if (remaining == 0) continue;
        remaining--;
      }
      stack.add((i - 1, remaining, iv.lo, iv.hi));
    }
  }
  return result;
}
