import 'dart:io';

void main() {
    final output = StringBuffer();
    for (var row = 1; row <= 9; row++) {
        for (var column = 1; column <= 9; column++) {
            output.write((row * column).toString().padLeft(3, ' '));
        }
        output.writeln();
    }
    stdout.write(output);
}
