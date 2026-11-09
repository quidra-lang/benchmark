part of 'main.dart';

bool isLetter(String c) => RegExp(r'^[A-Za-z]$').hasMatch(c);

class Hyphenation {
  final words = <String, List<int>>{};
  final int leftMin, rightMin;
  Hyphenation(
    List<String> lines,
    List<String> additions,
    this.leftMin,
    this.rightMin,
  ) {
    for (final spelling in [...lines, ...additions]) {
      register(spelling);
    }
  }
  void register(String spelling) {
    final parts = spelling.split('-'), points = <int>[];
    var position = 0;
    for (final part in parts.take(parts.length - 1)) {
      position += part.length;
      points.add(position);
    }
    words[parts.join()] = points;
  }

  List<(int, bool)> splitPoints(String word) {
    final points = <int, bool>{};
    var first = 0, last = word.length;
    while (first < word.length && !isLetter(word[first])) {
      first++;
    }
    while (last > first && !isLetter(word[last - 1])) {
      last--;
    }
    final core = word.substring(first, last);
    if (core.isNotEmpty && core.split('').every(isLetter)) {
      for (final p in words[core.toLowerCase()] ?? <int>[]) {
        if (p >= leftMin && core.length - p >= rightMin)
          points[first + p] = true;
      }
    }
    for (var p = 1; p < word.length - 1; p++) {
      if (word[p] == '-' && isLetter(word[p - 1]) && isLetter(word[p + 1]))
        points[p + 1] = false;
    }
    final positions = points.keys.toList()..sort();
    return [for (final p in positions) (p, points[p]!)];
  }
}
