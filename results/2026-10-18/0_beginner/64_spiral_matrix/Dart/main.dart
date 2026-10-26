void main() {
  final matrix = List.generate(5, (_) => List.filled(6, 0));
  const directions = [(0, 1), (1, 0), (0, -1), (-1, 0)];
  var r = 0, c = 0, d = 0;
  for (var value = 1; value <= 30; value++) {
    matrix[r][c] = value;
    if (value == 30) break;
    var nr = r + directions[d].$1, nc = c + directions[d].$2;
    if (nr < 0 || nr >= 5 || nc < 0 || nc >= 6 || matrix[nr][nc] != 0) {
      d = (d + 1) % 4;
      nr = r + directions[d].$1;
      nc = c + directions[d].$2;
    }
    r = nr;
    c = nc;
  }
  for (final row in matrix) {
    print(row.map((v) => v.toString().padLeft(3)).join());
  }
}
