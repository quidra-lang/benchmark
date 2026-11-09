part of 'main.dart';

typedef Point = (int, int);

class Series {
  final String name;
  final points = <Point>[];
  Series(this.name);
}

List<String> readLines(String path) => File(path).readAsLinesSync();
int hundredths(String text) => int.parse(text.replaceAll('.', ''));

class Settings {
  final Map<String, List<String>> fields;
  Settings(this.fields);
  List<String> get windows => fields['WINDOWS']!;
  List<String> get kernels => fields['KERNELS']!;
  List<String> get bandwidths => fields['BANDWIDTHS']!;
  List<String> get degrees => fields['LOESS_DEGREES']!;
  List<String> get spans => fields['SPANS']!;
  List<String> get lambdas => fields['LAMBDAS']!;
  List<String> get isotonic => fields['ISOTONIC']!;
  List<String> get bandMethods => fields['BAND_METHODS']!;
  List<String> get plotSeries => fields['PLOT_SERIES']!;
  List<String> get plotMethods => fields['PLOT_METHODS']!;
  int get robustIterations => int.parse(fields['ROBUST_ITERATIONS']![0]);
  int get folds => int.parse(fields['CV_FOLDS']![0]);
  int get gridPoints => int.parse(fields['GRID_POINTS']![0]);
  double get bandZ => double.parse(fields['BAND_Z']![0]);
  double get threshold => hundredths(fields['OUTLIER_THRESHOLD']![0]) / 100;
  int get bootstrap => int.parse(fields['BOOTSTRAP']![0]);
  int get trim => int.parse(fields['BOOTSTRAP']![1]);
  int get seed => int.parse(fields['BOOTSTRAP']![2]);
  int get width => int.parse(fields['PLOT_SIZE']![0]);
  int get height => int.parse(fields['PLOT_SIZE']![1]);
}

(List<Series>, List<(String, int)>, Settings) readDataset() {
  final table = <String, Series>{};
  for (final line in readLines('input/series.csv').skip(1)) {
    final f = line.split(',');
    final series = table.putIfAbsent(f[0], () => Series(f[0]));
    series.points.add((hundredths(f[1]), hundredths(f[2])));
  }
  for (final series in table.values) {
    series.points.sort((a, b) => a.$1.compareTo(b.$1));
  }
  final tests = [
    for (final line in readLines('input/test_points.csv').skip(1))
      (line.split(',')[0], hundredths(line.split(',')[1])),
  ];
  final fields = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final words = line.split(' ');
    fields[words[0]] = words.sublist(1);
  }
  return (table.values.toList(), tests, Settings(fields));
}

(List<int>, List<double>) pointData(List<Point> points) =>
    (points.map((p) => p.$1).toList(), points.map((p) => p.$2 / 100).toList());
