part of 'main.dart';

String fixed(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return s.startsWith('-') && !s.substring(1).contains(RegExp('[1-9]'))
      ? s.substring(1)
      : s;
}

String timeText(int t) =>
    '${t ~/ 1000}.${(t % 1000).toString().padLeft(3, '0')}';
String cell(Mesh mesh, int p) => '${p ~/ mesh.w} ${p % mesh.w}';
List<String> fieldLines(Mesh mesh, List<double> x) => [
  for (var r = 0; r < mesh.h; r++)
    [for (var c = 0; c < mesh.w; c++) fixed(x[r * mesh.w + c], 2)].join(' '),
];
(List<String>, List<int>) isotherm(
  Mesh mesh,
  List<double> x,
  List<double> bands,
) {
  final hot = hottest(x),
      counts = List.filled(bands.length + 1, 0),
      out = <String>[];
  for (var r = 0; r < mesh.h; r++) {
    final row = StringBuffer();
    for (var c = 0; c < mesh.w; c++) {
      final p = r * mesh.w + c, level = bands.where((b) => b <= x[p]).length;
      counts[level]++;
      row.write(p == hot ? '*' : level);
    }
    out.add(row.toString());
  }
  return (out, counts);
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}
