const cellUnknown = 0, cellFilled = 1, cellEmpty = 2;
typedef Grid = List<List<int>>;
typedef Clues = List<List<int>>;
typedef Given = (int, int, int);

List<List<bool>> fitTable(List<int> cells, List<int> clue) {
  final empties = [0]; for (final state in cells) { empties.add(empties.last + (state == cellEmpty ? 1 : 0)); }
  final table = List.generate(cells.length + 1, (_) => List.filled(clue.length + 1, false)); table[0][0] = true;
  for (var end = 1; end <= cells.length; end++) {
    for (var count = 0; count <= clue.length; count++) {
      var fits = cells[end - 1] != cellFilled && table[end - 1][count];
      if (!fits && count > 0) { final start = end - clue[count - 1]; if (start >= 0 && empties[end] == empties[start]) fits = start == 0 ? count == 1 : cells[start - 1] != cellFilled && table[start - 1][count - 1]; }
      table[end][count] = fits;
    }
  }
  return table;
}
class LinePlacements {
  final List<int> cells, clue;
  late final List<List<bool>> before, after;
  LinePlacements(this.cells, this.clue) { before = fitTable(cells, clue); after = fitTable(cells.reversed.toList(), clue.reversed.toList()); }
  bool consistent() => before[cells.length][clue.length];
  bool canStart(int block, int start) {
    final end = start + clue[block]; for (var j = start; j < end; j++) { if (cells[j] == cellEmpty) return false; }
    final left = start == 0 ? block == 0 : cells[start - 1] != cellFilled && before[start - 1][block], rest = clue.length - block - 1;
    final right = end == cells.length ? rest == 0 : cells[end] != cellFilled && after[cells.length - end - 1][rest]; return left && right;
  }
  List<int> starts(int block) => [for (var start = 0; start <= cells.length - clue[block]; start++) if (canStart(block, start)) start];
  bool canBeEmpty(int index) {
    if (cells[index] == cellFilled) return false;
    for (var blocks = 0; blocks <= clue.length; blocks++) { if (before[index][blocks] && after[cells.length - index - 1][clue.length - blocks]) return true; } return false;
  }
}
bool hasPlacement(List<int> cells, List<int> clue) => LinePlacements(cells, clue).consistent();
List<int>? solveLine(List<int> cells, List<int> clue, bool precise) {
  final placements = LinePlacements(cells, clue); if (!placements.consistent()) return null;
  final solved = [...cells], possible = List.filled(cells.length, false);
  for (var block = 0; block < clue.length; block++) {
    final length = clue[block], starts = placements.starts(block);
    if (precise) { for (final start in starts) { for (var j = start; j < start + length; j++) { possible[j] = true; } } }
    else { final low = starts.first, high = starts.last; for (var j = high; j < low + length; j++) { if (solved[j] == cellUnknown) solved[j] = cellFilled; } for (var j = low; j < high + length; j++) { possible[j] = true; } }
  }
  for (var j = 0; j < cells.length; j++) {
    if (cells[j] != cellUnknown) continue;
    if (precise) { final empty = placements.canBeEmpty(j); if (possible[j] && !empty) { solved[j] = cellFilled; } else if (empty && !possible[j]) { solved[j] = cellEmpty; } }
    else if (!possible[j]) { solved[j] = cellEmpty; }
  }
  return solved;
}
