import 'dart:io';

void main() {
    const years = [1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100];
    final output = StringBuffer();
    for (final year in years) {
        final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
        final result = leap ? 'leap year' : 'common year';
        output.writeln('$year: $result');
    }
    stdout.write(output);
}
