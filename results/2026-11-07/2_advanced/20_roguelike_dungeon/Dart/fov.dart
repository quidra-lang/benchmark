import 'dart:math' as math;
import 'dungeon_gen.dart';
import 'entities.dart';

const directionNames = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
const directions = [Point(0, -1), Point(1, -1), Point(1, 0), Point(1, 1), Point(0, 1), Point(-1, 1), Point(-1, 0), Point(-1, -1)];
bool passable(Level level, int x, int y) => ['.', '#', '+', '<', '>'].contains(level.terrain[y][x]);
bool canMove(Level level, int x, int y, int dx, int dy) => passable(level, x + dx, y + dy) &&
    (dx == 0 || dy == 0 || (level.terrain[y][x] != '+' && level.terrain[y + dy][x + dx] != '+'));

List<Point> line(int x0, int y0, int x1, int y1) {
  final dx = (x1 - x0).abs(), dy = (y1 - y0).abs();
  final sx = x1 > x0 ? 1 : -1, sy = y1 > y0 ? 1 : -1;
  var error = dx - dy, x = x0, y = y0;
  final cells = <Point>[];
  while (x != x1 || y != y1) {
    final e2 = 2 * error;
    if (e2 > -dy) {
      error -= dy;
      x += sx;
    }
    if (e2 < dx) {
      error += dx;
      y += sy;
    }
    cells.add(Point(x, y));
  }
  return cells;
}

List<List<bool>> fieldOfView(Level level, int px, int py, int radius) {
  final visible = List.generate(level.height, (_) => List.filled(level.width, false));
  for (var y = math.max(0, py - radius); y < math.min(level.height, py + radius + 1); y++) {
    for (var x = math.max(0, px - radius); x < math.min(level.width, px + radius + 1); x++) {
      if ((x - px) * (x - px) + (y - py) * (y - py) > radius * radius) {
        continue;
      }
      final cells = line(px, py, x, y);
      visible[y][x] = cells.take(math.max(0, cells.length - 1)).every((point) => passable(level, point.x, point.y));
    }
  }
  return visible;
}

List<List<int>> distances(Level level, int px, int py) {
  final result = List.generate(level.height, (_) => List.filled(level.width, -1));
  result[py][px] = 0;
  final queue = [Point(px, py)];
  for (var head = 0; head < queue.length; head++) {
    final point = queue[head];
    for (final step in directions) {
      final nx = point.x + step.x, ny = point.y + step.y;
      if (canMove(level, point.x, point.y, step.x, step.y) && result[ny][nx] < 0) {
        result[ny][nx] = result[point.y][point.x] + 1;
        queue.add(Point(nx, ny));
      }
    }
  }
  return result;
}
