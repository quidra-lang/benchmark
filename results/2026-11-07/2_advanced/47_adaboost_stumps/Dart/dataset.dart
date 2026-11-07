part of 'main.dart';

class Row {
  final String id;
  final List<double> values;
  final int label;
  Row(this.id, this.values, this.label);
}

class Params {
  final int rounds, bins, folds, classes, sammeRounds, permutations;
  final double smoothing, convergence, clip;
  final List<String> variants;
  final List<double> margins, shrinkage;
  final int permutationSeed, noiseSeed, bootstrap, bootstrapSeed;
  final List<int> noise, sizes;
  Params(Map<String, List<String>> v)
    : rounds = int.parse(v['ROUNDS']![0]),
      variants = v['VARIANTS']!,
      bins = int.parse(v['BINS']![0]),
      smoothing = double.parse(v['SMOOTHING']![0]),
      convergence = double.parse(v['CONVERGENCE']![0]),
      clip = double.parse(v['CLIP']![0]),
      folds = int.parse(v['FOLDS']![0]),
      margins = v['MARGINS']!.map(double.parse).toList(),
      classes = int.parse(v['CLASSES']![0]),
      sammeRounds = int.parse(v['SAMME_ROUNDS']![0]),
      permutations = int.parse(v['PERMUTATION']![0]),
      permutationSeed = int.parse(v['PERMUTATION']![1]),
      noiseSeed = int.parse(v['NOISE']![0]),
      noise = v['NOISE']!.skip(1).map(int.parse).toList(),
      sizes = v['SIZES']!.map(int.parse).toList(),
      shrinkage = v['SHRINKAGE']!.map(double.parse).toList(),
      bootstrap = int.parse(v['BOOTSTRAP']![0]),
      bootstrapSeed = int.parse(v['BOOTSTRAP']![1]);
}

class Inputs {
  final List<String> features, multiFeatures;
  final List<Row> train, test, multiTrain, multiTest;
  final Params params;
  Inputs(
    this.features,
    this.train,
    this.test,
    this.multiFeatures,
    this.multiTrain,
    this.multiTest,
    this.params,
  );
}

List<String> readLines(String path) => File(path).readAsLinesSync();
(List<String>, List<Row>) readBinary(String path) {
  final lines = readLines(path), header = lines.first.split(',');
  final rows = <Row>[];
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    rows.add(
      Row(
        f[0],
        f.sublist(1, f.length - 1).map(double.parse).toList(),
        int.parse(f.last),
      ),
    );
  }
  return (header.sublist(1, header.length - 1), rows);
}

Inputs readInputs() {
  final (features, train) = readBinary('input/train.csv');
  final (_, test) = readBinary('input/test.csv');
  final lines = readLines('input/multiclass.csv'),
      header = lines.first.split(',');
  final mt = <Row>[], mv = <Row>[];
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    final row = Row(
      f[0],
      f.sublist(1, f.length - 2).map(double.parse).toList(),
      int.parse(f[f.length - 2]),
    );
    (f.last == 'train' ? mt : mv).add(row);
  }
  final params = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    params[f.first] = f.sublist(1);
  }
  return Inputs(
    features,
    train,
    test,
    header.sublist(1, header.length - 2),
    mt,
    mv,
    Params(params),
  );
}
