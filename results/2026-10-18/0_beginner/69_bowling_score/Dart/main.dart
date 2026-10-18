import 'dart:io';

void main() {
    final out = StringBuffer();
    const games = [[8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2], [3, 4, 5, 2, 7, 1,
        0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5], [5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6,
        1, 9, 7, 3, 5], [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10], [10, 9, 1, 10, 10, 7, 2, 0,
        0, 10, 8, 1, 10, 6, 4, 10]];
    for (var g = 0; g < games.length; g++) {
        final rolls = games[g];
        var index = 0, total = 0;
        out.write('game ${g+1}:');
        for (var frame = 0; frame < 10; frame++) {
            if (frame == 9) {
                for (final v in rolls.skip(index))
                    total += v;
            } else if (rolls[index] == 10) {
                total += 10 + rolls[index + 1] + rolls[index + 2];
                index++;
            } else {
                final pair = rolls[index] + rolls[index + 1];
                total += pair;
                if (pair == 10)
                    total += rolls[index + 2];
                index += 2;
            }
            out.write(' $total');
        }
        out.writeln();
    }
    stdout.write(out);
}
