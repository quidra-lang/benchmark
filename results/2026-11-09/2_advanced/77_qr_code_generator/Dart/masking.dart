part of 'main.dart';

bool maskCondition(int mask, int x, int y) => switch (mask) {
  0 => (x + y) % 2 == 0,
  1 => y % 2 == 0,
  2 => x % 3 == 0,
  3 => (x + y) % 3 == 0,
  4 => (y ~/ 2 + x ~/ 3) % 2 == 0,
  5 => x * y % 2 + x * y % 3 == 0,
  6 => (x * y % 2 + x * y % 3) % 2 == 0,
  _ => ((x + y) % 2 + x * y % 3) % 2 == 0,
};
List<List<int>> applyMask(List<List<int>> a, List<List<int>> areas, int mask) {
  final out = cloneGrid(a);
  for (var y = 0; y < out.length; y++) {
    for (var x = 0; x < out.length; x++) {
      if (areas[y][x] == 0 && maskCondition(mask, x, y)) out[y][x] ^= 1;
    }
  }
  return out;
}

class Penalty {
  int n1 = 0, n2 = 0, n3 = 0, n4 = 0;
  int get total => n1 + n2 + n3 + n4;
}

Penalty penalty(List<List<int>> a) {
  final n = a.length, p = Penalty();
  var dark = 0;
  for (final row in a) {
    for (final v in row) {
      dark += v;
    }
  }
  for (var direction = 0; direction < 2; direction++) {
    for (var k = 0; k < n; k++) {
      final values = [
        for (var i = 0; i < n; i++) direction == 0 ? a[k][i] : a[i][k],
      ];
      var start = 0;
      while (start < n) {
        var end = start + 1;
        while (end < n && values[end] == values[start]) {
          end++;
        }
        if (end - start >= 5) p.n1 += end - start - 2;
        start = end;
      }
      for (var start = 0; start + 11 <= n; start++) {
        var value = 0;
        for (final bit in values.sublist(start, start + 11)) {
          value = value * 2 + bit;
        }
        if (value == 0x5d0 || value == 0x05d) p.n3 += 40;
      }
    }
  }
  for (var y = 0; y < n - 1; y++) {
    for (var x = 0; x < n - 1; x++) {
      final v = a[y][x];
      if (a[y][x + 1] == v && a[y + 1][x] == v && a[y + 1][x + 1] == v)
        p.n2 += 3;
    }
  }
  p.n4 = 10 * ((20 * dark - 10 * n * n).abs() ~/ (n * n));
  return p;
}
