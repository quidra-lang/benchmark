import 'dart:io';

String fixed(double value, [int places = 6]) {
  final text = value.toStringAsFixed(places);
  return text.startsWith('-') && double.parse(text) == 0 ? text.substring(1) : text;
}
int scaled(double value, [int places = 6]) {
  var factor = 1;
  for (var index = 0; index < places; index++) {
    factor *= 10;
  }
  return (value * factor).round();
}
String fraction(int numerator, int denominator) {
  final divisor = numerator.gcd(denominator);
  final first = numerator ~/ divisor, second = denominator ~/ divisor;
  return '$first/$second ${fixed(first / second, 4)}';
}
void writeLines(String name, List<String> lines) => File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
