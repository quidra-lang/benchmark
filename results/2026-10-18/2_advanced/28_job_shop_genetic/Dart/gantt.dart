import 'dart:math' as math;

typedef Interval = (int, int, String);
(int, int) chartScale(int makespan, int width) {
  for (var magnitude = 1; ; magnitude *= 10) {
    for (final step in [1, 2, 5]) {
      final scale = step * magnitude,
          columns = (makespan + step * magnitude - 1) ~/ (step * magnitude);
      if (columns <= width) return (scale, columns);
    }
  }
}

String timeRow(int scale, int columns) {
  var row = 'time';
  for (var c = 0; c < columns; c += 10) {
    row = '${row.padRight(6 + c)}${c * scale}';
  }
  return row;
}

String ruleRow(int columns) =>
    '      ${[for (var c = 0; c < columns; c++) c % 10 == 0 ? '+' : '-'].join()}';
String framed(String label, String marks) => '${label.padRight(4)} |$marks|';
String chartRow(
  String label,
  List<Interval> intervals,
  int scale,
  int columns,
) {
  final ordered = List<Interval>.of(intervals)
        ..sort((a, b) => a.$1.compareTo(b.$1)),
      marks = <String>[];
  for (var c = 0; c < columns; c++) {
    var best = 0, mark = '.';
    for (final v in ordered) {
      final overlap =
          math.min(v.$2, (c + 1) * scale) - math.max(v.$1, c * scale);
      if (overlap > best) {
        best = overlap;
        mark = v.$3;
      }
    }
    marks.add(mark);
  }
  return framed(label, marks.join());
}

String busyRow(
  List<List<Interval>> intervals,
  int scale,
  int columns,
) => framed(
  'busy',
  [
    for (var c = 0; c < columns; c++)
      '${intervals.where((row) => row.any((v) => v.$1 <= c * scale && c * scale < v.$2)).length == 10 ? 'X' : intervals.where((row) => row.any((v) => v.$1 <= c * scale && c * scale < v.$2)).length}',
  ].join(),
);
