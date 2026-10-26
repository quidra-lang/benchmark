import 'dart:io';

class Observation {
  final String ident;
  final String label;
  final List<double> values;
  Observation(this.ident, this.label, this.values);
}
List<String> readLines(String path) => File(path).readAsLinesSync();
(List<String>, List<Observation>) readObservations() {
  final lines = readLines('input/data.csv');
  final names = lines[0].split(',').sublist(2);
  final observations = <Observation>[];
  for (final line in lines.skip(1)) {
    final fields = line.split(',');
    observations.add(Observation(fields[0], fields[1], fields.skip(2).map(double.parse).toList()));
  }
  return (names, observations);
}
Map<String, List<String>> readSettings() {
  final entries = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final fields = line.split(' ');
    entries[fields[0]] = fields.sublist(1);
  }
  return entries;
}
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
