part of 'main.dart';

const directions = [
  (1, 0),
  (-1, 0),
  (0, 1),
  (0, -1),
  (1, 1),
  (-1, -1),
  (-1, 1),
  (1, -1),
];
Volume aggregate(
  Volume base,
  Image left,
  Params p,
  void Function(int, Volume) observe,
) {
  final n = base.length,
      d = p.max - p.min + 1,
      summed = List.generate(
        base.length,
        (_) => List.filled(p.max - p.min + 1, 0),
      );
  for (var path = 0; path < p.paths; path++) {
    final (rx, ry) = directions[path];
    final values = List.generate(n, (_) => List.filled(d, 0)),
        y0 = ry < 0 ? left.h - 1 : 0,
        yEnd = ry < 0 ? -1 : left.h,
        ys = ry < 0 ? -1 : 1,
        x0 = rx < 0 ? left.w - 1 : 0,
        xEnd = rx < 0 ? -1 : left.w,
        xs = rx < 0 ? -1 : 1;
    for (var y = y0; y != yEnd; y += ys) {
      for (var x = x0; x != xEnd; x += xs) {
        final index = y * left.w + x, qx = x - rx, qy = y - ry;
        if (qx < 0 || qx >= left.w || qy < 0 || qy >= left.h) {
          values[index] = List.of(base[index]);
        } else {
          final q = qy * left.w + qx,
              minimum = values[q].reduce(min),
              penalty = max(
                p.p1,
                p.p2 *
                    p.gamma ~/
                    (p.gamma + (left.pixels[index] - left.pixels[q]).abs()),
              );
          for (var di = 0; di < d; di++) {
            var best = min(values[q][di], minimum + penalty);
            if (di > 0) best = min(best, values[q][di - 1] + p.p1);
            if (di + 1 < d) best = min(best, values[q][di + 1] + p.p1);
            values[index][di] = base[index][di] + best - minimum;
          }
        }
        for (var di = 0; di < d; di++) {
          summed[index][di] += values[index][di];
        }
      }
    }
    observe(path + 1, summed);
  }
  return summed;
}
