import 'dart:io';

void main() {
    final out = StringBuffer();
    var previous = <int>[];
    for (var n = 0; n < 12; n++) {
        final row = List.filled(n + 1, 1);
        for (var k = 1; k < n; k++)
            row[k] = previous[k - 1] + previous[k];
        out.writeln(row.join(' '));
        previous = row;
    }
    stdout.write(out);
}
