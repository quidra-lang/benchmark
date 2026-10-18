import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final n in [84, 9973, 15625, 1001, 123456, 48000, 999958, 999999]) {
        var remaining = n;
        final factors = <String>[];
        for (var d = 2; d * d <= remaining; d++) {
            var e = 0;
            while (remaining % d == 0) {
                remaining ~/= d;
                e++;
            }
            if (e > 0)
                factors.add(e == 1 ? '$d' : '$d^$e');
        }
        if (remaining > 1)
            factors.add('$remaining');
        out.writeln('$n = ${factors.join(' * ')}');
    }
    stdout.write(out);
}
