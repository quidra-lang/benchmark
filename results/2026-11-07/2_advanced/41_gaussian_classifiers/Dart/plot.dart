part of 'main.dart';

String real(double value) {
  final text = value.toStringAsFixed(4);
  return text == '-0.0000' ? '0.0000' : text;
}

String reals(Iterable<double> values) => values.map(real).join(' ');
String ints(Iterable<int> values) => values.join(' ');
String fractionText(Fraction v) =>
    v.$2 == 0 ? '-' : '${v.$1}/${v.$2} ${real(v.$1 / v.$2)}';
String ratio(int a, int b) => fractionText(fraction(a, b));
List<String> frame(List<List<String>> grid) {
  final border = '+${'-' * grid.first.length}+';
  return [border, for (final row in grid) '|${row.join()}|', border];
}

int cell(double v, double lo, double hi, int size) =>
    ((v - lo) / (hi - lo) * (size - 1) + 0.5).floor();
List<String> joinSections(List<List<String>> sections) => [
  for (var i = 0; i < sections.length; i++) ...[if (i > 0) '', ...sections[i]],
];
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}
