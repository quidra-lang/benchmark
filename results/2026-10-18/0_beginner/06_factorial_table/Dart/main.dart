import 'dart:io';

void main() {
  final output = StringBuffer();
  var factorial = 1;
  for (var n = 0; n <= 12; n++) {
    if (n > 0) factorial *= n;
    output.writeln('$n! = $factorial');
  }
  stdout.write(output);
}
