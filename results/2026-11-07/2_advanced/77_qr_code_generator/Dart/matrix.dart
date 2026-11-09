part of 'main.dart';

typedef Point = (int, int);

class Matrix {
  final List<List<int>> values, areas;
  final List<Point> order = [];
  Matrix(int n) : values = intGrid(n), areas = intGrid(n);
}

List<List<int>> intGrid(int n) => List.generate(n, (_) => List.filled(n, 0));
List<List<int>> cloneGrid(List<List<int>> a) => [
  for (final row in a) List.of(row),
];
(List<Point>, List<Point>) formatPositions(int n) {
  final first = List<Point>.filled(15, (0, 0)),
      second = List<Point>.filled(15, (0, 0));
  for (var i = 0; i <= 5; i++) {
    first[i] = (8, i);
  }
  first[6] = (8, 7);
  first[7] = (8, 8);
  first[8] = (7, 8);
  for (var i = 9; i < 15; i++) {
    first[i] = (14 - i, 8);
  }
  for (var i = 0; i < 8; i++) {
    second[i] = (n - 1 - i, 8);
  }
  for (var i = 8; i < 15; i++) {
    second[i] = (8, n - 15 + i);
  }
  return (first, second);
}

(List<Point>, List<Point>) versionPositions(int n) => (
  [for (var i = 0; i < 18; i++) (n - 11 + i % 3, i ~/ 3)],
  [for (var i = 0; i < 18; i++) (i ~/ 3, n - 11 + i % 3)],
);
int remainder(int a, int g) {
  while (a.bitLength >= g.bitLength) {
    a ^= g << (a.bitLength - g.bitLength);
  }
  return a;
}

int formatInformation(String level, int mask) {
  final indicator = {'L': 1, 'M': 0, 'Q': 3, 'H': 2}[level]!,
      q = (8 * indicator + mask) << 10;
  return (q + remainder(q, 0x537)) ^ 0x5412;
}

int versionInformation(int v) {
  final a = v << 12;
  return a + remainder(a, 0x1f25);
}

void writeInformation(List<List<int>> a, List<Point> positions, int value) {
  for (var i = 0; i < positions.length; i++) {
    final p = positions[i];
    a[p.$2][p.$1] = (value >> i) & 1;
  }
}

int readInformation(List<List<int>> a, List<Point> positions) {
  var value = 0;
  for (var i = 0; i < positions.length; i++) {
    final p = positions[i];
    value += a[p.$2][p.$1] << i;
  }
  return value;
}

Matrix makeMatrix(int v, List<int> alignment) {
  final n = 17 + 4 * v, m = Matrix(n);
  void set(int x, int y, int value, int area) {
    m.values[y][x] = value;
    m.areas[y][x] = area;
  }

  for (final c in [(3, 3), (n - 4, 3), (3, n - 4)]) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final x = c.$1 + dx, y = c.$2 + dy;
        if (x < 0 || y < 0 || x >= n || y >= n) continue;
        final d = max(dx.abs(), dy.abs());
        set(x, y, d == 0 || d == 1 || d == 3 ? 1 : 0, 1);
      }
    }
  }
  for (var i = 8; i <= n - 9; i++) {
    final value = 1 - i % 2;
    set(6, i, value, 1);
    set(i, 6, value, 1);
  }
  for (var iy = 0; iy < alignment.length; iy++) {
    for (var ix = 0; ix < alignment.length; ix++) {
      if (ix == 0 && iy == 0 ||
          ix == 0 && iy == alignment.length - 1 ||
          ix == alignment.length - 1 && iy == 0)
        continue;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          set(
            alignment[ix] + dx,
            alignment[iy] + dy,
            max(dx.abs(), dy.abs()) != 1 ? 1 : 0,
            1,
          );
        }
      }
    }
  }
  set(8, n - 8, 1, 1);
  final (f1, f2) = formatPositions(n);
  for (final points in [f1, f2]) {
    for (final p in points) {
      set(p.$1, p.$2, 0, 2);
    }
  }
  if (v >= 7) {
    final (g1, g2) = versionPositions(n);
    for (final points in [g1, g2]) {
      for (final p in points) {
        set(p.$1, p.$2, 0, 3);
      }
      writeInformation(m.values, points, versionInformation(v));
    }
  }
  var pair = 0;
  for (var r = n - 1; r >= 1; r -= 2) {
    if (r == 6) r--;
    for (var step = 0; step < n; step++) {
      final y = pair % 2 == 0 ? n - 1 - step : step;
      for (var x = r; x >= r - 1; x--) {
        if (m.areas[y][x] == 0) m.order.add((x, y));
      }
    }
    pair++;
  }
  return m;
}

List<List<int>> rotate(List<List<int>> a) {
  final n = a.length;
  return [
    for (var y = 0; y < n; y++) [for (var x = 0; x < n; x++) a[n - 1 - x][y]],
  ];
}

List<List<int>> transpose(List<List<int>> a) {
  final n = a.length;
  return [
    for (var y = 0; y < n; y++) [for (var x = 0; x < n; x++) a[x][y]],
  ];
}
