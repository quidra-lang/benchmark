import 'dart:math';
import 'line_solver.dart';
import 'propagation.dart';

(int, int)? guessCell(Grid grid) {
  final rowCounts = [for (final row in grid) row.where((state) => state == cellUnknown).length], columnCounts = List.filled(grid.first.length, 0);
  for (final row in grid) { for (var c = 0; c < row.length; c++) { if (row[c] == cellUnknown) columnCounts[c]++; } }
  (int, int)? best; var bestScore = 0;
  for (var r = 0; r < grid.length; r++) { for (var c = 0; c < grid[r].length; c++) { if (grid[r][c] != cellUnknown) continue; final score = rowCounts[r] + columnCounts[c]; if (best == null || score < bestScore) { best = (r, c); bestScore = score; } } } return best;
}
class Guess {
  final int number, depth, row, column, value, solves, known;
  final String result;
  Guess(this.number, this.depth, this.row, this.column, this.value, this.solves, this.known, this.result);
}
class Search {
  final Clues rows, columns;
  final guesses = <Guess>[], solutions = <Grid>[];
  int backtracks = 0;
  Search(this.rows, this.columns);
  int guessCount() => guesses.length;
  int maxDepth() => guesses.fold(0, (depth, guess) => max(depth, guess.depth));
  int lineSolves() => guesses.fold(0, (sum, guess) => sum + guess.solves);
  bool run(Grid grid, [int depth = 1]) {
    final (row, column) = guessCell(grid)!;
    for (final value in [cellFilled, cellEmpty]) {
      final number = guesses.length + 1, child = [for (final states in grid) [...states]], rowMarks = List.filled(rows.length, false), columnMarks = List.filled(columns.length, false);
      child[row][column] = value; rowMarks[row] = columnMarks[column] = true;
      final propagation = propagate(child, rows, columns, true, rowMarks, columnMarks), known = determinedCount(child); late String result;
      if (propagation.conflict != null) { result = 'contradiction at=${propagation.conflict!.label()}'; backtracks++; }
      else if (known == rows.length * columns.length) { solutions.add(child); result = 'solution${solutions.length}'; }
      else { result = 'open'; }
      guesses.add(Guess(number, depth, row, column, value, propagation.lineSolves(), known, result));
      if (result == 'open') { if (run(child, depth + 1)) return true; } else if (solutions.length == 2) { return true; }
    }
    return false;
  }
}
