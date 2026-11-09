part of 'main.dart';

typedef Vec = (int, int, int);
int coordinate(Vec p, int axis) => axis == 0
    ? p.$1
    : axis == 1
    ? p.$2
    : p.$3;
Vec subtract(Vec a, Vec b) => (a.$1 - b.$1, a.$2 - b.$2, a.$3 - b.$3);
Vec cross(Vec a, Vec b) => (
  a.$2 * b.$3 - a.$3 * b.$2,
  a.$3 * b.$1 - a.$1 * b.$3,
  a.$1 * b.$2 - a.$2 * b.$1,
);
int dot(Vec a, Vec b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
Vec normal(Face f, List<Vec> points) => cross(
  subtract(points[f.vertices[1]], points[f.vertices[0]]),
  subtract(points[f.vertices[2]], points[f.vertices[0]]),
);
int determinant(Face f, List<Vec> points) => dot(
  points[f.vertices[0]],
  cross(points[f.vertices[1]], points[f.vertices[2]]),
);
double area(List<Face> faces, List<Vec> points) {
  var total = 0.0;
  for (final f in faces) {
    final n = normal(f, points);
    total += math.sqrt(dot(n, n));
  }
  return total / 2;
}

String triangleAngle(Face f, List<Vec> points) {
  final a = points[f.vertices[0]],
      b = points[f.vertices[1]],
      c = points[f.vertices[2]];
  final smallest = [
    dot(subtract(b, a), subtract(c, a)),
    dot(subtract(c, b), subtract(a, b)),
    dot(subtract(a, c), subtract(b, c)),
  ].reduce(math.min);
  return smallest < 0
      ? 'obtuse'
      : smallest == 0
      ? 'right'
      : 'acute';
}

int edgeLengthSquared(Edge e, List<Vec> points) {
  final d = subtract(points[e.$1], points[e.$2]);
  return dot(d, d);
}

int windingNumber(
  List<int> ids,
  List<Face> faces,
  List<Vec> points,
  Vec sample,
) {
  var total = 0.0;
  for (final id in ids) {
    final f = faces[id - 1],
        a = subtract(points[f.vertices[0]], sample),
        b = subtract(points[f.vertices[1]], sample),
        c = subtract(points[f.vertices[2]], sample);
    final la = math.sqrt(dot(a, a)),
        lb = math.sqrt(dot(b, b)),
        lc = math.sqrt(dot(c, c)),
        numerator = dot(a, cross(b, c)),
        denominator =
            la * lb * lc + dot(a, b) * lc + dot(b, c) * la + dot(c, a) * lb;
    total += 2 * math.atan2(numerator, denominator);
  }
  return (total / (4 * math.pi)).round();
}

int volume6(List<int> ids, List<Face> faces, List<Vec> points) {
  var total = 0;
  for (final id in ids) {
    total += determinant(faces[id - 1], points);
  }
  return total;
}

List<String> centroid(
  List<int> ids,
  List<Face> faces,
  List<Vec> points,
  int sixVolume,
) {
  final result = <String>[];
  for (var axis = 0; axis < 3; axis++) {
    var numerator = 0;
    for (final id in ids) {
      final f = faces[id - 1], signed = determinant(f, points);
      numerator +=
          signed *
          (coordinate(points[f.vertices[0]], axis) +
              coordinate(points[f.vertices[1]], axis) +
              coordinate(points[f.vertices[2]], axis));
    }
    result.add(fraction(numerator, 4 * sixVolume));
  }
  return result;
}

String fraction(int n, int d) {
  if (d < 0) {
    n = -n;
    d = -d;
  }
  final divisor = n.abs().gcd(d);
  n ~/= divisor;
  d ~/= divisor;
  return d == 1 ? '$n' : '$n/$d';
}

String real(double value) => value.toStringAsFixed(3);
List<int> bbox(List<int> vertices, List<Vec> points) {
  final first = points[vertices.first],
      box = [first.$1, first.$2, first.$3, first.$1, first.$2, first.$3];
  for (final v in vertices) {
    for (var axis = 0; axis < 3; axis++) {
      final x = coordinate(points[v], axis);
      box[axis] = math.min(box[axis], x);
      box[axis + 3] = math.max(box[axis + 3], x);
    }
  }
  return box;
}
