import 'dart:io';

void main() {
    final out = StringBuffer();
    var state = 12345;
    final counts = List.filled(13, 0);
    for (var i = 0; i < 1000; i++) {
        state = (state * 48271) % 2147483647;
        final a = state % 6 + 1;
        state = (state * 48271) % 2147483647;
        final b = state % 6 + 1;
        counts[a + b]++;
    }
    var best = 2;
    for (var sum = 2; sum <= 12; sum++) {
        out.writeln('$sum: ${counts[sum]}');
        if (counts[sum] > counts[best])
            best = sum;
    }
    out.writeln('most frequent: $best');
    stdout.write(out);
}
