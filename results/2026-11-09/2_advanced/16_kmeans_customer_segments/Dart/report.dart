import 'dart:io';

String realText(double value) {
  final text = value.toStringAsFixed(4);
  return text == '-0.0000' ? '0.0000' : text;
}
String reals(List<double> values) => values.map(realText).join(' ');
double fourDecimal(double value) => double.parse(realText(value));
String amount(int cents) {
  final absolute = cents.abs();
  return '${cents < 0 ? '-' : ''}${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
}
void writeLines(String name, List<String> lines) => File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
