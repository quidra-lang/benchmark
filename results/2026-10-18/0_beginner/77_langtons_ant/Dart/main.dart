import 'dart:io';

void main() {
    final out = StringBuffer();
    final black = List.generate(11, (_) => List.filled(11, false));
    const directions = [(-1, 0), (0, 1), (1, 0), (0, -1)];
    var r = 5, c = 5, d = 0;
    for (var i = 0; i < 300; i++) {
        d = (d + (black[r][c] ? 3 : 1)) % 4;
        black[r][c] = !black[r][c];
        r = (r + directions[d].$1) % 11;
        c = (c + directions[d].$2) % 11;
    }
    var count = 0;
    for (var i = 0; i < 11; i++) {
        for (var j = 0; j < 11; j++) {
            if (black[i][j])
                count++;
            out.write(i == r && j == c ? 'A' : black[i][j] ? '#' : '.');
        }
        out.writeln();
    }
    out.writeln('black: $count');
    stdout.write(out);
}
