part of 'main.dart';

String named(List<(String, Object)> items) =>
    items.map((p) => '${p.$1}=${p.$2}').join(' ');
String numberList(List<int> values) => values.isEmpty ? '-' : values.join(',');
String frequency(List<int> values) {
  final counts = <int, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  return keys.isEmpty
      ? '-'
      : keys.map((key) => '$key:${counts[key]}').join(',');
}

String heading(Job j) => 'JOB ${j.number} ${j.text}';
void saveLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void saveParagraphs(String name, List<List<String>> paragraphs) {
  final text = paragraphs.map((p) => p.join('\n')).join('\n\n');
  File('output/$name').writeAsStringSync(text.isEmpty ? '' : '$text\n');
}

List<String> queensBoard(List<int> columns) => [
  for (final c in columns) '${'.' * (c - 1)}Q${'.' * (columns.length - c)}',
];
