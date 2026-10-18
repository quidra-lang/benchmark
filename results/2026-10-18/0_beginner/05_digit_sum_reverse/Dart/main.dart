import 'dart:io';

void main() {
  const values = [7, 98000, 4096, 50301, 2718281, 123456789];
  final output = StringBuffer();
  for (final original in values) {
    var remaining = original;
    var digits = 0;
    var sum = 0;
    var reversed = 0;
    while (remaining > 0) {
      final digit = remaining % 10;
      digits++;
      sum += digit;
      reversed = reversed * 10 + digit;
      remaining ~/= 10;
    }
    output.writeln('$original: digits=$digits sum=$sum reversed=$reversed');
  }
  stdout.write(output);
}
