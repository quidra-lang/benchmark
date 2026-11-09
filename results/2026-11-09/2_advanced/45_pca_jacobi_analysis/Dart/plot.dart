part of 'main.dart';

typedef Cell = (int, int);
List<List<String>> newGrid(int rows, int columns) =>
    List.generate(rows, (_) => List.filled(columns, ' '));
List<String> framed(List<List<String>> grid) {
  final border = '+${'-' * grid.first.length}+';
  return [border, for (final row in grid) '|${row.join()}|', border];
}

int gridIndex(double fraction, int size) =>
    math.min((fraction * size).floor(), size - 1);
int roundedPosition(double fraction, double size) =>
    (fraction * size + 0.5).floor();
Cell biplotCell(
  double x,
  double y,
  double xLimit,
  double yLimit,
  int w,
  int h,
) => (
  gridIndex((yLimit - y) / (2 * yLimit), h),
  gridIndex((x + xLimit) / (2 * xLimit), w),
);
Cell circleCell(double first, double second, int radius) => (
  radius ~/ 2 + 1 - roundedPosition(second, radius / 2),
  radius + 1 + roundedPosition(first, radius.toDouble()),
);
Cell diagnosticCell(
  double t2,
  double spe,
  double t2Max,
  double speMax,
  int w,
  int h,
) => (h - 1 - gridIndex(spe / speMax, h), gridIndex(t2 / t2Max, w));
List<Cell> shaftCells(Cell origin, Cell tip) {
  final dr = tip.$1 - origin.$1,
      dc = tip.$2 - origin.$2,
      steps = math.max(dr.abs(), dc.abs());
  return [
    for (var s = 1; s < steps; s++)
      (
        origin.$1 + dr.sign * ((2 * s * dr.abs() + steps) ~/ (2 * steps)),
        origin.$2 + dc.sign * ((2 * s * dc.abs() + steps) ~/ (2 * steps)),
      ),
  ];
}

String shaftCharacter(Cell origin, Cell tip) {
  final dr = tip.$1 - origin.$1, dc = tip.$2 - origin.$2;
  if (2 * dr.abs() <= dc.abs()) return '-';
  if (2 * dc.abs() <= dr.abs()) return '|';
  if (dc * dr < 0) return '/';
  return '\\';
}

String screeLine(int length, int kaiser, int broken, int width) =>
    '|${[for (var p = 1; p <= width; p++) p == broken
          ? 'o'
          : p == kaiser
          ? ':'
          : p <= length
          ? '#'
          : ' '].join()}|';
