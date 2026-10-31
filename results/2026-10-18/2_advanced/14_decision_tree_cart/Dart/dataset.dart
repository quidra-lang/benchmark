import 'dart:io';

class Attribute {
  final int index;
  final String name;
  final bool integer;
  final List<String> values;
  Attribute(this.index, this.name, this.integer, this.values);
}

class Row {
  final String id;
  final List<int?> values;
  final int label;
  Row(this.id, this.values, this.label);
  int get missing => values.where((value) => value == null).length;
}

class Settings {
  final int maxDepth, minSplit, minLeaf, maxSurrogates, folds;
  final List<int> curve;
  final int bagTrees, bagSeed, repeats, permutationSeed;
  Settings(Map<String, List<int>> entries)
      : maxDepth = entries['MAX_DEPTH']![0],
        minSplit = entries['MIN_SAMPLES_SPLIT']![0],
        minLeaf = entries['MIN_SAMPLES_LEAF']![0],
        maxSurrogates = entries['MAX_SURROGATES']![0],
        folds = entries['FOLDS']![0],
        curve = entries['CURVE']!,
        bagTrees = entries['BAG_TREES']![0],
        bagSeed = entries['BAG_SEED']![0],
        repeats = entries['PERMUTATION_REPEATS']![0],
        permutationSeed = entries['PERMUTATION_SEED']![0];
}

class Dataset {
  final List<Attribute> attributes;
  final String target;
  final List<String> classes;
  final List<Row> train, validation, test;
  final Settings settings;
  Dataset(this.attributes, this.target, this.classes, this.train, this.validation, this.test, this.settings);
}

List<String> readLines(String path) => File(path).readAsLinesSync();

List<Row> readRows(String path, List<Attribute> attributes, List<String> classes) {
  final rows = <Row>[];
  for (final line in readLines(path).skip(1)) {
    final fields = line.split(',');
    final values = <int?>[];
    for (final attribute in attributes) {
      final text = fields[attribute.index + 1];
      values.add(text == '?' ? null : attribute.integer ? int.parse(text) : attribute.values.indexOf(text));
    }
    rows.add(Row(fields[0], values, classes.indexOf(fields.last)));
  }
  return rows;
}

Dataset loadDataset() {
  final attributes = <Attribute>[];
  late String target;
  late List<String> classes;
  for (final line in readLines('input/schema.txt')) {
    final fields = line.split(' ');
    if (fields[0] == 'ATTRIBUTE') {
      attributes.add(Attribute(attributes.length, fields[1], fields[2] == 'INT', fields.skip(3).toList()));
    } else {
      target = fields[1];
      classes = fields.skip(2).toList();
    }
  }
  final entries = <String, List<int>>{};
  for (final line in readLines('input/params.txt')) {
    final fields = line.split(' ');
    entries[fields[0]] = fields.skip(1).map(int.parse).toList();
  }
  return Dataset(attributes, target, classes,
      readRows('input/train.csv', attributes, classes),
      readRows('input/validation.csv', attributes, classes),
      readRows('input/test.csv', attributes, classes), Settings(entries));
}
