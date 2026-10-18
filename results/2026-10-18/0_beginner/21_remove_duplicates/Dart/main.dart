import 'dart:io';

void main() {
    final out = StringBuffer();
    const values = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9];
    final unique = <int>[];
    for (final v in values) {
        if (!unique.contains(v))
            unique.add(v);
    }
    out.writeln(unique.join(' '));
    out.writeln('removed: ${values.length-unique.length}');
    stdout.write(out);
}
