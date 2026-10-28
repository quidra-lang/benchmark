part of 'main.dart';

class Value {
  final int number;
  final String text;
  final bool isNull, unknown;
  const Value({
    this.number = 0,
    this.text = '',
    this.isNull = false,
    this.unknown = false,
  });
}

class Column {
  final String name, kind;
  final bool nullable;
  Column(this.name, this.kind, this.nullable);
}

class Options {
  final int rows, page, limit;
  final List<int> methods;
  Options(this.rows, this.page, this.limit, this.methods);
}

const typeNames = ['INT', 'STRING', 'BOOL', 'DATE'];
int number(String s) => int.parse(s);
List<String> readLines(String path) => File(path).readAsLinesSync();
int dateNumber(String s) {
  final a = s.split('-').map(int.parse).toList();
  return DateTime.utc(a[0], a[1], a[2]).difference(DateTime.utc(1970)).inDays;
}

String dateText(int day) {
  final d = DateTime.utc(1970).add(Duration(days: day));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Value parseValue(String s, String kind) {
  if (s.isEmpty) return const Value(isNull: true);
  return switch (kind) {
    'STRING' => Value(text: s),
    'BOOL' => Value(number: s == 'true' ? 1 : 0),
    'DATE' => Value(number: dateNumber(s)),
    _ => Value(number: number(s)),
  };
}

String valueText(Value v, String kind, [bool csv = false]) {
  if (v.unknown) return '?';
  if (v.isNull) return csv ? '' : 'NULL';
  return switch (kind) {
    'STRING' => v.text,
    'BOOL' => v.number == 1 ? 'true' : 'false',
    'DATE' => dateText(v.number),
    _ => '${v.number}',
  };
}

List<Column> readSchema() => [
  for (final line in readLines('input/schema.txt'))
    parseColumn(line.split(' ')),
];
Column parseColumn(List<String> a) => Column(a[0], a[1], a[2] == 'NULLABLE');
List<List<Value>> readTable(List<Column> schema) => [
  for (final line in readLines('input/table.csv').skip(1))
    parseRow(line.split(','), schema),
];
List<Value> parseRow(List<String> a, List<Column> schema) => [
  for (var c = 0; c < schema.length; c++) parseValue(a[c], schema[c].kind),
];
Options readOptions() {
  final a = readLines('input/options.txt');
  return Options(
    number(a[0].split(' ')[1]),
    number(a[1].split(' ')[1]),
    number(a[2].split(' ')[1]),
    [for (final line in a.skip(3)) methodNames.indexOf(line.split(' ')[2])],
  );
}

List<int> damagedBytes() {
  final text = readLines('input/damaged.hex').join();
  return [
    for (var i = 0; i < text.length; i += 2)
      int.parse(text.substring(i, i + 2), radix: 16),
  ];
}

void writeLines(String name, List<String> lines) {
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}

String formatChecksum(int v) => v.toRadixString(16).padLeft(8, '0');
