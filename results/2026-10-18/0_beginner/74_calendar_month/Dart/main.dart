import 'dart:io';

void main() {
    final out = StringBuffer();
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
        'October', 'November', 'December'], lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    bool leap(int y) => y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    var k = 0;
    for (final p in [(2024, 2), (2026, 8), (2026, 11)]) {
        final year = p.$1, month = p.$2;
        var days = 0;
        for (var y = 1; y < year; y++)
            days += leap(y) ? 366 : 365;
        for (var m = 1; m < month; m++)
            days += m == 2 && leap(year) ? 29 : lengths[m - 1];
        final offset = (days + 1) % 7, last = month == 2 && leap(year) ? 29 : lengths[month - 1];
        if (k++ > 0)
            out.writeln();
        out.writeln('${names[month-1]} $year\nSu Mo Tu We Th Fr Sa');
        out.write('   ' * offset);
        for (var day = 1; day <= last; day++) {
            out.write(day.toString().padLeft(2));
            if ((offset + day - 1) % 7 == 6 || day == last)
                out.writeln();
            else out.write(' ');
        }
    }
    stdout.write(out);
}
