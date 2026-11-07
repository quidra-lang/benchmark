part of 'main.dart';

class Table {
  final List<String> names, ids;
  final List<List<double?>> rows;
  Table(this.names, this.ids, this.rows);
}

class Settings {
  final String missing, scaling, components;
  final double target, t2Limit, speLimit;
  final int parallel,
      seed,
      cycles,
      top,
      screeWidth,
      biplotWidth,
      biplotHeight,
      radius,
      diagnosticWidth,
      diagnosticHeight;
  Settings(
    this.missing,
    this.scaling,
    this.components,
    this.target,
    this.parallel,
    this.seed,
    this.t2Limit,
    this.speLimit,
    this.cycles,
    this.top,
    this.screeWidth,
    this.biplotWidth,
    this.biplotHeight,
    this.radius,
    this.diagnosticWidth,
    this.diagnosticHeight,
  );
}

class Dataset {
  final Table data, supplementary;
  final Settings settings;
  Dataset(this.data, this.supplementary, this.settings);
}

List<String> readLines(String path) => File(path).readAsLinesSync();
Table readTable(String path) {
  final lines = readLines(path),
      names = lines.first.split(',').skip(1).toList(),
      ids = <String>[],
      rows = <List<double?>>[];
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    ids.add(f.first);
    rows.add([for (final v in f.skip(1)) v == 'NA' ? null : double.parse(v)]);
  }
  return Table(names, ids, rows);
}

Settings readSettings() {
  final v = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    v[f[0]] = f.sublist(1);
  }
  return Settings(
    v['MISSING']![0],
    v['SCALING']![0],
    v['COMPONENTS']![0],
    double.parse(v['CUMULATIVE_TARGET']![0]),
    int.parse(v['PARALLEL']![0]),
    int.parse(v['PARALLEL']![1]),
    double.parse(v['T2_LIMIT']![0]),
    double.parse(v['SPE_LIMIT']![0]),
    int.parse(v['VARIMAX_CYCLES']![0]),
    int.parse(v['TOP_ROWS']![0]),
    int.parse(v['SCREE_WIDTH']![0]),
    int.parse(v['BIPLOT_SIZE']![0]),
    int.parse(v['BIPLOT_SIZE']![1]),
    int.parse(v['CIRCLE_RADIUS']![0]),
    int.parse(v['DIAGNOSTIC_SIZE']![0]),
    int.parse(v['DIAGNOSTIC_SIZE']![1]),
  );
}

Dataset readDataset() => Dataset(
  readTable('input/data.csv'),
  readTable('input/supplementary.csv'),
  readSettings(),
);
