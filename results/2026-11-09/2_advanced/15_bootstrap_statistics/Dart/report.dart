import 'dart:io';
import 'dart:math' as math;
import 'tests.dart';

String realText(double value) {
  final text = value.toStringAsFixed(4);
  return text == '-0.0000' ? '0.0000' : text;
}

String pValue(int numerator, int denominator) {
  final (first, second) = reducedFraction(numerator, denominator);
  return '$first/$second ${realText(first / second)}';
}

String numberList(List<int> numbers) {
  if (numbers.isEmpty) return 'none';
  return (numbers.toList()..sort()).join(' ');
}

int binNumber(double value, double low, double high, int bins) => math.min((bins * (value - low) / (high - low)).floor(), bins - 1) + 1;
String bar(int count, int top) => List.filled((40 * count + top - 1) ~/ top, '#').join();

void writeLines(String name, List<String> lines) {
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}
