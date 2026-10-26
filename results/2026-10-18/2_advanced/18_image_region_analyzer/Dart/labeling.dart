import 'dart:math' as math;
import 'morphology.dart';

class Labeling {
  final List<List<int>> labels;
  final int count;
  final int provisional;
  Labeling(this.labels, this.count, this.provisional);
}

int findRoot(List<int> parents, int label) {
  while (parents[label] != label) {
    parents[label] = parents[parents[label]];
    label = parents[label];
  }
  return label;
}

void unionRoots(List<int> parents, int first, int second) {
  final a = findRoot(parents, first);
  final b = findRoot(parents, second);
  if (a != b) {
    parents[math.max(a, b)] = math.min(a, b);
  }
}

Labeling labelComponents(Mask mask, int connectivity) {
  final height = mask.length, width = mask.first.length;
  final previous = connectivity == 4 ? [const Point(-1, 0), const Point(0, -1)] : [const Point(-1, 0), const Point(-1, -1), const Point(0, -1), const Point(1, -1)];
  final provisional = List.generate(height, (_) => List.filled(width, 0));
  final parents = [0];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!mask[y][x]) {
        continue;
      }
      final neighbors = <int>[];
      for (final offset in previous) {
        final nx = x + offset.x, ny = y + offset.y;
        if (occupied(mask, nx, ny)) {
          neighbors.add(provisional[ny][nx]);
        }
      }
      if (neighbors.isEmpty) {
        provisional[y][x] = parents.length;
        parents.add(parents.length);
      } else {
        provisional[y][x] = neighbors.first;
        for (final other in neighbors.skip(1)) {
          unionRoots(parents, neighbors.first, other);
        }
      }
    }
  }
  final numbers = List.filled(parents.length, 0);
  final labels = List.generate(height, (_) => List.filled(width, 0));
  var count = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (provisional[y][x] == 0) {
        continue;
      }
      final root = findRoot(parents, provisional[y][x]);
      if (numbers[root] == 0) {
        numbers[root] = ++count;
      }
      labels[y][x] = numbers[root];
    }
  }
  return Labeling(labels, count, parents.length - 1);
}

int bitQuadEuler(Mask mask, int connectivity) {
  var singles = 0, triples = 0, diagonals = 0;
  for (var y = -1; y < mask.length; y++) {
    for (var x = -1; x < mask.first.length; x++) {
      final tl = occupied(mask, x, y), tr = occupied(mask, x + 1, y);
      final bl = occupied(mask, x, y + 1), br = occupied(mask, x + 1, y + 1);
      final count = [tl, tr, bl, br].where((value) => value).length;
      if (count == 1) {
        singles++;
      } else if (count == 3) {
        triples++;
      } else if (count == 2 && ((tl && br) || (tr && bl))) {
        diagonals++;
      }
    }
  }
  return (singles - triples + (connectivity == 8 ? -2 : 2) * diagonals) ~/ 4;
}
