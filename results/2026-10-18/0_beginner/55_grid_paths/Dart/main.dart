import 'dart:io';

void main() {
    final out = StringBuffer();
    const grid = ['.......', '..#....', '....#..', '.#.....', '...#.#.', '.......'];
    for (var mode = 0; mode < 2; mode++) {
        final dp = List.generate(6, (_) => List.filled(7, 0));
        for (var r = 0; r < 6; r++) {
            for (var c = 0; c < 7; c++) {
                if (mode == 1 && grid[r][c] == '#')
                    continue;
                if (r == 0 && c == 0) {
                    dp[r][c] = 1;
                    continue;
                }
                if (r > 0)
                    dp[r][c] += dp[r - 1][c];
                if (c > 0)
                    dp[r][c] += dp[r][c - 1];
            }
        }
        out.writeln('${mode==0?'without':'with'} obstacles: ${dp[5][6]}');
    }
    stdout.write(out);
}
