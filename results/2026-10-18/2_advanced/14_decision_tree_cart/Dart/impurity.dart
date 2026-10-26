import 'dataset.dart';

typedef Fraction = (int, int);

class Statistics {
  final int size;
  final List<int> counts;
  final int squares, majority, errors;
  Statistics(this.size, this.counts, this.squares, this.majority, this.errors);
}

int sum(Iterable<int> values) => values.fold(0, (total, value) => total + value);

int majority(List<int> counts) {
  var selected = 0;
  for (var index = 1; index < counts.length; index++) {
    if (counts[index] > counts[selected]) selected = index;
  }
  return selected;
}

int squareSum(List<int> counts) => counts.fold(0, (total, count) => total + count * count);

Statistics statistics(List<Row> rows, int classes) {
  final counts = List.filled(classes, 0);
  for (final row in rows) { counts[row.label]++; }
  final selected = majority(counts);
  return Statistics(rows.length, counts, squareSum(counts), selected, rows.length - counts[selected]);
}

int compareFractions(Fraction first, Fraction second) =>
    (first.$1 * second.$2).compareTo(second.$1 * first.$2);

Fraction quality(Statistics left, Statistics right) =>
    (left.squares * right.size + right.squares * left.size, left.size * right.size);

bool improves(Fraction value, Statistics parent) => value.$1 * parent.size > parent.squares * value.$2;

double impurityDecrease(Statistics parent, Statistics left, Statistics right) {
  final first = left.squares / left.size;
  final second = right.squares / right.size;
  final before = parent.squares / parent.size;
  return (first + second) - before;
}
