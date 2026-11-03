part of 'main.dart';

typedef Cell = (int, int);

class Canvas {
  final int mainLength, secondaryLength, rows, columns;
  final String direction;
  final List<List<int>> lineSets;
  final List<List<String>> arrows, boxes;
  final List<List<bool>> highlighted;
  Canvas(int m, int n, this.direction)
    : mainLength = m,
      secondaryLength = n,
      rows = direction == 'LR' || direction == 'RL' ? n : m,
      columns = direction == 'LR' || direction == 'RL' ? m : n,
      lineSets = List.generate(
        direction == 'LR' || direction == 'RL' ? n : m,
        (_) => List.filled(direction == 'LR' || direction == 'RL' ? m : n, 0),
      ),
      arrows = List.generate(
        direction == 'LR' || direction == 'RL' ? n : m,
        (_) => List.filled(direction == 'LR' || direction == 'RL' ? m : n, ''),
      ),
      boxes = List.generate(
        direction == 'LR' || direction == 'RL' ? n : m,
        (_) => List.filled(direction == 'LR' || direction == 'RL' ? m : n, ''),
      ),
      highlighted = List.generate(
        direction == 'LR' || direction == 'RL' ? n : m,
        (_) =>
            List.filled(direction == 'LR' || direction == 'RL' ? m : n, false),
      );
  Cell map(int main, int secondary) {
    if (direction == 'BT' || direction == 'RL') main = mainLength - 1 - main;
    return direction == 'TB' || direction == 'BT'
        ? (main, secondary)
        : (secondary, main);
  }

  void line(int main, int secondary, int kind) {
    final p = map(main, secondary);
    lineSets[p.$1][p.$2] |= kind;
  }

  void mainLine(int main, int secondary) =>
      line(main, secondary, direction == 'LR' || direction == 'RL' ? 2 : 1);
  void secondaryLine(int main, int secondary) =>
      line(main, secondary, direction == 'LR' || direction == 'RL' ? 1 : 2);
  void segment(int g0, int gap, int upper, int lower, int offset) {
    if (upper == lower) {
      for (var j = 0; j < gap; j++) {
        mainLine(g0 + j, upper);
      }
      return;
    }
    for (var j = 0; j < offset; j++) {
      mainLine(g0 + j, upper);
    }
    line(g0 + offset, upper, 4);
    line(g0 + offset, lower, 4);
    for (var x = min(upper, lower) + 1; x < max(upper, lower); x++) {
      secondaryLine(g0 + offset, x);
    }
    for (var j = offset + 1; j < gap; j++) {
      mainLine(g0 + j, lower);
    }
  }

  void highlight(Cell a, Cell b) {
    final dr = (b.$1 - a.$1).sign, dc = (b.$2 - a.$2).sign;
    var row = a.$1, column = a.$2;
    while (true) {
      highlighted[row][column] = true;
      if ((row, column) == b) break;
      row += dr;
      column += dc;
    }
  }

  int crossingCells() {
    var sum = 0;
    for (final row in lineSets) {
      for (final mask in row) {
        if ((mask & 3) == 3) sum++;
      }
    }
    return sum;
  }

  String character(int r, int c) {
    if (boxes[r][c].isNotEmpty) return boxes[r][c];
    if (arrows[r][c].isNotEmpty) return arrows[r][c];
    if (highlighted[r][c]) return '#';
    return switch (lineSets[r][c]) {
      0 => ' ',
      1 => '|',
      2 => '-',
      _ => '+',
    };
  }

  List<String> drawing(String name) {
    final ruler = '    ${[for (var c = 0; c < columns; c++) c % 10].join()}',
        out = ['graph $name ${columns}x$rows', ruler];
    for (var r = 0; r < rows; r++) {
      out.add(
        '${r.toString().padLeft(3, ' ')} ${[for (var c = 0; c < columns; c++) character(r, c)].join()}'
            .trimRight(),
      );
    }
    return out;
  }
}
