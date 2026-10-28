import 'dart:io';
import 'dart:math' as math;

class Example {
  final String ident;
  final List<double> values;
  final int label;
  Example(this.ident, this.values, this.label);
}

class Settings {
  final Map<String, List<String>> fields;
  Settings()
    : fields = {
        for (final line in File('input/params.txt').readAsLinesSync())
          line.split(' ').first: line.split(' ').skip(1).toList(),
      };
  int integer(String key, [int i = 0]) => int.parse(fields[key]![i]);
  double real(String key, [int i = 0]) => double.parse(fields[key]![i]);
}

(List<String>, List<Example>) readExamples(String path) {
  final lines = File(path).readAsLinesSync();
  final header = lines.first.split(',');
  final examples = <Example>[];
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    examples.add(
      Example(
        f[0],
        f.sublist(1, f.length - 1).map(double.parse).toList(),
        int.parse(f.last),
      ),
    );
  }
  return (header.sublist(1, header.length - 1), examples);
}

List<List<int>> expansionTuples(int count, int degree) {
  final tuples = <List<int>>[];
  void visit(List<int> prefix, int start, int remaining) {
    if (remaining == 0) {
      tuples.add(List<int>.of(prefix));
      return;
    }
    for (var j = start; j < count; j++) {
      visit([...prefix, j], j, remaining - 1);
    }
  }

  for (var length = 1; length <= degree; length++) {
    visit([], 0, length);
  }
  return tuples;
}

List<String> expandedNames(List<String> names, List<List<int>> tuples) => [
  for (final indices in tuples) indices.map((j) => names[j]).join('*'),
];
List<double> expandedValues(List<List<int>> tuples, List<double> values) {
  final result = <double>[];
  for (final indices in tuples) {
    var product = values[indices.first];
    for (final j in indices.skip(1)) {
      product *= values[j];
    }
    result.add(product);
  }
  return result;
}

class Statistics {
  final List<double> means, deviations;
  Statistics(this.means, this.deviations);
}

Statistics computeStatistics(List<List<double>> rows, int count) {
  final means = <double>[], deviations = <double>[];
  for (var j = 0; j < count; j++) {
    var total = 0.0;
    for (final row in rows) {
      total += row[j];
    }
    final mean = total / rows.length;
    var squares = 0.0;
    for (final row in rows) {
      final difference = row[j] - mean;
      squares += difference * difference;
    }
    means.add(mean);
    deviations.add(math.sqrt(squares / (rows.length - 1)));
  }
  return Statistics(means, deviations);
}

List<double> standardize(List<double> values, Statistics s, int count) => [
  1.0,
  for (var j = 0; j < count; j++) (values[j] - s.means[j]) / s.deviations[j],
];
List<List<double>> standardizedRows(
  List<List<double>> rows,
  Statistics s,
  int count,
) => rows.map((row) => standardize(row, s, count)).toList();
