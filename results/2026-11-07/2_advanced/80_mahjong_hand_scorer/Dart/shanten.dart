part of 'main.dart';

class Shanten {
  final Map<String, int> memo = {};
  int standard(List<int> a, int m, int t, int h) {
    final key = String.fromCharCodes([...a, m, t, h]), cached = memo[key];
    if (cached != null) return cached;
    var best = 8 - 2 * m - min(t, 4 - m) - h;
    final first = a.indexWhere((c) => c > 0);
    if (first < 0) return best;
    a[first]--;
    best = min(best, standard(a, m, t, h));
    a[first]++;
    if (m < 4) {
      if (a[first] >= 3) {
        a[first] -= 3;
        best = min(best, standard(a, m + 1, t, h));
        a[first] += 3;
      }
      if (first < 27 &&
          first % 9 <= 6 &&
          a[first + 1] > 0 &&
          a[first + 2] > 0) {
        a[first]--;
        a[first + 1]--;
        a[first + 2]--;
        best = min(best, standard(a, m + 1, t, h));
        a[first]++;
        a[first + 1]++;
        a[first + 2]++;
      }
    }
    if (a[first] >= 2) {
      a[first] -= 2;
      if (h == 0) best = min(best, standard(a, m, t, 1));
      if (t < 4) best = min(best, standard(a, m, t + 1, h));
      a[first] += 2;
    }
    if (t < 4 && first < 27) {
      for (var delta = 1; delta <= 2; delta++) {
        if (first % 9 + delta <= 8 && a[first + delta] > 0) {
          a[first]--;
          a[first + delta]--;
          best = min(best, standard(a, m, t + 1, h));
          a[first]++;
          a[first + delta]++;
        }
      }
    }
    memo[key] = best;
    return best;
  }

  List<int> numbers(List<int> a) {
    var pairs = 0, distinct = 0, orphans = 0, hasOrphanPair = false;
    for (var kind = 0; kind < 34; kind++) {
      final n = a[kind];
      if (n > 0) {
        distinct++;
        if (yaochuu(kind)) orphans++;
      }
      if (n >= 2) {
        pairs++;
        if (yaochuu(kind)) hasOrphanPair = true;
      }
    }
    return [
      standard(a, 0, 0, 0),
      6 - pairs + max(0, 7 - distinct),
      13 - orphans - (hasOrphanPair ? 1 : 0),
    ];
  }
}

int minimumShanten(List<int> a) => min(a[0], min(a[1], a[2]));
