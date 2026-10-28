part of 'main.dart';

typedef Image = List<List<int>>;
typedef Point = (int, int);

class Params {
  final Map<String, List<int>> values;
  Params(this.values);
  int integer(String key) => values[key]![0];
  List<int> operator [](String key) => values[key]!;
}

List<String> readLines(String path) => File(path).readAsLinesSync();
(Image, List<Point>, Params) readInputs() {
  final image = [
        for (final line in readLines('input/image.pgm').skip(3))
          line.split(' ').map(int.parse).toList(),
      ],
      trig = List<Point>.filled(180, (0, 0));
  for (final line in readLines('input/trig.txt')) {
    final v = line.split(' ').map(int.parse).toList();
    trig[v[0]] = (v[1], v[2]);
  }
  final params = <String, List<int>>{};
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    params[f.first] = f.skip(1).map(int.parse).toList();
  }
  return (image, trig, Params(params));
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

void writePGM(String name, Image image) {
  writeLines(name, [
    'P2',
    '${image.first.length} ${image.length}',
    '255',
    for (final row in image) row.join(' '),
  ]);
}
