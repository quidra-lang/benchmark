part of 'main.dart';

String numberDigits(double value, int digits) {
  final text = value.toStringAsFixed(digits);
  return text.startsWith('-') && double.parse(text) == 0
      ? text.substring(1)
      : text;
}

String number(double value) => numberDigits(value, 4);
String optional(double value) => value.isNaN ? '-' : number(value);
int rounded4(double value) => (value * 10000).round();
String integerList(List<int> values) => values.join(' ');
String numberList(List<double> values) => values.map(number).join(' ');
List<String> framed(List<List<String>> rows) {
  final border = '+${'-' * rows.first.length}+';
  return [border, for (final row in rows) '|${row.join()}|', border];
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}
