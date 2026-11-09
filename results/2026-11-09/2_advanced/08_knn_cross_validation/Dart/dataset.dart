import 'dart:io';

class DataRow {
  final String id;
  final List<double> values;
  final String? label;
  final double? target;
  DataRow(this.id, this.values, this.label, this.target);
}

class Settings {
  late final List<String> scalings, metrics, weightings;
  late final List<int> kValues, curve;
  late final List<double> bins;
  late final int folds, editK, top;
  Settings(String path) {
    final entries = <String, List<String>>{};
    for (final line in File(path).readAsLinesSync()) {
      final parts = line.split(' ');
      entries[parts.first] = parts.sublist(1);
    }
    scalings = entries['SCALINGS']!; metrics = entries['METRICS']!; weightings = entries['WEIGHTINGS']!;
    kValues = entries['K_VALUES']!.map(int.parse).toList(); curve = entries['CURVE']!.map(int.parse).toList();
    bins = entries['BINS']!.map(double.parse).toList(); folds = int.parse(entries['FOLDS']!.first);
    editK = int.parse(entries['EDIT_K']!.first); top = int.parse(entries['TOP']!.first);
  }
}

(List<String>, List<DataRow>) readRows(String name) {
  final lines = File('input/$name').readAsLinesSync(), header = lines.first.split(',');
  final rows = <DataRow>[];
  for (final line in lines.skip(1)) {
    final parts = line.split(','), label = parts[parts.length - 2], target = parts.last;
    rows.add(DataRow(parts.first, parts.sublist(1, parts.length - 2).map(double.parse).toList(), label.isEmpty ? null : label, target.isEmpty ? null : double.parse(target)));
  }
  return (header.sublist(1, header.length - 2), rows);
}
