import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final original in [[3, 8, 5], [6, 6, 6], [5, 8, 5], [13, 5, 12], [2, 9, 4], [7, 4, 7], [8,
        6, 7], [4, 9, 6]]) {
        final s = original.toList()..sort();
        out.write('${original.join(' ')}: ');
        if (s[0] + s[1] <= s[2]) {
            out.writeln('not a triangle');
            continue;
        }
        final side = s[0] == s[2] ? 'equilateral' : s[0] == s[1] || s[1] == s[2] ? 'isosceles' : 'scalene';
        final lhs = s[2] * s[2], rhs = s[0] * s[0] + s[1] * s[1];
        final angle = lhs < rhs ? 'acute' : lhs == rhs ? 'right' : 'obtuse';
        out.writeln('$side $angle');
    }
    stdout.write(out);
}
