import 'dart:math';
import 'canvas.dart';
import 'clipping.dart';
import 'primitives.dart';

Set<Point> fillPolygons(List<List<Point>> sequences, String rule, Rect clip) {
  final edges = <(Point, Point)>[]; for (final vertices in sequences) { for (var i = 0; i < vertices.length; i++) { final s = vertices[i], e = vertices[(i + 1) % vertices.length]; if (s.$2 != e.$2) edges.add((s, e)); } } final pixels = <Point>{};
  for (var y = clip.$2; y <= clip.$4; y++) { final crossings = <(int, int)>[]; for (final (s, e) in edges) { if (y < min(s.$2, e.$2) || y >= max(s.$2, e.$2)) continue; var d = e.$2 - s.$2, n = 2 * s.$1 * (e.$2 - s.$2) + (2 * y + 1 - 2 * s.$2) * (e.$1 - s.$1); final direction = d > 0 ? 1 : -1; if (d < 0) { n = -n; d = -d; } crossings.add((floorRatio(n - d, 2 * d) + 1, direction)); } crossings.sort((a, b) { final c = a.$1.compareTo(b.$1); return c != 0 ? c : a.$2.compareTo(b.$2); }); var count = 0, wind = 0, index = 0;
    for (var x = clip.$1; x <= clip.$3; x++) { while (index < crossings.length && crossings[index].$1 <= x) { count++; wind += crossings[index++].$2; } if (rule == 'evenodd' ? count.isOdd : wind != 0) pixels.add((x, y)); }
  } return pixels;
}
Set<Point> fillShape(Point center, Set<Point> points, Rect clip) {
  final extents = <int, int>{}; for (final (dx, dy) in points) { extents[dy] = max(extents[dy] ?? 0, dx.abs()); } final pixels = <Point>{};
  for (final entry in extents.entries) { final y = center.$2 + entry.key; if (y < clip.$2 || y > clip.$4) continue; for (var x = max(clip.$1, center.$1 - entry.value); x <= min(clip.$3, center.$1 + entry.value); x++) { pixels.add((x, y)); } } return pixels;
}
Set<Point> floodFill(Layer layer, Point seed, Rect clip) {
  final target = layer.colors[seed.$2][seed.$1], pixels = <Point>{seed}, pending = <Point>[seed];
  while (pending.isNotEmpty) { final (x, y) = pending.removeLast(); for (final p in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]) { if (pixels.contains(p) || p.$1 < clip.$1 || p.$1 > clip.$3 || p.$2 < clip.$2 || p.$2 > clip.$4) continue; if (layer.colors[p.$2][p.$1] == target) { pixels.add(p); pending.add(p); } } } return pixels;
}
