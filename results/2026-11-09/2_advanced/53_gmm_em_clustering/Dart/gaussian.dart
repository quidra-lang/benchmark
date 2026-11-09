part of 'main.dart';

double determinant(Covariance s) => s.a * s.c - s.b * s.b;
double mahalanobis(Point point, Point mean, Covariance s) {
  final dx = point.x - mean.x, dy = point.y - mean.y;
  return (s.c * dx * dx - 2 * s.b * dx * dy + s.a * dy * dy) / determinant(s);
}

double weightedLogDensity(Point point, Component c) =>
    log(c.weight) -
    log(2 * pi) -
    log(determinant(c.cov)) / 2 -
    mahalanobis(point, c.mean, c.cov) / 2;

class EigenData {
  final double leading, trailing;
  final Point direction;
  final double angle, major, minor, area, correlation;
  EigenData(
    this.leading,
    this.trailing,
    this.direction,
    this.angle,
    this.major,
    this.minor,
    this.area,
    this.correlation,
  );
}

EigenData eigenData(Covariance s) {
  final h = (s.a + s.c) / 2,
      d = (s.a - s.c) / 2,
      g = sqrt(d * d + s.b * s.b),
      leading = h + g,
      trailing = h - g;
  var direction = const Point(1, 0);
  if (s.b == 0) {
    if (s.a < s.c) {
      direction = const Point(0, 1);
    }
  } else {
    var vx = s.a >= s.c ? leading - s.c : s.b,
        vy = s.a >= s.c ? s.b : leading - s.a;
    final length = sqrt(vx * vx + vy * vy);
    if (vx < 0) {
      vx = -vx;
      vy = -vy;
    }
    direction = Point(vx / length, vy / length);
  }
  return EigenData(
    leading,
    trailing,
    direction,
    atan2(direction.y, direction.x) * 180 / pi,
    sqrt(leading),
    sqrt(trailing),
    pi * sqrt(leading * trailing),
    s.b / sqrt(s.a * s.c),
  );
}

(double, double) bhattacharyya(Component a, Component b) {
  final mean = Covariance(
        (a.cov.a + b.cov.a) / 2,
        (a.cov.b + b.cov.b) / 2,
        (a.cov.c + b.cov.c) / 2,
      ),
      d =
          mahalanobis(b.mean, a.mean, mean) / 8 +
          log(
                determinant(mean) /
                    sqrt(determinant(a.cov) * determinant(b.cov)),
              ) /
              2;
  return (d, exp(-d));
}
