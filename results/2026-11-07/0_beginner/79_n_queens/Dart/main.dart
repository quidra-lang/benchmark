void main() {
  List<int>? first;
  for (var n = 4; n <= 8; n++) {
    final queens = List.filled(n, 0);
    var count = 0;
    void solve(int row) {
      if (row == n) {
        count++;
        if (n == 8 && first == null) first = queens.toList();
        return;
      }
      for (var col = 0; col < n; col++) {
        final safe = queens
            .take(row)
            .indexed
            .every(
              (queen) =>
                  queen.$2 != col && (queen.$2 - col).abs() != row - queen.$1,
            );
        if (safe) {
          queens[row] = col;
          solve(row + 1);
        }
      }
    }

    solve(0);
    print('N=$n: $count solutions');
  }
  for (var r = 0; r < 8; r++) {
    print([for (var c = 0; c < 8; c++) first![r] == c ? 'Q' : '.'].join());
  }
}
