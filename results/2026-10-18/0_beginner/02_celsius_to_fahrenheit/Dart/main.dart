import 'dart:io';

void main() {
    const temperatures = [-40, -15, -3, 0, 22, 37, 100];
    final output = StringBuffer();
    for (final celsius in temperatures) {
        final fahrenheit = celsius * 9 / 5 + 32;
        final tenths = (fahrenheit.abs() * 10 + 0.5).floor();
        final sign = fahrenheit < 0 ? '-' : '';
        output.writeln('$celsius C = $sign${tenths ~/ 10}.${tenths % 10} F');
    }
    stdout.write(output);
}
