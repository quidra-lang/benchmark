import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final s in [0, 59, 3725, 45296, 86400, 312047]) {
        String two(int n) => n.toString().padLeft(2, '0');
        out.writeln('$s seconds = ${two(s ~/ 3600)}:${two((s ~/ 60) % 60)}:${two(s % 60)}');
    }
    stdout.write(out);
}
