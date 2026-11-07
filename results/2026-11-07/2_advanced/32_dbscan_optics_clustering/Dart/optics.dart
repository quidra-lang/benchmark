part of 'main.dart';

const infinity = 1 << 62;
List<int> coreDistances(
  List<Point> points,
  List<List<int>> neighborhoods,
  int minPts,
) {
  final core = List.filled(points.length, infinity);
  for (var i = 0; i < points.length; i++) {
    if (neighborhoods[i].length >= minPts) {
      final values =
          neighborhoods[i]
              .map((other) => squaredDistance(points[i], points[other]))
              .toList()
            ..sort();
      core[i] = values[minPts - 1];
    }
  }
  return core;
}

(List<int>, List<int>, List<int>) opticsOrdering(
  List<Point> points,
  List<List<int>> neighborhoods,
  List<int> core,
) {
  final reach = List.filled(points.length, infinity),
      predecessor = List.filled(points.length, -1),
      processed = List.filled(points.length, false),
      order = <int>[];
  for (var start = 0; start < points.length; start++) {
    if (processed[start]) continue;
    final seeds = {start};
    while (seeds.isNotEmpty) {
      var current = -1;
      for (final point in seeds) {
        if (current < 0 ||
            reach[point] < reach[current] ||
            reach[point] == reach[current] &&
                points[point].id < points[current].id)
          current = point;
      }
      seeds.remove(current);
      processed[current] = true;
      order.add(current);
      if (core[current] == infinity) continue;
      for (final other in neighborhoods[current]) {
        if (processed[other]) continue;
        final distance = math.max(
          core[current],
          squaredDistance(points[current], points[other]),
        );
        if (distance < reach[other]) {
          reach[other] = distance;
          predecessor[other] = current;
          seeds.add(other);
        }
      }
    }
  }
  return (order, reach, predecessor);
}
