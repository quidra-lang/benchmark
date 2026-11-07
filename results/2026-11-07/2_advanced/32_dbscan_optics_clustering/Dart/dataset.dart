part of 'main.dart';

class Point {
  final int id, x, y;
  Point(this.id, this.x, this.y);
}

class Params {
  final Map<String, List<String>> fields;
  Params(this.fields);
  List<int> integers(String key) => fields[key]!.map(int.parse).toList();
  int integer(String key, [int index = 0]) => int.parse(fields[key]![index]);
  List<int> get eps => integers('EPS');
  List<int> get extract => integers('EXTRACT_EPS');
  int get minPts => integer('MIN_PTS');
  int get maxEps => integer('OPTICS_MAX_EPS');
  int get xiMinSize => integer('XI_MIN_SIZE');
  String get xiText => fields['XI']!.first;
  int get xiU => int.parse(xiText.split('/')[0]);
  int get xiV => int.parse(xiText.split('/')[1]);
  int get mapWidth => integer('MAP_SIZE');
  int get mapHeight => integer('MAP_SIZE', 1);
  int get kdistWidth => integer('KDIST_PLOT');
  int get kdistHeight => integer('KDIST_PLOT', 1);
  int get plotWidth => integer('PLOT_WIDTH');
}

List<Point> readPoints() {
  final points = <Point>[];
  for (final line in File('input/points.csv').readAsLinesSync().skip(1)) {
    final fields = line.split(',').map(int.parse).toList();
    points.add(Point(fields[0], fields[1], fields[2]));
  }
  points.sort((a, b) => a.id.compareTo(b.id));
  return points;
}

Params readParams() => Params({
  for (final line in File('input/params.txt').readAsLinesSync())
    line.split(' ').first: line.split(' ').skip(1).toList(),
});
