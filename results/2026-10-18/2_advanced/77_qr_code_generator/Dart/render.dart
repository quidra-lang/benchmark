part of 'main.dart';

List<String> symbolLines(List<List<int>> a) => [
  for (final row in a) row.map((v) => v == 1 ? '#' : '.').join(),
];
String pbm(List<List<int>> a, int quiet, int scale) {
  final n = a.length,
      width = (n + 2 * quiet) * scale,
      out = StringBuffer(
        'P1\n${(n + 2 * quiet) * scale} ${(n + 2 * quiet) * scale}\n',
      );
  for (var py = 0; py < width; py++) {
    for (var px = 0; px < width; px++) {
      final x = px ~/ scale - quiet, y = py ~/ scale - quiet;
      out.write(x >= 0 && y >= 0 && x < n && y < n && a[y][x] == 1 ? '1' : '0');
    }
    out.writeln();
  }
  return out.toString();
}
