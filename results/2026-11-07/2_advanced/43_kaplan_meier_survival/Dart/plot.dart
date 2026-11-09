part of 'main.dart';

List<String> curveLines(
  List<List<Subject>> collections,
  List<List<KMRow>> estimates,
  int width,
  int height,
  int limit,
) {
  final cells = List.generate(height, (_) => List.filled(width, 0)),
      step = limit ~/ width;
  for (var g = 0; g < collections.length; g++) {
    final maximum = collections[g].map((s) => s.time).reduce(math.max),
        mask = 1 << g;
    var previous = -1;
    for (var column = 0; column < width; column++) {
      final t = column * step;
      if (t > maximum) break;
      final q = math.min(
        height - 1,
        (rowAt(estimates[g], t).survival * height).floor(),
      );
      cells[q][column] |= mask;
      if (previous >= 0 && previous - 1 > q) {
        for (var v = q + 1; v < previous; v++) {
          cells[v][column] |= mask;
        }
      }
      previous = q;
    }
  }
  final border = '   +${'-' * width}+', lines = [border];
  for (var q = height - 1; q >= 0; q--) {
    final text = <String>[];
    for (final mask in cells[q]) {
      if (mask == 0) {
        text.add(' ');
      } else if ((mask & (mask - 1)) != 0) {
        text.add('*');
      } else {
        text.add(String.fromCharCode(65 + mask.bitLength - 1));
      }
    }
    lines.add('${(100 * q ~/ height).toString().padLeft(3)}|${text.join()}|');
  }
  lines.add(border);
  return lines;
}
