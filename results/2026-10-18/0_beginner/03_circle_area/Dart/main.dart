import 'dart:io';

String fixedThree(double value) {
    final thousandths = (value * 1000 + 0.5).floor();
    final fraction = (thousandths % 1000).toString().padLeft(3, '0');
    return '${thousandths ~/ 1000}.$fraction';
}

void main() {
    const radii = [3, 7, 12, 25, 41];
    const pi = 3.141592653589793;
    final output = StringBuffer();
    for (final radius in radii) {
        final r = radius.toDouble();
        final area = (pi * r) * r;
        final circumference = (2.0 * pi) * r;
        output.writeln('r=$radius area=${fixedThree(area)} ' 'circumference=${fixedThree(circumference)}');
    }
    stdout.write(output);
}
