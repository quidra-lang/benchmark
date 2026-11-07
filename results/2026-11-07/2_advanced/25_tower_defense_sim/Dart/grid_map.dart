import 'dart:io';

typedef Point = (int, int);
Point cellCenter(Point cell) => (100 * cell.$1, 100 * cell.$2);
class GridMap {
  final int width;
  final int height;
  final List<String> rows;
  late final Point exit;
  final List<Point> spawns = [];
  GridMap(this.width, this.height, this.rows) {
    final found = <int, Point>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final terrain = rows[y][x];
        if ('123456789'.contains(terrain)) {
          found[int.parse(terrain)] = (x, y);
        } else if (terrain == 'E') {
          exit = (x, y);
        }
      }
    }
    for (var number = 1; number <= found.length; number++) { spawns.add(found[number]!); }
  }
  bool inside(Point cell) => cell.$1 >= 0 && cell.$1 < width && cell.$2 >= 0 && cell.$2 < height;
  String terrain(Point cell) => rows[cell.$2][cell.$1];
  bool isRock(Point cell) => terrain(cell) == '#';
  bool isWater(Point cell) => terrain(cell) == '~';
  bool buildable(Point cell) => terrain(cell) == '.';
}
GridMap readMap() {
  final lines = File('input/map.txt').readAsLinesSync();
  final fields = lines[0].split(' ').map(int.parse).toList();
  return GridMap(fields[0], fields[1], lines.sublist(1, fields[1] + 1));
}
