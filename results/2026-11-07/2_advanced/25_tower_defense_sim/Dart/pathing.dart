import 'grid_map.dart';

const directions = [(0, -1), (1, 0), (0, 1), (-1, 0)];
Point neighbor(Point cell, int direction) => (cell.$1 + directions[direction].$1, cell.$2 + directions[direction].$2);
class DistanceField {
  final GridMap grid;
  final List<int> distances;
  Point get exit => grid.exit;
  DistanceField(this.grid, Set<Point> towers) : distances = List.filled(grid.width * grid.height, -1) {
    distances[grid.exit.$2 * grid.width + grid.exit.$1] = 0;
    final queue = <Point>[grid.exit];
    for (var head = 0; head < queue.length; head++) {
      final cell = queue[head];
      for (var direction = 0; direction < 4; direction++) {
        final following = neighbor(cell, direction);
        if (grid.inside(following) && !grid.isRock(following) && !towers.contains(following) && at(following) < 0) {
          distances[following.$2 * grid.width + following.$1] = at(cell) + 1;
          queue.add(following);
        }
      }
    }
  }
  int at(Point cell) => distances[cell.$2 * grid.width + cell.$1];
  int direction(Point cell) {
    var best = -1;
    var bestDistance = 0;
    for (var direction = 0; direction < 4; direction++) {
      final following = neighbor(cell, direction);
      if (!grid.inside(following)) continue;
      final distance = at(following);
      if (distance >= 0 && (best < 0 || distance < bestDistance)) {
        best = direction;
        bestDistance = distance;
      }
    }
    return best;
  }
  Point nextCell(Point cell) => neighbor(cell, direction(cell));
  List<Point> path(Point start) {
    final cells = <Point>[start];
    while (cells.last != exit) { cells.add(nextCell(cells.last)); }
    return cells;
  }
}
