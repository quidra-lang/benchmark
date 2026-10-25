import 'dart:io';

String money(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
int percent(int part, int whole) => (200 * part + whole) ~/ (2 * whole);
String tableRow(String label, Iterable<int> values, int width) => label.padRight(10) + values.map((value) => value.toString().padLeft(width)).join();
void writeReport(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}
