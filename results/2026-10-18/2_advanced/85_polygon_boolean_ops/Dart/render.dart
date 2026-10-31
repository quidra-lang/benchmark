part of 'main.dart';

class Rendered {
  final List<String> rows = [];
  int result = 0, a = 0, b = 0, both = 0;
}

Rendered render(
  Result result,
  int x0,
  int y0,
  int cw,
  int ch,
  int cols,
  int rows,
) {
  final out = Rendered(), rings = flatten(result.polygons);
  for (var j = 0; j < rows; j++) {
    final row = <String>[];
    for (var i = 0; i < cols; i++) {
      final p = Point(
        rational(x0).add(ratio((2 * i + 1) * cw, 2)),
        rational(y0).add(ratio((2 * (rows - 1 - j) + 1) * ch, 2)),
      );
      var character = '.';
      if (interior(p, rings)) {
        character = '#';
        out.result++;
      } else if (result.a != null && result.b != null) {
        final a = interior(p, result.a!.rings),
            b = interior(p, result.b!.rings);
        if (a && b) {
          character = '+';
          out.both++;
        } else if (a) {
          character = 'a';
          out.a++;
        } else if (b) {
          character = 'b';
          out.b++;
        }
      }
      row.add(character);
    }
    out.rows.add(row.join());
  }
  return out;
}
