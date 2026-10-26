import 'grid.dart';

bool startsRun(Grid grid, int row, int column, int dr, int dc) => grid.isOpen(row, column) && !grid.isOpen(row - dr, column - dc);
int runLength(Grid grid, int row, int column, int dr, int dc) {
  var length = 0;
  while (grid.isOpen(row + length * dr, column + length * dc)) {
    length++;
  }
  return length;
}

String shortRunError(Grid grid) {
  for (var row = 0; row < grid.height; row++) {
    for (var column = 0; column < grid.width; column++) {
      for (final (dr, dc, direction) in [(0, 1, 'across'), (1, 0, 'down')]) {
        if (startsRun(grid, row, column, dr, dc) && runLength(grid, row, column, dr, dc) == 2) {
          return 'short slot at ${grid.location(grid.cell(row, column))} $direction';
        }
      }
    }
  }
  return '';
}

class Slot {
  final int index;
  final int number;
  final bool across;
  final List<int> cells;
  final String label;
  var crossings = <int>[];
  Slot(this.index, this.number, this.across, this.cells) : label = '$number${across ? 'A' : 'D'}';
  int get length => cells.length;
}

class Layout {
  final Grid grid;
  late final List<int> numbers;
  late final List<int> acrossSlot;
  late final List<int> downSlot;
  final slots = <Slot>[];
  Layout(this.grid) {
    numbers = List.filled(grid.cells.length, 0);
    acrossSlot = List.filled(grid.cells.length, -1);
    downSlot = List.filled(grid.cells.length, -1);
    var nextNumber = 0;
    for (var row = 0; row < grid.height; row++) {
      for (var column = 0; column < grid.width; column++) {
        for (final (dr, dc, across) in [(0, 1, true), (1, 0, false)]) {
          if (!startsRun(grid, row, column, dr, dc)) {
            continue;
          }
          final length = runLength(grid, row, column, dr, dc);
          if (length < 3) {
            continue;
          }
          final start = grid.cell(row, column);
          if (numbers[start] == 0) {
            numbers[start] = ++nextNumber;
          }
          final cells = List.generate(length, (i) => grid.cell(row + i * dr, column + i * dc));
          final index = slots.length;
          final owners = across ? acrossSlot : downSlot;
          for (final cell in cells) {
            owners[cell] = index;
          }
          slots.add(Slot(index, numbers[start], across, cells));
        }
      }
    }
    for (final slot in slots) {
      final owners = slot.across ? downSlot : acrossSlot;
      slot.crossings = [for (final cell in slot.cells) if (owners[cell] >= 0) owners[cell]]..sort();
    }
  }
  int ownerCount(int cell) => (acrossSlot[cell] >= 0 ? 1 : 0) + (downSlot[cell] >= 0 ? 1 : 0);
  int get orphanCell {
    for (final cell in grid.whiteCells) {
      if (ownerCount(cell) == 0) {
        return cell;
      }
    }
    return -1;
  }
}
