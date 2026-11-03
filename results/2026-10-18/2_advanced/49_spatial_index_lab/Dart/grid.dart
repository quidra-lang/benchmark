part of 'main.dart';

class Cell {
  final int column, row;
  final Box box;
  final points = <SpatialObject>[];
  Cell(this.column, this.row, int size)
    : box = Box(
        column * size,
        row * size,
        column * size + size - 1,
        row * size + size - 1,
      );
}

class Grid {
  final int world, cellSize, side;
  final cells = <Cell>[];
  Grid(this.world, this.cellSize, List<SpatialObject> points)
    : side = world ~/ cellSize {
    for (var row = 0; row < side; row++) {
      for (var column = 0; column < side; column++) {
        cells.add(Cell(column, row, cellSize));
      }
    }
    for (final p in points) {
      insert(p);
    }
  }
  (int, int) position(SpatialObject point) =>
      (point.box.x1 ~/ cellSize, point.box.y1 ~/ cellSize);
  Cell cell(SpatialObject point) {
    final (column, row) = position(point);
    return cells[row * side + column];
  }

  void insert(SpatialObject point) {
    final target = cell(point);
    target.points.add(point);
    target.points.sort((a, b) => a.id.compareTo(b.id));
  }

  void delete(SpatialObject point) {
    cell(point).points.removeWhere((p) => p.id == point.id);
  }
}
