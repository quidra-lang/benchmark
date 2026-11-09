part of 'main.dart';

class SuffixArray {
  final List<int> sa, classes;
  SuffixArray(this.sa, this.classes);
}

class AdjacentCheck {
  int ordered = 0, lcpSum = 0, maxLcp = 0, star = 1;
}

int symbol(String c) =>
    const {r'$': 0, '#': 1, 'A': 2, 'C': 3, 'G': 4, 'T': 5}[c]!;
List<int> countingSort(List<int> a, List<int> keys, int classes) {
  final counts = List.filled(classes, 0);
  for (final i in a) {
    counts[keys[i]]++;
  }
  var position = 0;
  for (var i = 0; i < classes; i++) {
    final n = counts[i];
    counts[i] = position;
    position += n;
  }
  final b = List.filled(a.length, 0);
  for (final i in a) {
    final key = keys[i];
    b[counts[key]++] = i;
  }
  return b;
}

SuffixArray suffixArray(String text) {
  final n = text.length,
      positions = [for (var i = 0; i < text.length; i++) i],
      keys = [for (var i = 0; i < text.length; i++) symbol(text[i])];
  var order = countingSort(positions, keys, 6),
      rank = List.filled(n, 0),
      classes = 0,
      previous = -1;
  for (final i in order) {
    if (keys[i] != previous) {
      classes++;
      previous = keys[i];
    }
    rank[i] = classes - 1;
  }
  final counts = [classes];
  for (var h = 1; classes < n; h *= 2) {
    final second = [
      for (var i = 0; i < n; i++) i + h < n ? rank[i + h] + 1 : 0,
    ];
    order = countingSort(
      countingSort(positions, second, classes + 1),
      rank,
      classes,
    );
    final next = List.filled(n, 0);
    var nextClasses = 0, lastA = -1, lastB = -1;
    for (final i in order) {
      if (rank[i] != lastA || second[i] != lastB) {
        nextClasses++;
        lastA = rank[i];
        lastB = second[i];
      }
      next[i] = nextClasses - 1;
    }
    rank = next;
    classes = nextClasses;
    counts.add(classes);
  }
  return SuffixArray(order, counts);
}

List<int> directSort(String text) =>
    [for (var i = 0; i < text.length; i++) i]
      ..sort((a, b) => text.substring(a).compareTo(text.substring(b)));
AdjacentCheck adjacent(String text, List<int> sa) {
  final a = AdjacentCheck();
  for (var i = 1; i < sa.length; i++) {
    final x = sa[i - 1], y = sa[i];
    var l = 0;
    while (text[x + l] == text[y + l]) {
      l++;
    }
    if (symbol(text[x + l]) < symbol(text[y + l])) a.ordered++;
    a.lcpSum += l;
    if (l > a.maxLcp) {
      a.maxLcp = l;
      a.star = i;
    }
  }
  return a;
}
