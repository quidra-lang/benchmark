part of 'main.dart';

class Point {
  final double x, y;
  const Point(this.x, this.y);
}

class DataPoint {
  final String id;
  final Point point;
  DataPoint(this.id, this.point);
}

class Covariance {
  final double a, b, c;
  const Covariance(this.a, this.b, this.c);
}

class Component {
  final double weight;
  final Point mean;
  final Covariance cov;
  Component(this.weight, this.mean, this.cov);
}

typedef Model = List<Component>;

class Params {
  final List<int> k;
  final int iterations, kmeansMax, folds, width, height;
  final List<String> types;
  final double epsilon,
      tolerance,
      uncertain,
      lowDensity,
      xmin,
      xmax,
      ymin,
      ymax;
  final List<double> gofEdges;
  Params(Map<String, List<String>> v)
    : k = v['K']!.map(int.parse).toList(),
      iterations = int.parse(v['ITERATIONS']![0]),
      types = v['TYPES']!,
      epsilon = double.parse(v['REGULARIZATION']![0]),
      tolerance = double.parse(v['SETTLE_TOLERANCE']![0]),
      kmeansMax = int.parse(v['KMEANS_MAX_ITERATIONS']![0]),
      folds = int.parse(v['CV_FOLDS']![0]),
      uncertain = double.parse(v['UNCERTAIN_THRESHOLD']![0]),
      lowDensity = double.parse(v['LOW_DENSITY_THRESHOLD']![0]),
      gofEdges = v['GOF_EDGES']!.map(double.parse).toList(),
      xmin = double.parse(v['MAP_X']![0]),
      xmax = double.parse(v['MAP_X']![1]),
      ymin = double.parse(v['MAP_Y']![0]),
      ymax = double.parse(v['MAP_Y']![1]),
      width = int.parse(v['MAP_SIZE']![0]),
      height = int.parse(v['MAP_SIZE']![1]);
}

List<String> readLines(String path) => File(path).readAsLinesSync();
(List<DataPoint>, Map<int, Model>, Params) readDataset() {
  final points = <DataPoint>[];
  for (final line in readLines('input/points.csv').skip(1)) {
    final f = line.split(',');
    points.add(DataPoint(f[0], Point(double.parse(f[1]), double.parse(f[2]))));
  }
  final values = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    values[f.first] = f.sublist(1);
  }
  final initial = <int, Model>{}, lines = readLines('input/init.txt');
  var cursor = 0;
  while (cursor < lines.length) {
    if (lines[cursor].isEmpty) {
      cursor++;
      continue;
    }
    final k = int.parse(lines[cursor].split(' ')[1]),
        weights = lines[cursor + 1]
            .split(' ')
            .skip(1)
            .map(double.parse)
            .toList(),
        model = <Component>[];
    for (var j = 0; j < k; j++) {
      final f = lines[cursor + j + 2].split(' ');
      model.add(
        Component(
          weights[j],
          Point(double.parse(f[2]), double.parse(f[3])),
          Covariance(
            double.parse(f[4]),
            double.parse(f[5]),
            double.parse(f[6]),
          ),
        ),
      );
    }
    initial[k] = model;
    cursor += k + 2;
  }
  return (points, initial, Params(values));
}
