import 'dart:math';
import 'clues.dart';
import 'line_solver.dart';

String stateChar(int state) => ['?', '#', '.'][state];
int charState(String char) => switch (char) { '?' => cellUnknown, '#' => cellFilled, '.' => cellEmpty, _ => throw StateError(char) };
String stateString(List<int> cells) => cells.map(stateChar).join();
List<String> gridDisplay(List<String> names, List<Grid> grids) => ['grid ${names.join(' ')}', for (var r = 0; r < grids.first.length; r++) grids.map((grid) => stateString(grid[r])).join(' | ')];
List<String> answerSheet(Clues rows, Clues columns, Grid grid) {
  final tokens = columns.map((clue) => spaced(clue).split(' ')).toList(); var width = 0, depth = 0, margin = 0;
  for (final column in tokens) { depth = max(depth, column.length); for (final token in column) { width = max(width, token.length + 1); } } for (final clue in rows) { margin = max(margin, spaced(clue).length); }
  final lines = <String>[];
  for (var line = 0; line < depth; line++) { var text = ' ' * margin; for (final column in tokens) { final skip = depth - column.length; text += line >= skip ? column[line - skip].padLeft(width) : ' ' * width; } lines.add(text.trimRight()); }
  for (var r = 0; r < rows.length; r++) { lines.add(spaced(rows[r]).padLeft(margin) + grid[r].map((state) => '${' ' * (width - 1)}${stateChar(state)}').join()); } return lines;
}
