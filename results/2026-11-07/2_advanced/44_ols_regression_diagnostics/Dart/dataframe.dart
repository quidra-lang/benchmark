part of 'main.dart';

class Value {
  final double? number;
  final String? label;
  Value({this.number, this.label});
  bool get present => number != null || label != null;
}

typedef DataRow = Map<String, Value>;

class DataFrame {
  final List<String> columns;
  final Map<String, bool> categorical;
  final List<DataRow> rows;
  DataFrame(this.columns, this.categorical, this.rows);
}

class Params {
  final double tolerance,
      alpha,
      confidence,
      leverage,
      studentized,
      cook,
      dffits,
      vif,
      dw,
      bp,
      normal,
      limit;
  final int best, width, height;
  Params(
    this.tolerance,
    this.alpha,
    this.confidence,
    this.leverage,
    this.studentized,
    this.cook,
    this.dffits,
    this.vif,
    this.dw,
    this.bp,
    this.normal,
    this.best,
    this.width,
    this.height,
    this.limit,
  );
}

List<String> readLines(String path) => File(path).readAsLinesSync();
DataFrame readCSV(String path, [Map<String, bool>? kinds]) {
  final lines = readLines(path),
      columns = lines.first.split(','),
      records = [for (final line in lines.skip(1)) line.split(',')],
      categories = <String, bool>{};
  for (var j = 0; j < columns.length; j++) {
    final c = columns[j];
    categories[c] = kinds != null
        ? kinds[c]!
        : records.any(
            (r) =>
                r[j] != 'NA' &&
                r[j].codeUnitAt(0) >= 65 &&
                r[j].codeUnitAt(0) <= 90,
          );
  }
  final rows = <DataRow>[];
  for (final r in records) {
    final row = <String, Value>{};
    for (var j = 0; j < columns.length; j++) {
      final c = columns[j], v = r[j];
      row[c] = v == 'NA'
          ? Value()
          : categories[c]!
          ? Value(label: v)
          : Value(number: double.parse(v));
    }
    rows.add(row);
  }
  return DataFrame(columns, categories, rows);
}

Params readParams() {
  final v = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    v[f[0]] = f.sublist(1);
  }
  double get(String key) => double.parse(v[key]![0]);
  return Params(
    get('RANK_TOL'),
    get('ALPHA_REMOVE'),
    get('CONFIDENCE'),
    get('LEVERAGE'),
    get('STUDENTIZED'),
    get('COOK'),
    get('DFFITS'),
    get('VIF'),
    get('DURBIN_WATSON'),
    get('BREUSCH_PAGAN'),
    get('NORMALITY'),
    int.parse(v['BEST_SUBSETS']![0]),
    int.parse(v['PLOT']![0]),
    int.parse(v['PLOT']![1]),
    double.parse(v['PLOT']![2]),
  );
}
