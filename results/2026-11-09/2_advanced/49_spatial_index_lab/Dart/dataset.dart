part of 'main.dart';

class SpatialObject {
  final int id;
  final Box box;
  SpatialObject(this.id, this.box);
}

class Params {
  final int world, bucket, maximum, minimum, cellSize;
  Params(this.world, this.bucket, this.maximum, this.minimum, this.cellSize);
}

class Command {
  final String name;
  final List<int> values;
  Command(this.name, this.values);
}

List<String> readLines(String path) => File(path).readAsLinesSync();
List<SpatialObject> readObjects(String path, bool points) {
  final objects = <SpatialObject>[];
  for (final line in readLines(path).skip(1)) {
    final v = line.split(',').map(int.parse).toList();
    objects.add(
      SpatialObject(
        v[0],
        points ? Box(v[1], v[2], v[1], v[2]) : Box(v[1], v[2], v[3], v[4]),
      ),
    );
  }
  return objects;
}

(List<SpatialObject>, List<SpatialObject>, Params, List<Command>)
readDataset() {
  final points = readObjects('input/points.csv', true),
      rects = readObjects('input/rects.csv', false),
      v = readLines('input/params.txt').map((s) => s.split(' ')).toList();
  final p = Params(
    int.parse(v[0][1]),
    int.parse(v[1][1]),
    int.parse(v[2][1]),
    int.parse(v[2][2]),
    int.parse(v[3][1]),
  );
  final commands = <Command>[];
  for (final line in readLines('input/queries.txt')) {
    final f = line.split(' ');
    commands.add(Command(f.first, f.skip(1).map(int.parse).toList()));
  }
  return (points, rects, p, commands);
}
