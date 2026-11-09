part of 'main.dart';

String fractionText(int a, int b) {
  final divisor = a.abs().gcd(b);
  return '${a ~/ divisor}/${b ~/ divisor}';
}

String rootText(int value) => math.sqrt(value).toStringAsFixed(3);
String ariText(int a, int b) {
  var text = (a / b).toStringAsFixed(4);
  if (text == '-0.0000') text = '0.0000';
  return '${fractionText(a, b)} $text';
}

List<String> framed(List<String> rows, int width) {
  final border = '+${List.filled(width, '-').join()}+';
  return [border, for (final row in rows) '|$row|', border];
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}
