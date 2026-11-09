part of 'main.dart';

class Params {
  final List<List<String>> rows;
  Params(this.rows);
  int i(int row, [int col = 0]) => int.parse(rows[row][col]);
  double d(int row, [int col = 0]) => double.parse(rows[row][col]);
  String s(int row, [int col = 0]) => rows[row][col];
  int get m => i(0);
  String get mainWindow => s(1);
  double get threshold => d(2);
  int get peakCount => i(3);
  double get fundamental => d(4);
  int get width => i(4, 1);
  int get l => i(5);
  String get welchWindow => s(5, 1);
  int get f => i(6);
  int get hop => i(6, 1);
  int get shadeBand => i(6, 2);
  String get spectrogramWindow => s(6, 3);
  double get onset => d(7);
  int get p1 => i(8);
  int get p2 => i(8, 1);
  int get b1 => i(9);
  int get b2 => i(9, 1);
  int get notch => i(10);
  int get notchWidth => i(10, 1);
  int get e1 => i(11);
  int get e2 => i(11, 1);
  int get z1 => i(12);
  int get z2 => i(12, 1);
  int get j => i(12, 2);
  List<double> get fir => rows[13].map(double.parse).toList();
  int get maxLag => i(14);
  List<int> get bands => rows[15].map(int.parse).toList();
  int get t1 => i(16);
  int get t2 => i(16, 1);
  int get block => i(17);
}

(int, List<double>, List<double>, Params) readInput() {
  final lines = File('input/signal.csv').readAsLinesSync(),
      header = lines.first.split(','),
      fs = int.parse(header[0]),
      n = int.parse(header[1]);
  final x = <double>[], y = <double>[];
  for (var i = 0; i < n; i++) {
    final row = lines[i + 1].split(',');
    x.add(double.parse(row[0]));
    y.add(double.parse(row[1]));
  }
  final p = Params(
    File(
      'input/params.txt',
    ).readAsLinesSync().map((s) => s.split(' ').sublist(1)).toList(),
  );
  return (fs, x, y, p);
}
