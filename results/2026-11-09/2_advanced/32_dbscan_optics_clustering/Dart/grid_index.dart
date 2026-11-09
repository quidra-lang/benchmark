part of 'main.dart';

int squaredDistance(Point a, Point b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return dx * dx + dy * dy;
}

class GridIndex {
  final List<Point> points;
  final int eps;
  final cells = <(int, int), List<int>>{};
  GridIndex(this.points, this.eps) {
    for (var i = 0; i < points.length; i++) {
      cells.putIfAbsent(cellOf(points[i]), () => []).add(i);
    }
  }
  (int, int) cellOf(Point point) => (point.x ~/ eps, point.y ~/ eps);
  (List<int>, int) neighborhood(int index) {
    final point = points[index],
        cell = cellOf(points[index]),
        neighbors = <int>[];
    var candidates = 0;
    for (var y = cell.$2 - 1; y <= cell.$2 + 1; y++) {
      for (var x = cell.$1 - 1; x <= cell.$1 + 1; x++) {
        for (final other in cells[(x, y)] ?? <int>[]) {
          candidates++;
          if (squaredDistance(point, points[other]) <= eps * eps)
            neighbors.add(other);
        }
      }
    }
    return (neighbors, candidates);
  }

  ((int, int), int) busiest() {
    var best = (0, 0), count = -1;
    for (final entry in cells.entries) {
      final cell = entry.key;
      if (entry.value.length > count ||
          entry.value.length == count &&
              (cell.$2 < best.$2 || cell.$2 == best.$2 && cell.$1 < best.$1)) {
        best = cell;
        count = entry.value.length;
      }
    }
    return (best, count);
  }
}

List<int> bruteForceCounts(List<Point> points, int eps) => [
  for (final point in points)
    points.where((other) => squaredDistance(point, other) <= eps * eps).length,
];
