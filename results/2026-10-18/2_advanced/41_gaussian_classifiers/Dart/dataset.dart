part of 'main.dart';

class Row {
  final int id;
  final List<double> values;
  final String label;
  int classIndex = 0;
  Row(this.id, this.values, this.label);
}

class Subset {
  final String name;
  final List<int> features;
  Subset(this.name, this.features);
}

class Params {
  late String prior;
  late double epsilon, gamma, outlier;
  late List<double> smoothing, gammaGrid, edges, reject;
  late List<int> curve;
  late int folds, bootstrap, seed;
  late (int, int) mapSize, plotSize;
  final subsets = <Subset>[];
  final pairs = <(int, int)>[];
}

class Dataset {
  final List<String> features, classes;
  final List<Row> train, test;
  final List<List<double>> costs;
  final Params params;
  Dataset(
    this.features,
    this.classes,
    this.train,
    this.test,
    this.costs,
    this.params,
  );
}

List<String> readLines(String path) => File(path).readAsLinesSync();
List<double> decimals(Iterable<String> values) =>
    values.map(double.parse).toList();
List<int> integers(Iterable<String> values) => values.map(int.parse).toList();
(List<String>, List<Row>) readTable(String path) {
  final lines = readLines(path),
      header = lines.first.split(','),
      rows = <Row>[];
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    rows.add(
      Row(int.parse(f[0]), decimals(f.sublist(1, f.length - 1)), f.last),
    );
  }
  return (header.sublist(1, header.length - 1), rows);
}

Dataset readInputs() {
  final (features, train) = readTable('input/train.csv');
  final (_, test) = readTable('input/test.csv');
  final classes = train.map((r) => r.label).toSet().toList()..sort();
  final indices = {for (var i = 0; i < classes.length; i++) classes[i]: i};
  for (final r in [...train, ...test]) {
    r.classIndex = indices[r.label]!;
  }
  final names = {for (var i = 0; i < features.length; i++) features[i]: i};
  final v = <String, List<String>>{}, p = Params();
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    if (f[0] == 'SUBSET') {
      p.subsets.add(Subset(f[1], [for (final s in f.skip(2)) names[s]!]));
    } else if (f[0] == 'PAIR') {
      p.pairs.add((names[f[1]]!, names[f[2]]!));
    } else {
      v[f[0]] = f.sublist(1);
    }
  }
  p.prior = v['PRIOR']![0];
  p.epsilon = double.parse(v['VAR_SMOOTHING']![0]);
  p.gamma = double.parse(v['QDA_GAMMA']![0]);
  p.outlier = double.parse(v['OUTLIER_THRESHOLD']![0]);
  p.smoothing = decimals(v['SMOOTHING_GRID']!);
  p.gammaGrid = decimals(v['GAMMA_GRID']!);
  p.edges = decimals(v['CALIBRATION_EDGES']!);
  p.reject = decimals(v['REJECT_THRESHOLDS']!);
  p.curve = integers(v['CURVE']!);
  p.folds = int.parse(v['CV_FOLDS']![0]);
  p.bootstrap = int.parse(v['BOOTSTRAP']![0]);
  p.seed = int.parse(v['BOOTSTRAP']![1]);
  p.mapSize = (int.parse(v['MAP_SIZE']![0]), int.parse(v['MAP_SIZE']![1]));
  p.plotSize = (int.parse(v['PLOT_SIZE']![0]), int.parse(v['PLOT_SIZE']![1]));
  final lines = readLines('input/costs.csv'),
      columns = lines.first.split(',').skip(1).toList(),
      costs = zeros(classes.length);
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    for (var j = 0; j < columns.length; j++) {
      costs[indices[f[0]]!][indices[columns[j]]!] = double.parse(f[j + 1]);
    }
  }
  return Dataset(features, classes, train, test, costs, p);
}
