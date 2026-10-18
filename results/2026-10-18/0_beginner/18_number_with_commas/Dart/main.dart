import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final n in [0, 7, 999, 1000, -456789, 3141592, 9876543210]) {
        final digits = n.abs().toString();
        if (n < 0)
            out.write('-');
        for (var i = 0; i < digits.length; i++) {
            if (i > 0 && (digits.length - i) % 3 == 0)
                out.write(',');
            out.write(digits[i]);
        }
        out.writeln();
    }
    stdout.write(out);
}
