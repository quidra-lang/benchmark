part of 'main.dart';

int samplesPerTick(int rate, int tempo) => rate * 5 ~/ (tempo * 2);
(int, int)? nextRow(Song song, int position, int row) {
  int? jump, patternBreak;
  for (final cell in song.cells(position, row)) {
    final e = cell.effect;
    if (e == null) continue;
    if (e.name == 'F' && e.value == 0) return null;
    if (e.name == 'B') {
      jump = e.value;
    } else if (e.name == 'D') {
      patternBreak = e.value;
    }
  }
  if (jump == null && patternBreak == null)
    return row < 63 ? (position, row + 1) : (position + 1, 0);
  return (
    jump ?? position + 1,
    patternBreak == null || patternBreak >= 64 ? 0 : patternBreak,
  );
}

Set<(int, int)> reachableRows(Song song) {
  final reached = <(int, int)>{};
  var current = (0, 0);
  while (reached.add(current)) {
    final next = nextRow(song, current.$1, current.$2);
    if (next == null || next.$1 >= song.order.length) break;
    current = next;
  }
  return reached;
}
