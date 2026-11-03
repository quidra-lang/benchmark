part of 'main.dart';

class Mesh {
  final int w, h;
  final double dx, thickness;
  final List<String> codes;
  final List<List<int>> neighbors;
  Mesh(this.w, this.h, this.dx, this.thickness, this.codes)
    : neighbors = List.generate(w * h, (p) {
        final r = p ~/ w, c = p % w;
        return [
          c > 0 ? p - 1 : -1,
          c + 1 < w ? p + 1 : -1,
          r > 0 ? p - w : -1,
          r + 1 < h ? p + w : -1,
        ];
      });
  (List<int>, int) segmentCells(String edge, int start, int end) {
    final cells = <int>[];
    var face = 0;
    for (var i = start; i <= end; i++) {
      switch (edge) {
        case 'left':
          face = 0;
          cells.add(i * w);
        case 'right':
          face = 1;
          cells.add(i * w + w - 1);
        case 'top':
          face = 2;
          cells.add(i);
        case 'bottom':
          face = 3;
          cells.add((h - 1) * w + i);
      }
    }
    return (cells, face);
  }

  List<int> sourceCells(int r1, int c1, int r2, int c2) => [
    for (var r = r1; r <= r2; r++)
      for (var c = c1; c <= c2; c++) r * w + c,
  ];
}

List<String> readLines(String path) => File(path).readAsLinesSync();
Mesh readMesh() {
  final lines = readLines('input/plate.txt'), a = lines.first.split(' ');
  return Mesh(
    int.parse(a[0]),
    int.parse(a[1]),
    double.parse(a[2]),
    double.parse(a[3]),
    lines.skip(1).join().split(''),
  );
}
