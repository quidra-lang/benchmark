import 'dart:math';

void main() {
  const values = [17, -8, 42, 5, -23, 36, 5, 0, -11, 29];
  final sum = values.reduce((a, b) => a + b);
  print('sum: $sum');
  print('max: ${values.reduce(max)}');
  print('min: ${values.reduce(min)}');
}
