import 'dart:io';

void main() {
    final out = StringBuffer();
    const text = 'Peter Piper picked a peck of pickled peppers!';
    final counts = List.filled(26, 0);
    for (final c in text.toLowerCase().codeUnits) {
        if (c >= 97 && c <= 122)
            counts[c - 97]++;
    }
    for (var i = 0; i < 26; i++) {
        if (counts[i] > 0)
            out.writeln('${String.fromCharCode(97+i)}: ${counts[i]}');
    }
    stdout.write(out);
}
