import 'grid.dart';
import 'slots.dart';

String decimal(int numerator, int denominator, int places) {
  var scale = 1;
  for (var i = 0; i < places; i++) {
    scale *= 10;
  }
  final rounded = (2 * numerator * scale + denominator) ~/ (2 * denominator);
  return '${rounded ~/ scale}.${(rounded % scale).toString().padLeft(places, '0')}';
}

List<String> gridLines(Grid grid, List<int> letters) => [for (var row = 0; row < grid.height; row++) String.fromCharCodes(letters.sublist(row * grid.width, (row + 1) * grid.width))];
List<String> numberLines(Layout layout) {
  final grid = layout.grid;
  final lines = <String>[];
  for (var row = 0; row < grid.height; row++) {
    final marks = <String>[];
    for (var column = 0; column < grid.width; column++) {
      final cell = grid.cell(row, column);
      if (grid.cells[cell] == 35) {
        marks.add('##');
      } else if (layout.numbers[cell] > 0) {
        marks.add(layout.numbers[cell].toString().padLeft(2));
      } else {
        marks.add(' .');
      }
    }
    lines.add(marks.join(' '));
  }
  return lines;
}

String listLine(Slot slot, String clue, String entry, String score, bool theme) => '${slot.number}. $clue (${slot.length}) $entry $score${theme ? ' theme' : ''}';
