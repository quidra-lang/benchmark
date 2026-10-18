import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final s in ['AAABBBCCCD', 'WWWWWWWWWWWWBWWWWWWWWWWWWBBB', 'ALGORITHM', 'MISSISSIPPI', 'XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ']) {
        final encoded = StringBuffer();
        var i = 0;
        while (i < s.length) {
            var end = i + 1;
            while (end < s.length && s[end] == s[i])
                end++;
            encoded.write('${end-i}${s[i]}');
            i = end;
        }
        final e = encoded.toString(), decoded = StringBuffer();
        i = 0;
        while (i < e.length) {
            var count = 0;
            while (i < e.length && e.codeUnitAt(i) >= 48 && e.codeUnitAt(i) <= 57) {
                count = count * 10 + e.codeUnitAt(i) - 48;
                i++;
            }
            decoded.write(e[i] * count);
            i++;
        }
        out.writeln('$s -> $e -> $decoded');
    }
    stdout.write(out);
}
