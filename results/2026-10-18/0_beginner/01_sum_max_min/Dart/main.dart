import 'dart:io';

void main() {
  const values = [17, -8, 42, 5, -23, 36, 5, 0, -11, 29];
  var total = 0;
  var maximum = values.first;
  var minimum = values.first;
  for (final value in values) {
    total += value;
    if (value > maximum) maximum = value;
    if (value < minimum) minimum = value;
  }
  stdout.write('sum: $total\nmax: $maximum\nmin: $minimum\n');
}
