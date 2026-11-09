part of 'main.dart';

int cross(Point a, Point b) => a.$1 * b.$2 - a.$2 * b.$1;
int rho(Point p, int t, List<Point> trig, int step) =>
    floorDiv(p.$1 * trig[t].$1 + p.$2 * trig[t].$2, 16384 * step);
List<Point> circlePoints(int radius) {
  final set = <Point>{};
  var a = radius, b = 0, error = 1 - radius;
  while (a >= b) {
    set.addAll([
      (a, b),
      (b, a),
      (-b, a),
      (-a, b),
      (-a, -b),
      (-b, -a),
      (b, -a),
      (a, -b),
    ]);
    b++;
    if (error < 0) {
      error += 2 * b + 1;
    } else {
      a--;
      error += 2 * (b - a) + 1;
    }
  }
  int half(Point p) => p.$2 > 0 || p.$2 == 0 && p.$1 > 0 ? 0 : 1;
  return set.toList()..sort((a, b) {
    final h = half(a).compareTo(half(b));
    if (h != 0) {
      return h;
    }
    final c = cross(a, b);
    return c > 0
        ? -1
        : c < 0
        ? 1
        : 0;
  });
}

class CircleCell {
  final int radius, x, y, votes, points;
  CircleCell(this.radius, this.x, this.y, this.votes, this.points);
}

class CircleVoting {
  final int minimum;
  final votes = <Image>[], offsets = <List<Point>>[], peaks = <CircleCell>[];
  int candidates = 0;
  CircleVoting(this.minimum);
}

CircleVoting circleVote(Mask edge, Params p) {
  final width = edge.first.length,
      height = edge.length,
      minimum = p.integer('circle_min_radius'),
      maximum = p.integer('circle_max_radius'),
      result = CircleVoting(minimum);
  for (var r = minimum; r <= maximum; r++) {
    final offsets = circlePoints(r), votes = newImage(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (edge[y][x]) {
          for (final o in offsets) {
            final q = (x + o.$1, y + o.$2);
            if (inside(q, width, height)) {
              votes[q.$2][q.$1]++;
            }
          }
        }
      }
    }
    result.offsets.add(offsets);
    result.votes.add(votes);
  }
  for (var r = minimum; r <= maximum; r++) {
    final index = r - minimum, denominator = result.offsets[index].length;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final votes = result.votes[index][y][x];
        if (100 * votes < p.integer('circle_min_percent') * denominator) {
          continue;
        }
        result.candidates++;
        var peak = true;
        for (
          var otherR = max(minimum, r - 2);
          otherR <= min(maximum, r + 2) && peak;
          otherR++
        ) {
          for (
            var otherY = max(0, y - 2);
            otherY <= min(height - 1, y + 2) && peak;
            otherY++
          ) {
            for (
              var otherX = max(0, x - 2);
              otherX <= min(width - 1, x + 2);
              otherX++
            ) {
              if (otherR == r && otherY == y && otherX == x) {
                continue;
              }
              final other = result.votes[otherR - minimum][otherY][otherX],
                  left = votes * result.offsets[otherR - minimum].length,
                  right = other * denominator,
                  earlier =
                      otherR < r ||
                      otherR == r && (otherY < y || otherY == y && otherX < x);
              if (left < right || left == right && earlier) {
                peak = false;
                break;
              }
            }
          }
        }
        if (peak) {
          result.peaks.add(CircleCell(r, x, y, votes, denominator));
        }
      }
    }
  }
  result.peaks.sort((a, b) {
    final left = a.votes * b.points, right = b.votes * a.points;
    if (left != right) {
      return right.compareTo(left);
    }
    final r = a.radius.compareTo(b.radius), y = a.y.compareTo(b.y);
    return r != 0
        ? r
        : y != 0
        ? y
        : a.x.compareTo(b.x);
  });
  return result;
}

class LineCell {
  final int theta, rho, votes;
  LineCell(this.theta, this.rho, this.votes);
}

class LineVoting {
  final votes = List.generate(180, (_) => <int, int>{}), peaks = <LineCell>[];
  int maximum = 0, low = 0, high = 0;
}

LineVoting lineVote(
  List<Point> points,
  int width,
  int height,
  List<Point> trig,
  int step,
  int threshold,
) {
  final result = LineVoting();
  var initialized = false;
  for (var t = 0; t < 180; t++) {
    for (final p in <Point>[
      (0, 0),
      (width - 1, 0),
      (0, height - 1),
      (width - 1, height - 1),
    ]) {
      final r = rho(p, t, trig, step);
      if (!initialized) {
        result.low = r;
        result.high = r;
        initialized = true;
      }
      result.low = min(result.low, r);
      result.high = max(result.high, r);
    }
    for (final p in points) {
      final r = rho(p, t, trig, step), count = (result.votes[t][r] ?? 0) + 1;
      result.votes[t][r] = count;
      result.maximum = max(result.maximum, count);
    }
  }
  for (var t = 0; t < 180; t++) {
    for (final entry in result.votes[t].entries) {
      final r = entry.key, votes = entry.value;
      if (votes < threshold) {
        continue;
      }
      var peak = true;
      for (
        var otherT = max(0, t - 2);
        otherT <= min(179, t + 2) && peak;
        otherT++
      ) {
        for (var otherR = r - 2; otherR <= r + 2; otherR++) {
          if (otherT == t && otherR == r) {
            continue;
          }
          final v = result.votes[otherT][otherR] ?? 0;
          if (v > votes ||
              v == votes && (otherT < t || otherT == t && otherR < r)) {
            peak = false;
            break;
          }
        }
      }
      if (peak) {
        result.peaks.add(LineCell(t, r, votes));
      }
    }
  }
  result.peaks.sort((a, b) {
    final v = b.votes.compareTo(a.votes), t = a.theta.compareTo(b.theta);
    return v != 0
        ? v
        : t != 0
        ? t
        : a.rho.compareTo(b.rho);
  });
  return result;
}
