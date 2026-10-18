import 'dart:io';

void main() {
    final out = StringBuffer();
    var a = 1, b = 1, sum = 0;
    for (var i = 0; i < 30; i++) {
        if (i > 0)
            out.write(' ');
        out.write(a);
        sum += a;
        (a, b) = (b, a + b);
    }
    out.writeln('\nsum: $sum');
    stdout.write(out);
}
