part of 'main.dart';

typedef Mask = List<List<bool>>;
Mask newMask(int width, int height) =>
    List.generate(height, (_) => List.filled(width, false));
bool inside(Point p, int width, int height) =>
    p.$1 >= 0 && p.$1 < width && p.$2 >= 0 && p.$2 < height;
List<Point> neighbors(Point p, int width, int height) => [
  for (var dy = -1; dy <= 1; dy++)
    for (var dx = -1; dx <= 1; dx++)
      if ((dx != 0 || dy != 0) && inside((p.$1 + dx, p.$2 + dy), width, height))
        (p.$1 + dx, p.$2 + dy),
];
Image directions(Image gx, Image gy) {
  final result = newImage(gx.first.length, gx.length);
  for (var y = 0; y < gx.length; y++) {
    for (var x = 0; x < gx[y].length; x++) {
      final ax = gx[y][x].abs(), ay = gy[y][x].abs();
      result[y][x] = 29 * ay <= 12 * ax
          ? 0
          : 29 * ay >= 70 * ax
          ? 90
          : gx[y][x] * gy[y][x] < 0
          ? 45
          : 135;
    }
  }
  return result;
}

Image suppress(Image magnitude, Image direction) {
  final width = magnitude.first.length,
      height = magnitude.length,
      result = newImage(width, height);
  const offsets = <int, Point>{
    0: (-1, 0),
    45: (1, -1),
    90: (0, -1),
    135: (-1, -1),
  };
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final d = offsets[direction[y][x]]!, value = magnitude[y][x];
      if (value > magnitude[y + d.$2][x + d.$1] &&
          value >= magnitude[y - d.$2][x - d.$1]) {
        result[y][x] = value;
      }
    }
  }
  return result;
}

(Mask, int, int, int) hysteresis(Image nms, int low, int high) {
  final width = nms.first.length,
      height = nms.length,
      edge = newMask(width, height),
      queue = <Point>[];
  var strong = 0, weak = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = nms[y][x];
      if (value >= high) {
        strong++;
        edge[y][x] = true;
        queue.add((x, y));
      } else if (value >= low) {
        weak++;
      }
    }
  }
  for (var i = 0; i < queue.length; i++) {
    for (final q in neighbors(queue[i], width, height)) {
      if (!edge[q.$2][q.$1] && nms[q.$2][q.$1] >= low) {
        edge[q.$2][q.$1] = true;
        queue.add(q);
      }
    }
  }
  return (edge, strong, weak, queue.length - strong);
}

List<List<Point>> components(Mask edge) {
  final width = edge.first.length,
      height = edge.length,
      seen = newMask(width, height),
      groups = <List<Point>>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!edge[y][x] || seen[y][x]) {
        continue;
      }
      seen[y][x] = true;
      final queue = <Point>[(x, y)];
      for (var i = 0; i < queue.length; i++) {
        for (final q in neighbors(queue[i], width, height)) {
          if (edge[q.$2][q.$1] && !seen[q.$2][q.$1]) {
            seen[q.$2][q.$1] = true;
            queue.add(q);
          }
        }
      }
      groups.add(queue);
    }
  }
  return groups;
}
