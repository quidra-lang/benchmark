part of 'main.dart';

typedef Point = (double, double);

class Example {
  final String id;
  final Point point;
  final int label;
  Example(this.id, this.point, this.label);
  Example withLabel(int label) => Example(id, point, label);
}

class Params {
  final cs = <double>[], kernels = <Kernel>[], learning = <int>[];
  double tolerance = 0,
      epsilon = 0,
      multiclassC = 0,
      lambda = 0,
      xMin = 0,
      xMax = 0,
      yMin = 0,
      yMax = 0;
  int maxPasses = 0,
      folds = 0,
      newton = 0,
      iterations = 0,
      seed = 0,
      w = 0,
      h = 0;
  String multiclass = '';
}

List<String> lines(String path) => File(path).readAsLinesSync();
Example parseExample(List<String> a) =>
    Example(a[0], (double.parse(a[1]), double.parse(a[2])), int.parse(a[3]));
List<Example> readExamples(String path) =>
    lines(path).skip(1).map((s) => parseExample(s.split(','))).toList();
(List<Example>, List<Example>) readMulticlass() {
  final train = <Example>[], test = <Example>[];
  for (final line in lines('input/multiclass.csv').skip(1)) {
    final a = line.split(',');
    (a[4] == 'train' ? train : test).add(parseExample(a));
  }
  return (train, test);
}

Params readParams() {
  final p = Params();
  for (final line in lines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'C_GRID':
        p.cs.addAll(a.sublist(1).map(double.parse));
      case 'KERNEL':
        p.kernels.add(
          Kernel(
            a[1],
            a[2],
            a[2] == 'poly' ? int.parse(a[3]) : 0,
            a[2] == 'poly'
                ? double.parse(a[4])
                : a[2] == 'rbf'
                ? double.parse(a[3])
                : 0,
            a[2] == 'poly' ? double.parse(a[5]) : 0,
          ),
        );
      case 'TOLERANCE':
        p.tolerance = double.parse(a[1]);
      case 'EPS':
        p.epsilon = double.parse(a[1]);
      case 'MAX_PASSES':
        p.maxPasses = int.parse(a[1]);
      case 'FOLDS':
        p.folds = int.parse(a[1]);
      case 'LEARNING_CURVE':
        p.learning.addAll(a.sublist(1).map(int.parse));
      case 'NEWTON_ITERATIONS':
        p.newton = int.parse(a[1]);
      case 'MULTICLASS':
        p.multiclass = a[1];
        p.multiclassC = double.parse(a[2]);
      case 'PEGASOS':
        p.lambda = double.parse(a[1]);
        p.iterations = int.parse(a[2]);
        p.seed = int.parse(a[3]);
      case 'PLOT_X':
        p.xMin = double.parse(a[1]);
        p.xMax = double.parse(a[2]);
      case 'PLOT_Y':
        p.yMin = double.parse(a[1]);
        p.yMax = double.parse(a[2]);
      case 'PLOT_SIZE':
        p.w = int.parse(a[1]);
        p.h = int.parse(a[2]);
    }
  }
  return p;
}
