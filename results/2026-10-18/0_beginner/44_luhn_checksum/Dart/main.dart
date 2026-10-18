import 'dart:io';

void main() {
    final out = StringBuffer();
    for (final number in ['688126340316', '0128469655154', '92181914514156', '177332430060552', '7982377590420309',
        '9884593615513906']) {
        var sum = 0;
        for (var i = 0; i < number.length; i++) {
            var v = number.codeUnitAt(i) - 48;
            if ((number.length - i) % 2 == 0) {
                v *= 2;
                if (v > 9)
                    v -= 9;
            }
            sum += v;
        }
        if (sum % 10 == 0) {
            out.writeln('$number: valid');
        } else {
            final without = sum - (number.codeUnitAt(number.length - 1) - 48);
            out.writeln('$number: invalid (expected check digit ${(10-without%10)%10})');
        }
    }
    stdout.write(out);
}
