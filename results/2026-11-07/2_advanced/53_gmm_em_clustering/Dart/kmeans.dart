part of 'main.dart';

double distance2(Point a, Point b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return dx * dx + dy * dy;
}

double distance(Point a, Point b) => sqrt(distance2(a, b));
List<int> assignments(List<DataPoint> points, List<Point> centers) {
  final result = <int>[];
  for (final point in points) {
    var best = 0;
    for (var k = 1; k < centers.length; k++) {
      if (distance2(point.point, centers[k]) <
          distance2(point.point, centers[best])) {
        best = k;
      }
    }
    result.add(best);
  }
  return result;
}

class KMeans {
  final List<Point> centers;
  final List<int> assignment, sizes;
  final int iterations;
  final double inertia;
  KMeans(
    this.centers,
    this.assignment,
    this.sizes,
    this.iterations,
    this.inertia,
  );
}

KMeans runKMeans(List<DataPoint> points, List<Point> initial, int maximum) {
  var centers = List<Point>.of(initial),
      assigned = assignments(points, initial),
      iterations = 0;
  for (var t = 1; t <= maximum; t++) {
    final next = List<Point>.of(centers);
    for (var k = 0; k < centers.length; k++) {
      var x = 0.0, y = 0.0, count = 0;
      for (var i = 0; i < points.length; i++) {
        if (assigned[i] == k) {
          count++;
          x += points[i].point.x;
          y += points[i].point.y;
        }
      }
      if (count > 0) {
        next[k] = Point(x / count, y / count);
      }
    }
    centers = next;
    final nextAssigned = assignments(points, centers);
    iterations = t;
    final same = listEqual(assigned, nextAssigned);
    assigned = nextAssigned;
    if (same) {
      break;
    }
  }
  final sizes = List.filled(centers.length, 0);
  var inertia = 0.0;
  for (var i = 0; i < points.length; i++) {
    sizes[assigned[i]]++;
    inertia += distance2(points[i].point, centers[assigned[i]]);
  }
  return KMeans(centers, assigned, sizes, iterations, inertia);
}
