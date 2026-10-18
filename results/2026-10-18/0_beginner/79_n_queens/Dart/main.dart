import 'dart:io';

void main() {
    final out = StringBuffer();
    List<int> ? first;
    for (var n = 4; n <= 8; n++) {
        final queens = List.filled(n, 0);
        var count = 0;
        void solve(int row) {
            if (row == n) {
                count++;
                if (n == 8 && first == null)
                    first = queens.toList();
                return;
            }
            for (var col = 0; col < n; col++) {
                var safe = true;
                for (var r = 0; r < row; r++) {
                    if (queens[r] == col || (queens[r] - col).abs() == row - r) {
                        safe = false;
                        break;
                    }
                }
                if (safe) {
                    queens[row] = col;
                    solve(row + 1);
                }
            }
        }
        solve(0);
        out.writeln('N=$n: $count solutions');
    }
    for (var r = 0; r < 8; r++)
        out.writeln([for (var c = 0; c < 8; c++) first![r] == c ? 'Q' : '.'].join());
    stdout.write(out);
}
