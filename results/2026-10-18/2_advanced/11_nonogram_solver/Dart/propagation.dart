import 'line_solver.dart';

String lineLabel(bool isRow, int index) => '${isRow ? 'R' : 'C'}${index + 1}';
List<int> lineCells(Grid grid, bool isRow, int index) => isRow ? [...grid[index]] : [for (final row in grid) row[index]];
int determinedCount(Grid grid) => grid.fold(0, (sum, row) => sum + row.where((state) => state != cellUnknown).length);
class PropagationStep {
  final bool isRow, contradiction;
  final int index, gain;
  PropagationStep(this.isRow, this.index, this.gain, this.contradiction);
  String label() => lineLabel(isRow, index);
  String text() => '${label()}${contradiction ? '!' : '+$gain'}';
}
class Propagation {
  final steps = <PropagationStep>[];
  PropagationStep? conflict;
  int lineSolves() => steps.length;
  String record() => steps.map((step) => step.text()).join(' ');
}
Propagation propagate(Grid grid, Clues rows, Clues columns, bool precise, List<bool> rowMarks, List<bool> columnMarks) {
  final result = Propagation();
  while (true) {
    var index = rowMarks.indexOf(true); final isRow = index >= 0;
    if (!isRow) { index = columnMarks.indexOf(true); if (index < 0) return result; }
    if (isRow) { rowMarks[index] = false; } else { columnMarks[index] = false; }
    final cells = lineCells(grid, isRow, index);
    final solved = solveLine(cells, isRow ? rows[index] : columns[index], precise);
    if (solved == null) { final step = PropagationStep(isRow, index, 0, true); result.steps.add(step); result.conflict = step; return result; }
    var gain = 0;
    for (var position = 0; position < solved.length; position++) {
      final state = solved[position]; if (cells[position] != cellUnknown || state == cellUnknown) continue; gain++;
      if (isRow) { grid[index][position] = state; columnMarks[position] = true; } else { grid[position][index] = state; rowMarks[position] = true; }
    }
    result.steps.add(PropagationStep(isRow, index, gain, false));
  }
}
