part of 'main.dart';

class Canvas {
  final int width, height;
  final List<List<String>> rows;
  Canvas(this.width, this.height)
    : rows = List.generate(height, (_) => List.filled(width, ' '));
  (int, int) position(int x, int y, [int d = 1]) => (
    (2 * x * (width - 1) + 1000 * d) ~/ (2000 * d),
    height - 1 - (2 * y * (height - 1) + 1000 * d) ~/ (2000 * d),
  );
  void mark(int x, int y, int d, String ch) {
    final (column, row) = position(x, y, d);
    rows[row][column] = ch;
  }

  void line(Point a, Point b, String ch) {
    var (x, y) = position(a.x, a.y);
    final (endX, endY) = position(b.x, b.y);
    final dx = (endX - x).abs(),
        dy = -(endY - y).abs(),
        sx = x < endX ? 1 : -1,
        sy = y < endY ? 1 : -1;
    var error = dx + dy;
    while (true) {
      rows[y][x] = ch;
      if (x == endX && y == endY) {
        return;
      }
      final twice = 2 * error;
      if (twice >= dy) {
        error += dy;
        x += sx;
      }
      if (twice <= dx) {
        error += dx;
        y += sy;
      }
    }
  }

  void drawVoronoi(List<Point> points) {
    final horizontal = width - 1,
        vertical = height - 1,
        owners = List.generate(height, (_) => List.filled(width, 0));
    for (var r = 0; r < height; r++) {
      for (var c = 0; c < width; c++) {
        var best = -1;
        for (var s = 1; s < points.length; s++) {
          final p = points[s],
              dx = (c * 1000 - p.x * horizontal) * vertical,
              dy = ((vertical - r) * 1000 - p.y * vertical) * horizontal,
              distance = dx * dx + dy * dy;
          if (best < 0 || distance < best) {
            best = distance;
            owners[r][c] = s;
          }
        }
      }
    }
    for (var r = 0; r < height; r++) {
      for (var c = 0; c < width; c++) {
        final owner = owners[r][c];
        if (c < horizontal && owner != owners[r][c + 1] ||
            r < vertical && owner != owners[r + 1][c]) {
          rows[r][c] = '#';
        }
      }
    }
    for (final p in points.skip(1)) {
      mark(p.x, p.y, 1, 'o');
    }
  }

  List<String> framed() {
    final border = '+${'-' * width}+';
    return [border, for (final row in rows) '|${row.join()}|', border];
  }
}
