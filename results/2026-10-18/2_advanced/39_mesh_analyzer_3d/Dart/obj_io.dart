part of 'main.dart';

final integerPattern = RegExp(r'^-?[0-9]+$');
bool integerWord(String word) => integerPattern.hasMatch(word);

class Polygon {
  final int number, line;
  final String group;
  final List<int> vertices;
  Polygon(this.number, this.line, this.group, this.vertices);
}

class Source {
  final int lines;
  int ignored = 0;
  final vertices = <Vec>[(0, 0, 0)],
      polygons = <Polygon>[],
      errors = <(int, String)>[];
  Source(this.lines);
}

Source readOBJ() {
  final lines = readLines('input/model.obj'), s = Source(lines.length);
  var group = 'default';
  const ignored = {'vt', 'vn', 's', 'o', 'usemtl', 'mtllib'};
  for (var index = 0; index < lines.length; index++) {
    final text = lines[index];
    if (text.isEmpty || text.startsWith('#')) continue;
    final words = text.split(' '), keyword = words[0], args = words.sublist(1);
    switch (keyword) {
      case 'v':
        if (args.length != 3 || !args.every(integerWord)) {
          s.errors.add((index + 1, 'bad_vertex'));
        } else {
          s.vertices.add((
            int.parse(args[0]),
            int.parse(args[1]),
            int.parse(args[2]),
          ));
        }
      case 'f':
        if (args.length < 3) {
          s.errors.add((index + 1, 'short_face'));
          continue;
        }
        final resolved = <int>[];
        String? reason;
        for (final reference in args) {
          final part = reference.split('/')[0];
          if (!integerWord(part)) {
            reason = 'bad_index';
            break;
          }
          var number = int.parse(part);
          if (number == 0) {
            reason = 'bad_index';
            break;
          }
          if (number < 0) number += s.vertices.length;
          if (number < 1 || number >= s.vertices.length) {
            reason = 'out_of_range';
            break;
          }
          resolved.add(number);
        }
        if (reason != null) {
          s.errors.add((index + 1, reason));
        } else {
          s.polygons.add(
            Polygon(s.polygons.length + 1, index + 1, group, resolved),
          );
        }
      case 'g':
        group = args.isEmpty ? 'default' : args[0];
      default:
        if (ignored.contains(keyword)) {
          s.ignored++;
        } else {
          s.errors.add((index + 1, 'unknown_keyword'));
        }
    }
  }
  return s;
}

List<String> repairedOBJ(List<Vec> points, List<Face> faces) {
  final lines = [
    '# vertices ${points.length - 1} faces ${faces.length}',
    for (final p in points.skip(1)) 'v ${vecText(p)}',
  ];
  String? previous;
  for (final f in faces) {
    if (f.group != previous) {
      lines.add('g ${f.group}');
      previous = f.group;
    }
    lines.add('f ${listing(f.vertices)}');
  }
  return lines;
}
