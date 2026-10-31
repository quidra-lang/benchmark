class Grid {
  final int width;
  final int height;
  final List<int> cells;
  Grid(List<String> rows) : width = rows.first.length, height = rows.length, cells = rows.join().codeUnits;
  int cell(int row, int column) => row * width + column;
  String location(int cell) => '${cell ~/ width + 1},${cell % width + 1}';
  bool isOpen(int row, int column) => row >= 0 && row < height && column >= 0 && column < width && cells[cell(row, column)] != 35;
  List<int> get whiteCells => [for (var i = 0; i < cells.length; i++) if (cells[i] != 35) i];

  int asymmetricCell(String symmetry) {
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final otherRow = symmetry == 'rot180' ? height - 1 - row : row;
        if (isOpen(row, column) != isOpen(otherRow, width - 1 - column)) {
          return cell(row, column);
        }
      }
    }
    return -1;
  }

  int get componentCount {
    final seen = List.filled(cells.length, false);
    var count = 0;
    for (final start in whiteCells) {
      if (seen[start]) {
        continue;
      }
      count++;
      seen[start] = true;
      final stack = [start];
      while (stack.isNotEmpty) {
        final position = stack.removeLast();
        final row = position ~/ width, column = position % width;
        for (final (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
          final r = row + dr, c = column + dc;
          if (isOpen(r, c)) {
            final neighbor = cell(r, c);
            if (!seen[neighbor]) {
              seen[neighbor] = true;
              stack.add(neighbor);
            }
          }
        }
      }
    }
    return count;
  }
}
