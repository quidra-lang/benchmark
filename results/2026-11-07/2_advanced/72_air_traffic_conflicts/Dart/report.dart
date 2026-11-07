part of 'main.dart';

String format(double x, int digits) {
  final s = x.toStringAsFixed(digits);
  return s.startsWith('-') && RegExp(r'^0(?:\.0+)?$').hasMatch(s.substring(1))
      ? s.substring(1)
      : s;
}

String f(double x) => format(x, 3);
String signed(int x) => x > 0 ? '+$x' : '$x';
void chart(StringBuffer s, List<List<String>> grid) {
  final border = '+${'-' * grid[0].length}+';
  s.writeln(border);
  for (final row in grid) {
    s.writeln('|${row.join()}|');
  }
  s.writeln(border);
}

void write(String path, StringBuffer s) =>
    File(path).writeAsStringSync(s.toString());
