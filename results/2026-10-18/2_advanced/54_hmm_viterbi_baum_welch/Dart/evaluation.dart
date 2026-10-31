part of 'main.dart';

List<List<int>> intMatrix(int rows, int columns) =>
    List.generate(rows, (_) => List.filled(columns, 0));
int gcd(int a, int b) {
  a = a.abs();
  b = b.abs();
  while (b != 0) {
    final old = b;
    b = a % b;
    a = old;
  }
  return a;
}

String fraction(int a, int b) {
  if (b == 0) {
    return '-';
  }
  if (b < 0) {
    a = -a;
    b = -b;
  }
  final d = gcd(a, b);
  return '${a ~/ d}/${b ~/ d}';
}

int correctCount(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i]) {
      count++;
    }
  }
  return count;
}

void addConfusion(
  List<List<int>> table,
  List<int> truth,
  List<int> prediction,
) {
  for (var i = 0; i < truth.length; i++) {
    table[truth[i]][prediction[i]]++;
  }
}

List<String> confusionLines(List<List<int>> table, List<String> states) {
  var width = 1;
  for (final row in table) {
    for (final v in row) {
      width = max(width, '$v'.length);
    }
  }
  var header = ' ';
  for (final state in states) {
    header += ' ${state.padLeft(width)}';
  }
  final lines = <String>[header];
  for (var i = 0; i < table.length; i++) {
    var line = states[i];
    for (final value in table[i]) {
      line += ' ${'$value'.padLeft(width)}';
    }
    lines.add(line);
  }
  return lines;
}

List<String> metricsLines(List<List<int>> table, List<String> states) {
  final k = states.length,
      rows = List.filled(states.length, 0),
      columns = List.filled(states.length, 0);
  var total = 0, correct = 0;
  for (var i = 0; i < k; i++) {
    for (var j = 0; j < k; j++) {
      final value = table[i][j];
      rows[i] += value;
      columns[j] += value;
      total += value;
      if (i == j) {
        correct += value;
      }
    }
  }
  var expected = 0;
  for (var i = 0; i < k; i++) {
    expected += rows[i] * columns[i];
  }
  return [
    'ACCURACY ${fraction(correct, total)}',
    'KAPPA ${fraction(total * correct - expected, total * total - expected)}',
    for (var i = 0; i < k; i++)
      'STATE ${states[i]} precision ${fraction(table[i][i], columns[i])} recall ${fraction(table[i][i], rows[i])} f1 ${fraction(2 * table[i][i], rows[i] + columns[i])}',
  ];
}

class Run {
  final int state, start, end;
  Run(this.state, this.start, this.end);
}

List<Run> runs(List<int> path) {
  final result = <Run>[];
  for (var start = 0; start < path.length;) {
    var end = start;
    while (end + 1 < path.length && path[end + 1] == path[start]) {
      end++;
    }
    result.add(Run(path[start], start, end));
    start = end + 1;
  }
  return result;
}

class Segment {
  final int start, end;
  Segment(this.start, this.end);
}

bool overlaps(Segment a, Segment b) =>
    max(a.start, b.start) <= min(a.end, b.end);
(int, int) regionMatches(List<Segment> predicted, List<Segment> truth) => (
  predicted.where((p) => truth.any((t) => overlaps(p, t))).length,
  truth.where((t) => predicted.any((p) => overlaps(p, t))).length,
);
List<int> boundaries(List<int> path) => [
  for (var i = 1; i < path.length; i++)
    if (path[i] != path[i - 1]) i + 1,
];
(int, int) boundaryMatches(
  List<int> predicted,
  List<int> truth,
  int tolerance,
) => (
  predicted.where((p) => truth.any((t) => (p - t).abs() <= tolerance)).length,
  truth.where((t) => predicted.any((p) => (p - t).abs() <= tolerance)).length,
);
String encode(List<int> indices, List<String> names) =>
    indices.map((i) => names[i]).join();
