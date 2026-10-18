import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final a in [[3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2], [-4, 7, -1, 3, -8, 10, -2, 5, -6,
        -2, 9, -12, 4, -1], [-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2]]) {
        var current = a[0], best = current, start = 0, bi = 0, bj = 0;
        for (var i = 1; i < a.length; i++) {
            if (current + a[i] < a[i]) {
                current = a[i];
                start = i;
            } else {
                current += a[i];
            }
            if (current > best) {
                best = current;
                bi = start;
                bj = i;
            }
        }
        out.writeln('max sum $best at [$bi, $bj]');
    }
    stdout.write(out);
}
