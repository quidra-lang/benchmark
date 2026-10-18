import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final n in [0, 10, 255, 1000, 43981, 65535]) {
        out.writeln('$n: bin=${n.toRadixString(2)} oct=${n.toRadixString(8)} hex=${n.toRadixString(16).toUpperCase()}');
    }
    stdout.write(out);
}
