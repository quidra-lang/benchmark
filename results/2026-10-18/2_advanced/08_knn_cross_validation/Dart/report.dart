import 'dart:io';

String fixed(double value, [int places = 4]) {
  final text = value.toStringAsFixed(places); return text.startsWith('-') && double.parse(text) == 0 ? text.substring(1) : text;
}
double fourDecimal(double value) => double.parse(fixed(value));
String ratio(int numerator, int denominator) => '$numerator/$denominator ${fixed(numerator / denominator)}';
String fraction(int numerator, int denominator) {
  if (denominator == 0) return '- -';
  final divisor = numerator.gcd(denominator); return '${numerator ~/ divisor}/${denominator ~/ divisor} ${fixed(numerator / denominator)}';
}
List<String> joinParts(List<List<String>> parts) {
  final lines = <String>[]; for (final part in parts) { if (lines.isNotEmpty) lines.add(''); lines.addAll(part); } return lines;
}
void writeLines(String name, List<String> lines) => File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
