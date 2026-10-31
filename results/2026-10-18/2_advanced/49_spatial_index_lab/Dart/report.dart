part of 'main.dart';

String fraction(int numerator, int denominator) {
  var a = numerator, b = denominator;
  while (b != 0) {
    final old = b;
    b = a % b;
    a = old;
  }
  return '${numerator ~/ a}/${denominator ~/ a}';
}

String ids(List<int> values) => values.isEmpty ? '-' : values.join(' ');
String boxWords(Box box) => '${box.x1} ${box.y1} ${box.x2} ${box.y2}';
String distances(List<(int, int)> values) =>
    values.isEmpty ? '-' : values.map((v) => '${v.$1}:${v.$2}').join(' ');
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}
