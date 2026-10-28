part of 'main.dart';

String real(double value) {
  if (value.isNaN) return '-';
  final s = value.toStringAsFixed(4);
  return s == '-0.0000' ? '0.0000' : s;
}

String optional(int value) => value == 0 ? '-' : '$value';
String ints(Iterable<int> values) => values.join(' ');
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

List<String> separateSections(List<List<String>> sections) => [
  for (var i = 0; i < sections.length; i++) ...[if (i > 0) '', ...sections[i]],
];
