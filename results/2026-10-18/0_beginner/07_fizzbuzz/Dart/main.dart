import 'dart:io';

void main() {
  final output = StringBuffer();
  for (var number = 1; number <= 30; number++) {
    if (number % 15 == 0) {
      output.writeln('FizzBuzz');
    } else if (number % 3 == 0) {
      output.writeln('Fizz');
    } else if (number % 5 == 0) {
      output.writeln('Buzz');
    } else {
      output.writeln(number);
    }
  }
  stdout.write(output);
}
