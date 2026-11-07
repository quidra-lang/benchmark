part of 'main.dart';

List<String> readLines(String path) => File(path).readAsLinesSync();
List<int> readECG() => readLines(
  'input/ecg.csv',
).skip(1).map((line) => int.parse(line.split(',')[1])).toList();

class Annotation {
  final int sample;
  final String label;
  Beat? beat;
  Annotation(this.sample, this.label);
}

List<Annotation> readAnnotations() {
  final annotations = <Annotation>[];
  for (final line in readLines('input/annotations.csv').skip(1)) {
    final fields = line.split(',');
    annotations.add(Annotation(int.parse(fields[0]), fields[1]));
  }
  return annotations;
}

Map<String, int> readParams() {
  final params = <String, int>{};
  for (final line in readLines('input/params.txt')) {
    final fields = line.split(' ');
    params[fields[0]] = int.parse(fields[1]);
  }
  return params;
}

void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
