import 'dart:io';

String fixedWidthLine(
  String label,
  Iterable<String> cells,
  int labelWidth,
  int cellWidth,
) => label.padRight(labelWidth) + cells.map((cell) => cell.padLeft(cellWidth)).join();

int roundedPercent(int part, int whole) => (200 * part + whole) ~/ (2 * whole);
void writeFiles(String directory, Map<String, List<String>> files) {
  Directory(directory).createSync(recursive: true);
  for (final entry in files.entries) {
    File('$directory/${entry.key}').writeAsStringSync('${entry.value.join('\n')}\n');
  }
}
