part of 'main.dart';

String fixedText(int value) =>
    '${value < 0 ? '-' : ''}${value.abs() ~/ 10000}.${(value.abs() % 10000).toString().padLeft(4, '0')}';
String averageText(int total, int count) =>
    fixedText(floorDiv(10000 * total, count));
String cellText(World w, int cell) => '${cell ~/ w.cols},${cell % w.cols}';
String cellsText(World w, List<int> cells) =>
    cells.map((cell) => cellText(w, cell)).join(' ');
List<String> gridLines(World w, List<String> fields, String separator) => [
  for (var row = 0; row < w.rows; row++)
    [
      for (var cell = row * w.cols; cell < (row + 1) * w.cols; cell++)
        w.stateIndex[cell] < 0 ? w.kinds[cell] : fields[w.stateIndex[cell]],
    ].join(separator),
];
List<String> valueGrid(World w, List<int> values) =>
    gridLines(w, values.map(fixedText).toList(), ' ');
List<String> policyGrid(World w, List<int> policy) =>
    gridLines(w, policy.map((a) => '^>v<'[a]).toList(), '');
List<String> qTableRows(
  World w,
  String name,
  List<List<int>> q,
  List<List<int>>? visits,
) => [
  for (var s = 0; s < w.states.length; s++)
    for (var a = 0; a < 4; a++)
      '$name,${w.states[s] ~/ w.cols},${w.states[s] % w.cols},${actionLetters[a]},${fixedText(q[s][a])},${visits == null ? '-' : visits[s][a]}',
];
List<String> joinParts(List<List<String>> parts) {
  final lines = <String>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) lines.add('');
    lines.addAll(parts[i]);
  }
  return lines;
}

void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
